import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';

/// เก็บ vehicleId + token ไว้ให้ background isolate อ่านเอง — isolate ของ background
/// service เป็นคนละ Dart VM กับ UI หลัก เข้าถึง UserSession ในหน่วยความจำไม่ได้เลย
/// (secure storage เป็น plugin แยก เข้าถึงได้จากทุก isolate จึงใช้เป็นสะพานเชื่อมแทน)
const _kBgVehicleIdKey = 'bg_vehicle_id';
const _kBgTokenKey = 'bg_token';

const _uploadInterval = Duration(seconds: 5);
const _notificationId = 888;

/// ตามตำแหน่งเจ้าของต่อในพื้นหลัง แม้ปิดแอป/สลับไปแอปอื่นแล้ว เพื่อให้ auto-lock/auto-unlock
/// (ดู PUT /vehicles/{id}/owner-location ฝั่ง backend) ยังทำงานต่อได้ ไม่ใช่แค่ตอนเปิดหน้า
/// Live Tracking ค้างไว้เท่านั้น — เดิมพึ่ง GPS stream ในหน้าจอเพียงอย่างเดียว พอปิดแอป/สลับ
/// แอปไป auto-lock ก็หยุดทำงานทันที (ดู live_tracking_screen.dart _startOwnerTracking)
///
/// รันเป็น Android foreground service (มี notification ค้างตลอดตอนติดตามอยู่ — จงใจให้เห็น
/// เพื่อความโปร่งใส ไม่ใช่แอบติดตามเงียบๆ) ฝั่ง iOS ใช้ background location mode ซึ่ง OS
/// จะจำกัดความถี่เองตามดุลยพินิจ (ดูคอมเมนต์ในโค้ดฝั่ง native เพิ่มเติม)
class BackgroundLocationService {
  BackgroundLocationService._();
  static final BackgroundLocationService instance =
      BackgroundLocationService._();

  final _storage = const FlutterSecureStorage();
  bool _configured = false;

  /// เรียกครั้งเดียวตอนแอป start (ดู main.dart) — แค่ผูก handler ไว้กับ platform channel
  /// ยังไม่เริ่มขอ location จริงจนกว่าจะเรียก start()
  Future<void> configure() async {
    if (_configured) return;
    _configured = true;
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        // ไม่ระบุ notificationChannelId เอง — ปล่อยให้ปลั๊กอินสร้าง/จัดการ channel
        // "FOREGROUND_DEFAULT" ของมันเอง ถ้าใส่ id กำหนดเองตรงนี้ ปลั๊กอินจะ "ไม่" สร้าง
        // channel ให้ (สมมติว่าแอปสร้างไว้แล้วล่วงหน้า) — เจอ channel ไม่มีจริงบน
        // Android 14+ (API 34) จะ crash ทันทีด้วย CannotPostForegroundServiceNotificationException
        // (เจอมาแล้วตอนเทสบน Oppo Android 15 จริง)
        initialNotificationTitle: 'MFU Vehicle Tracker',
        initialNotificationContent: 'Watching your vehicle location',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// เรียกทุกครั้งที่ยืนยันแล้วว่า login อยู่ + มีรถลงทะเบียนอย่างน้อย 1 คัน
  /// (ดู HomeScreen._loadVehicle) เขียน vehicleId/token ทับของเดิมเสมอ เผื่อ token
  /// หมุนใหม่ระหว่าง session — ไม่ทำอะไรถ้า service วิ่งอยู่แล้ว
  Future<void> start({required String vehicleId, required String token}) async {
    await _storage.write(key: _kBgVehicleIdKey, value: vehicleId);
    await _storage.write(key: _kBgTokenKey, value: token);
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  /// เรียกตอน logout หรือลบรถคันเดียวที่มีทิ้ง (ไม่มีอะไรให้ track ต่อแล้ว)
  Future<void> stop() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
    }
    await _storage.delete(key: _kBgVehicleIdKey);
    await _storage.delete(key: _kBgTokenKey);
  }
}

/// รันอยู่ใน isolate แยกต่างหาก (background service isolate) ห้ามอ้างอิง state จาก UI
/// isolate ตรงๆ (UserSession, ApiClient ฯลฯ ใช้ไม่ได้ที่นี่) ต้องอ่าน token/vehicleId
/// จาก secure storage เองใหม่ทุกครั้งที่จะยิง request
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  const storage = FlutterSecureStorage();
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.backendUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  StreamSubscription<Position>? positionSub;
  DateTime? lastUpload;

  Future<void> stopAndCleanUp() async {
    await positionSub?.cancel();
    service.stopSelf();
  }

  service.on('stop').listen((event) => stopAndCleanUp());

  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
  } catch (_) {
    return;
  }

  Future<void> uploadOnce(Position position) async {
    // อ่านสดทุกครั้ง เผื่อ logout/ลบรถระหว่างที่ service ยังวิ่งอยู่ (stop() เขียนทับด้วยการลบ
    // key ทั้งคู่ทิ้ง — เจอ null ปุ๊บคือสัญญาณให้ service หยุดตัวเองด้วย ไม่ต้องรอ invoke('stop'))
    final vehicleId = await storage.read(key: _kBgVehicleIdKey);
    final token = await storage.read(key: _kBgTokenKey);
    if (vehicleId == null || token == null) {
      await stopAndCleanUp();
      return;
    }
    try {
      await dio.put(
        '/vehicles/$vehicleId/owner-location',
        data: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        // token หมดอายุ/ถูกเพิกถอน — เขียนซ้ำไปเรื่อยๆ ก็ไม่มีทางสำเร็จ หยุด service ทิ้ง
        // key ไว้ ให้ user เปิดแอปแล้ว login ใหม่ค่อยเริ่ม start() ให้เองอีกที
        await storage.delete(key: _kBgVehicleIdKey);
        await storage.delete(key: _kBgTokenKey);
        await stopAndCleanUp();
      }
      // error อื่น (network ล่ม ฯลฯ) เงียบไว้ — ping รอบถัดไปจาก stream จะลองใหม่เอง
    } catch (_) {
      // เงียบไว้ — ping รอบถัดไปจาก stream จะลองใหม่เอง ไม่ควรทำให้ service ทั้งตัวล้ม
    }
  }

  positionSub = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    ),
  ).listen((position) {
    final now = DateTime.now();
    if (lastUpload != null && now.difference(lastUpload!) < _uploadInterval) {
      return;
    }
    lastUpload = now;
    uploadOnce(position);
  });
}

@pragma('vm:entry-point')
bool _onIosBackground(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

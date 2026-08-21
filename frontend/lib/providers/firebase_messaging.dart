import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// เรียกหลัง login สำเร็จ: init Firebase, ขอ FCM token ของเครื่อง
/// แล้วส่งให้ backend ผูกกับ user (POST /me/device-token)
/// ห่อ try/catch ทั้งหมด — ถ้า platform ไม่รองรับหรือ backend ล่ม แอปต้องไม่พัง
Future<void> registerFcmToken(String baseUrl, String jwt) async {
  try {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    await Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    ).post(
      '/me/device-token',
      data: {'token': token},
      options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
    debugPrint('FCM token registered with backend');
  } catch (e) {
    debugPrint('FCM register failed: $e');
  }
}

/// เรียกก่อน logout: ถอด FCM token ของเครื่องนี้ออกจากบัญชีที่กำลังจะออกจากระบบ
/// ไม่งั้นเครื่องนี้จะยังได้ push ของบัญชีเดิมต่อแม้ logout ไปแล้ว (ถ้ามีคนอื่น login
/// เครื่องเดียวกันต่อ ทั้งสองบัญชีจะมี token เดียวกันผูกอยู่พร้อมกัน)
/// ห่อ try/catch ทั้งหมด — ถอด token ไม่สำเร็จก็ต้อง logout ต่อได้ปกติ
Future<void> unregisterFcmToken(String baseUrl, String jwt) async {
  try {
    await Firebase.initializeApp();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    ).delete(
      '/me/device-token',
      data: {'token': token},
      options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
    debugPrint('FCM token unregistered from backend');
  } catch (e) {
    debugPrint('FCM unregister failed: $e');
  }
}

class FirebaseMessagingProvider extends ChangeNotifier {
  final _messaging = FirebaseMessaging.instance;

  String? _token;
  final List<RemoteMessage> _messages = [];

  String? get token => _token;
  List<RemoteMessage> get messages => List.unmodifiable(_messages);

  Future<void> init() async {
    await _requestPermission();
    _token = await _messaging.getToken();
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _messaging.onTokenRefresh.listen((t) {
      _token = t;
      notifyListeners();
    });
    debugPrint("FCM token: $_token");
    notifyListeners();
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  void _onForegroundMessage(RemoteMessage message) {
    _messages.insert(0, message);
    notifyListeners();
  }
}

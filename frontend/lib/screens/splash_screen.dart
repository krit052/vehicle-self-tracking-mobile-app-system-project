import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/firebase_messaging.dart' show registerFcmToken;
import '../services/api_client.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// หน้าแรกสุดตอนเปิดแอป: เช็คว่ามี JWT ที่ยังใช้ได้เก็บไว้จากรอบก่อนไหม
/// (ปัดปิดแอป/ปิดเครื่องไม่ได้ล้าง token — ล้างเฉพาะตอนกด Logout เท่านั้น)
/// ถ้ามีและยังไม่หมดอายุ → เข้า home/admin-home ทันทีโดยไม่ต้อง login ซ้ำ
/// ถ้าไม่มีหรือหมดอายุแล้ว → ไปหน้า login ตามปกติ
///
/// ก่อนเช็ค session จะขอ location permission ก่อนเสมอ (แอปพึ่ง GPS เป็นแกนหลัก —
/// auto-lock/auto-unlock และ live tracking ใช้ไม่ได้เลยถ้าไม่มีตำแหน่ง) ถ้า user
/// ยังไม่เปิด location service หรือยังไม่ได้ให้สิทธิ์ จะค้างหน้านี้ไว้พร้อม dialog
/// จนกว่าจะเปิด/ให้สิทธิ์ — ไม่ปล่อยผ่านไป login/home เงียบๆ แล้วไปพังทีหลัง
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with WidgetsBindingObserver {
  final _storage = const FlutterSecureStorage();
  bool _waitingForLocationSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureLocationThenCheckSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // user สลับกลับมาจากหน้า Settings ของเครื่อง (หลังกดเปิด location/สิทธิ์แอป) →
    // ลองเช็คสิทธิ์ใหม่อีกรอบให้เอง ไม่ต้องรอ user มา retry เอง
    if (state == AppLifecycleState.resumed && _waitingForLocationSettings) {
      _waitingForLocationSettings = false;
      _ensureLocationThenCheckSession();
    }
  }

  Future<void> _ensureLocationThenCheckSession() async {
    final granted = await _ensureLocationPermission();
    if (!granted || !mounted) return;
    await _checkSession();
  }

  /// คืน true เมื่อ location service เปิดอยู่ + มีสิทธิ์เข้าถึงตำแหน่งแล้ว (อย่างน้อย
  /// while-in-use) ถ้ายังไม่ผ่านจะโชว์ dialog ค้างไว้จนกว่า user จะเปิด/ให้สิทธิ์
  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      await _showLocationDialog(
        title: 'เปิดใช้งานตำแหน่ง (Location)',
        message:
            'แอปนี้ต้องใช้ตำแหน่งของคุณเพื่อติดตามและล็อก/ปลดล็อกรถอัตโนมัติ '
            'กรุณาเปิดบริการตำแหน่ง (Location Services) ก่อนใช้งานแอป',
        actionLabel: 'เปิดตำแหน่ง',
        onAction: () async {
          _waitingForLocationSettings = true;
          await Geolocator.openLocationSettings();
        },
      );
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return false;
      await _showLocationDialog(
        title: 'ต้องการสิทธิ์เข้าถึงตำแหน่ง',
        message: 'กรุณาอนุญาตให้แอปเข้าถึงตำแหน่งของคุณเพื่อใช้งานต่อ',
        actionLabel: 'ลองอีกครั้ง',
        onAction: () async {},
      );
      return _ensureLocationPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      await _showLocationDialog(
        title: 'สิทธิ์เข้าถึงตำแหน่งถูกปิดถาวร',
        message:
            'กรุณาไปที่ตั้งค่าแอปแล้วเปิดสิทธิ์เข้าถึงตำแหน่ง (Location) '
            'เพื่อใช้งานแอปนี้ต่อ',
        actionLabel: 'เปิดตั้งค่าแอป',
        onAction: () async {
          _waitingForLocationSettings = true;
          await Geolocator.openAppSettings();
        },
      );
      return false;
    }

    return true;
  }

  Future<void> _showLocationDialog({
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await onAction();
              if (mounted) _ensureLocationThenCheckSession();
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _checkSession() async {
    String? token;
    try {
      token = await _storage.read(key: 'jwt_token');
    } catch (_) {}

    if (token == null || token.isEmpty) {
      _goTo('/login');
      return;
    }

    try {
      final res = await ApiClient.instance.dio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final user = Map<String, dynamic>.from(res.data as Map);
      UserSession.instance.token = token;
      UserSession.instance.role = user['role'] as String? ?? 'user';
      UserSession.instance.user = user;
      // ผูก FCM token ของเครื่องนี้ใหม่ทุกครั้งที่ resume session ค้างไว้ (ไม่ได้ผ่านหน้า
      // login) เผื่อ token หมุนใหม่ระหว่างที่ผู้ใช้ไม่เคย logout เลย — fire-and-forget
      registerFcmToken(token);
      _goTo(UserSession.instance.role == 'admin' ? '/admin-home' : '/home');
    } on DioException catch (e) {
      // 401/403 = token หมดอายุหรือถูกเพิกถอน → ล้างแล้วไป login
      // error อื่น (network ล่ม ฯลฯ) ก็ไป login เหมือนกัน ให้ผู้ใช้ลองใหม่เอง
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        try {
          await _storage.delete(key: 'jwt_token');
        } catch (_) {}
      }
      _goTo('/login');
    } catch (_) {
      _goTo('/login');
    }
  }

  void _goTo(String route) {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

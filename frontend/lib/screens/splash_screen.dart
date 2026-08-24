import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/firebase_messaging.dart' show registerFcmToken;
import '../theme/app_theme.dart';
import 'login_screen.dart' show UserSession;

const _baseUrl = 'https://primp-squeeze-dedicator.ngrok-free.dev';

/// หน้าแรกสุดตอนเปิดแอป: เช็คว่ามี JWT ที่ยังใช้ได้เก็บไว้จากรอบก่อนไหม
/// (ปัดปิดแอป/ปิดเครื่องไม่ได้ล้าง token — ล้างเฉพาะตอนกด Logout เท่านั้น)
/// ถ้ามีและยังไม่หมดอายุ → เข้า home/admin-home ทันทีโดยไม่ต้อง login ซ้ำ
/// ถ้าไม่มีหรือหมดอายุแล้ว → ไปหน้า login ตามปกติ
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkSession();
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
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).get('/auth/me');
      final user = Map<String, dynamic>.from(res.data as Map);
      UserSession.instance.token = token;
      UserSession.instance.role = user['role'] as String? ?? 'user';
      UserSession.instance.user = user;
      // ผูก FCM token ของเครื่องนี้ใหม่ทุกครั้งที่ resume session ค้างไว้ (ไม่ได้ผ่านหน้า
      // login) เผื่อ token หมุนใหม่ระหว่างที่ผู้ใช้ไม่เคย logout เลย — fire-and-forget
      registerFcmToken(_baseUrl, token);
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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import 'user_session.dart';

/// Dio client กลางตัวเดียวของทั้งแอป
///
/// เดิมทุกหน้าจอสร้าง `Dio(BaseOptions(baseUrl: ..., headers: {...}))` เองซ้ำๆ กัน (พบใน 14
/// ไฟล์) พร้อม copy-paste error handling เหมือนกันแทบทุกที่ ทำให้:
///   - แก้ timeout/baseUrl ต้องไล่แก้หลายจุด
///   - ไม่มีจุดกลางไว้ดัก 401 (token หมดอายุ) — แต่ละหน้าจัดการเอง ไม่เหมือนกัน
///
/// ตอนนี้รวมมาไว้ที่เดียว:
///   - แนบ Authorization header ให้อัตโนมัติทุก request (จาก UserSession ก่อน ถ้าไม่มีค่อย
///     อ่านจาก secure storage — เหมือน pattern `_getToken()` เดิมที่กระจายอยู่ทุกหน้าจอ)
///   - เจอ 401 จาก endpoint ที่ต้อง login (ไม่รวม /auth/* ซึ่ง 401 คือ "รหัสผ่านผิด" ปกติ
///     ไม่ใช่ "session หมดอายุ") → เคลียร์ session แล้วเด้งกลับไปหน้า login ให้อัตโนมัติ
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!options.headers.containsKey('Authorization')) {
            final token = await _resolveToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) {
          final path = error.requestOptions.path;
          final isAuthEndpoint = path.startsWith('/auth/');
          if (error.response?.statusCode == 401 && !isAuthEndpoint) {
            _handleSessionExpired();
          }
          handler.next(error);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  /// main.dart ตั้งค่านี้ให้ตอน build MaterialApp เพื่อให้ interceptor เด้งไปหน้า login
  /// ได้เอง แม้ตอนนั้นจะไม่มี BuildContext ของหน้าที่กำลังยิง request ค้างอยู่
  GlobalKey<NavigatorState>? navigatorKey;

  Dio get dio => _dio;

  Future<String?> _resolveToken() async {
    if (UserSession.instance.token != null) return UserSession.instance.token;
    try {
      return await _storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  bool _redirecting = false;

  Future<void> _handleSessionExpired() async {
    if (_redirecting) return;
    _redirecting = true;
    try {
      UserSession.instance.clear();
      try {
        await _storage.delete(key: 'jwt_token');
      } catch (_) {}
      navigatorKey?.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (_) => false,
      );
    } finally {
      _redirecting = false;
    }
  }
}

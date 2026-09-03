import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/splash_screen.dart';
import 'providers/firebase_messaging.dart';
import 'services/api_client.dart';
import 'services/background_location_service.dart';
import 'theme/app_theme.dart';

/// Navigator ระดับแอป — ให้ ApiClient เด้งไปหน้า login เองได้ตอน token หมดอายุ (401)
/// โดยไม่ต้องมี BuildContext ของหน้าที่กำลังยิง request อยู่ตอนนั้น
final navigatorKey = GlobalKey<NavigatorState>();

/// ผูก onMessage/onBackgroundMessage listener ไว้ตั้งแต่ app start เพื่อให้แอปที่เปิด
/// อยู่ (foreground) รับ push ได้จริง — ก่อนหน้านี้ provider นี้ถูกสร้างไว้แต่ไม่เคยมีใคร
/// เรียก init() เลย ทำให้ onMessage listener ไม่เคยถูกลงทะเบียน
final firebaseMessagingProvider = FirebaseMessagingProvider();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  ApiClient.instance.navigatorKey = navigatorKey;
  // ผูก handler ของ background location service ไว้ตั้งแต่ app start (ยังไม่เริ่มขอ
  // location จริงจนกว่า HomeScreen จะเรียก start() ตอนยืนยันว่า login + มีรถแล้ว)
  await BackgroundLocationService.instance.configure();
  await firebaseMessagingProvider.init();
  runApp(const MfuTrackerApp());
}

class MfuTrackerApp extends StatelessWidget {
  const MfuTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MFU Vehicle Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/forgotpassword': (context) => const ForgotScreen(),
        '/home': (context) => const HomeScreen(),
        '/admin-home': (context) => const AdminHomeScreen(),
      },
    );
  }
}

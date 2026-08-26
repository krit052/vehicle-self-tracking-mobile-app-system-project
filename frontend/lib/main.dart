import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_client.dart';
import 'theme/app_theme.dart';

/// Navigator ระดับแอป — ให้ ApiClient เด้งไปหน้า login เองได้ตอน token หมดอายุ (401)
/// โดยไม่ต้องมี BuildContext ของหน้าที่กำลังยิง request อยู่ตอนนั้น
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  MediaKit.ensureInitialized();
  ApiClient.instance.navigatorKey = navigatorKey;
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

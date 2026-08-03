import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  MediaKit.ensureInitialized();
  runApp(const MfuTrackerApp());
}

class MfuTrackerApp extends StatelessWidget {
  const MfuTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MFU Vehicle Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/forgotpassword': (context) => const ForgotScreen(),
        '/home': (context) => const HomeScreen(),
        '/admin-home': (context) => const AdminHomeScreen(),
      },
    );
  }
}

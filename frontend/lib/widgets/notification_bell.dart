import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../screens/login_screen.dart';
import '../screens/notifications_screen.dart';

/// ไอคอนกระดิ่งแจ้งเตือนที่มี badge สีแดงบอกจำนวน unread
/// ดึงจำนวน unread จาก GET /notifications เอง และรีเฟรชหลังกลับจากหน้า Notifications
class NotificationBell extends StatefulWidget {
  final Color color;
  final EdgeInsetsGeometry? padding;

  const NotificationBell({
    super.key,
    this.color = AppColors.onPrimary,
    this.padding,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  static const _baseUrl = 'http://localhost:8001';
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final token = UserSession.instance.token;
    if (token == null) return;
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).get('/notifications');
      final data = (res.data as List).cast<Map<String, dynamic>>();
      final count = data.where((n) => (n['read'] as bool? ?? false) == false).length;
      if (!mounted) return;
      setState(() => _unread = count);
    } catch (_) {
      // เงียบไว้ — badge แค่ไม่อัปเดต ไม่ควรทำ UI พัง
    }
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    // กลับมาแล้วรีเฟรช (อาจมีการกดอ่านไปบางรายการ)
    _loadUnread();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _open,
      padding: widget.padding,
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_outlined, color: widget.color),
          if (_unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: Text(
                  _unread > 9 ? '9+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

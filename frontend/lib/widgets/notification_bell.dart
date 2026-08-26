import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../screens/notifications_screen.dart';

/// แหล่งความจริง "เดียว" ของจำนวนแจ้งเตือนที่ยังไม่อ่าน (unread)
/// ทุก NotificationBell ฟังตัวนี้ → อ่านแจ้งเตือนที่หน้าไหน badge ก็อัปเดตพร้อมกันทุกหน้า
class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  final ValueNotifier<int> unread = ValueNotifier(0);

  /// ตั้งค่า unread ตรง ๆ (หน้า Notifications คำนวณจากลิสต์ที่โหลดมาแล้ว)
  void setUnread(int count) => unread.value = count;

  /// ดึงจาก backend มานับ unread ใหม่
  Future<void> refresh() async {
    if (UserSession.instance.token == null) return;
    try {
      final res = await ApiClient.instance.dio.get('/notifications');
      final data = (res.data as List).cast<Map<String, dynamic>>();
      unread.value =
          data.where((n) => (n['read'] as bool? ?? false) == false).length;
    } catch (_) {
      // เงียบไว้ — badge แค่ไม่อัปเดต ไม่ควรทำ UI พัง
    }
  }
}

/// ไอคอนกระดิ่งแจ้งเตือนที่มี badge สีแดงบอกจำนวน unread
/// อ่านค่าจาก NotificationCenter (แหล่งเดียว) → sync กันทุกหน้า
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
  @override
  void initState() {
    super.initState();
    // ดึงยอดล่าสุดตอนสร้าง (เผื่อมีแจ้งเตือนใหม่เข้ามา) — อัปเดตเข้า NotificationCenter
    NotificationCenter.instance.refresh();
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    // กลับมาแล้วรีเฟรช (อาจมีการกดอ่านไปบางรายการ)
    NotificationCenter.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationCenter.instance.unread,
      builder: (context, unread, _) {
        return IconButton(
          onPressed: _open,
          padding: widget.padding,
          tooltip: 'Notifications',
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_outlined, color: widget.color),
              if (unread > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
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
      },
    );
  }
}

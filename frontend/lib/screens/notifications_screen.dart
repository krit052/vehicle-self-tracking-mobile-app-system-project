import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

final _mockAlerts = [
  _AlertItem(
    id: 'a1',
    alertType: 'MOVED',
    snapshotUrl: '',
    createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
  ),
  _AlertItem(
    id: 'a2',
    alertType: 'LOST',
    snapshotUrl: '',
    createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
  ),
  _AlertItem(
    id: 'a3',
    alertType: 'MOVED',
    snapshotUrl: '',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  ),
];

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _mockAlerts.isEmpty ? _buildEmpty() : _buildList(),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      title: const Text(
        'MFU TRACKER',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.5),
      ),
      centerTitle: false,
      leading: const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.account_circle, color: AppColors.onPrimary),
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.notifications, color: AppColors.onPrimary),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: _mockAlerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AlertCard(alert: _mockAlerts[i]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(36),
            ),
            child: const Icon(Icons.notifications_none, size: 36, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const Text('No notifications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
          const SizedBox(height: 4),
          const Text("You're all caught up",
              style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
        NavigationDestination(icon: Icon(Icons.history_outlined), label: 'History'),
        NavigationDestination(icon: Icon(Icons.motorcycle_sharp), label: 'Vehicle'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
      onDestinationSelected: (_) => Navigator.of(context).pop(),
    );
  }
}

// ── Alert Card ────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final _AlertItem alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _typeColor(alert.alertType), width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AlertIcon(type: alert.alertType),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _typeTitle(alert.alertType),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _typeColor(alert.alertType),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _bodyText(alert.alertType),
                    style: const TextStyle(fontSize: 13, color: AppColors.onSurface, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 12, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(_formatTime(alert.createdAt),
                          style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
        'MOVED' => const Color(0xFFE65100),
        'LOST'  => AppColors.error,
        _       => AppColors.onSurfaceVariant,
      };

  String _typeTitle(String type) => switch (type) {
        'MOVED' => 'Vehicle Moved',
        'LOST'  => 'Vehicle Lost',
        _       => 'Vehicle Alert',
      };

  String _bodyText(String type) => switch (type) {
        'MOVED' => 'Your vehicle has moved outside its geofence radius.',
        'LOST'  => 'Your vehicle has disappeared from camera view.',
        _       => 'An alert was triggered for your vehicle.',
      };

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays == 1)    return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _AlertIcon extends StatelessWidget {
  final String type;
  const _AlertIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = switch (type) {
      'MOVED' => (Icons.warning_amber_rounded,   const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      'LOST'  => (Icons.visibility_off_outlined, const Color(0xFFFFEDED), AppColors.error),
      _       => (Icons.notifications_outlined,  AppColors.surfaceContainer, AppColors.onSurfaceVariant),
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

// ── Data Model ────────────────────────────────────────────────────────────────

class _AlertItem {
  final String id;
  final String alertType;
  final String snapshotUrl;
  final DateTime createdAt;

  const _AlertItem({
    required this.id,
    required this.alertType,
    required this.snapshotUrl,
    required this.createdAt,
  });
}

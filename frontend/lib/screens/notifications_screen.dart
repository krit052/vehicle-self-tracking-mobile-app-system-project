import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _baseUrl = 'http://localhost:8001';

  List<_AlertItem> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Dio get _dio {
    final token = UserSession.instance.token;
    return Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));
  }

  Future<void> _fetchNotifications() async {
    if (UserSession.instance.token == null) {
      setState(() {
        _loading = false;
        _error = 'Not logged in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _dio.get('/notifications');
      final data = (res.data as List).cast<Map<String, dynamic>>();
      setState(() {
        _alerts = data.map(_AlertItem.fromJson).toList();
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _error = e.response?.data?['detail']?.toString() ??
            'Could not load notifications.';
      });
    }
  }

  Future<void> _markRead(String id, int index) async {
    try {
      await _dio.patch('/notifications/$id/read');
      setState(() {
        _alerts[index] = _alerts[index].copyWithRead(true);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final userName = UserSession.instance.user?['name'] as String?;
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      centerTitle: false,
      leading: Padding(
        padding: const EdgeInsets.all(10),
        child: CircleAvatar(
          backgroundColor: AppColors.primaryContainer,
          child: Text(
            userName != null && userName.isNotEmpty
                ? userName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
            ),
          ),
        ),
      ),
      title: const Text(
        'MFU TRACKER',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              const Icon(Icons.notifications, color: AppColors.onPrimary),
              if (_alerts.any((a) => !a.read))
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_alerts.isEmpty) return _buildEmpty();
    return _buildList();
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _fetchNotifications,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _fetchNotifications,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _alerts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _AlertCard(
          alert: _alerts[i],
          onTap: _alerts[i].read ? null : () => _markRead(_alerts[i].id, i),
        ),
      ),
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
            child: const Icon(
              Icons.notifications_none,
              size: 36,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "You're all caught up",
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
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
        NavigationDestination(
          icon: Icon(Icons.history_outlined),
          label: 'History',
        ),
        NavigationDestination(
          icon: Icon(Icons.motorcycle_sharp),
          label: 'Vehicle',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
      onDestinationSelected: (_) => Navigator.of(context).pop(),
    );
  }
}

// ── Alert Card ────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final _AlertItem alert;
  final VoidCallback? onTap;

  const _AlertCard({required this.alert, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: alert.read ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: _typeColor(alert.alertType), width: 4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 5,
              ),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _typeTitle(alert.alertType),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _typeColor(alert.alertType),
                              ),
                            ),
                          ),
                          if (!alert.read)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _typeColor(alert.alertType),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _bodyText(alert.alertType),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.onSurface,
                          height: 1.4,
                        ),
                      ),
                      if (alert.licensePlate.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.pin_outlined,
                              size: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                alert.cameraName.isNotEmpty
                                    ? '${alert.licensePlate}  ·  ${alert.cameraName}'
                                    : alert.licensePlate,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(alert.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
    'MOVED' => const Color(0xFFE65100),
    'LOST' => AppColors.error,
    'UNAUTHORIZED_MOVE' => AppColors.error,
    'PLATE_DETECTED' => AppColors.blue,
    _ => AppColors.onSurfaceVariant,
  };

  String _typeTitle(String type) => switch (type) {
    'MOVED' => 'Vehicle Moved',
    'LOST' => 'Vehicle Lost',
    'UNAUTHORIZED_MOVE' => 'Is This You?',
    'PLATE_DETECTED' => 'License Plate Detected',
    _ => 'Vehicle Alert',
  };

  String _bodyText(String type) => switch (type) {
    'MOVED' => 'Your vehicle has moved outside its geofence radius.',
    'LOST' => 'Your vehicle has disappeared from camera view.',
    'UNAUTHORIZED_MOVE' =>
      'Your vehicle left its zone without being unlocked. Confirm this was you.',
    'PLATE_DETECTED' =>
      'Your vehicle was detected by a campus CCTV camera.',
    _ => 'An alert was triggered for your vehicle.',
  };

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
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
      'MOVED' => (
        Icons.warning_amber_rounded,
        const Color(0xFFFFF3E0),
        const Color(0xFFE65100),
      ),
      'LOST' => (
        Icons.visibility_off_outlined,
        const Color(0xFFFFEDED),
        AppColors.error,
      ),
      'UNAUTHORIZED_MOVE' => (
        Icons.no_encryption_gmailerrorred_outlined,
        const Color(0xFFFFEDED),
        AppColors.error,
      ),
      'PLATE_DETECTED' => (
        Icons.pin_outlined,
        const Color(0xFFE3F2FD),
        AppColors.blue,
      ),
      _ => (
        Icons.notifications_outlined,
        AppColors.surfaceContainer,
        AppColors.onSurfaceVariant,
      ),
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
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
  final bool read;
  final String licensePlate;
  final String cameraName;

  const _AlertItem({
    required this.id,
    required this.alertType,
    required this.snapshotUrl,
    required this.createdAt,
    required this.read,
    this.licensePlate = '',
    this.cameraName = '',
  });

  factory _AlertItem.fromJson(Map<String, dynamic> json) => _AlertItem(
    id: json['id'] as String,
    alertType: json['alert_type'] as String? ?? 'INFO',
    snapshotUrl: json['snapshot_url'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    read: json['read'] as bool? ?? false,
    licensePlate: json['license_plate'] as String? ?? '',
    cameraName: json['camera_name'] as String? ?? '',
  );

  _AlertItem copyWithRead(bool read) => _AlertItem(
    id: id,
    alertType: alertType,
    snapshotUrl: snapshotUrl,
    createdAt: createdAt,
    read: read,
    licensePlate: licensePlate,
    cameraName: cameraName,
  );
}

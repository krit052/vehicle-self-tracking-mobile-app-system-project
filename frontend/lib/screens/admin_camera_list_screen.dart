import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_client.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import 'admin_camera_detail_screen.dart';
import 'admin_camera_map_screen.dart';

class AdminCameraListScreen extends StatefulWidget {
  const AdminCameraListScreen({super.key});

  @override
  State<AdminCameraListScreen> createState() => _AdminCameraListScreenState();
}

class _AdminCameraListScreenState extends State<AdminCameraListScreen> {
  final _storage = const FlutterSecureStorage();

  List<AdminCameraData> _cameras = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCameras();
    AdminCameraSync.instance.version.addListener(_loadCameras);
  }

  @override
  void dispose() {
    AdminCameraSync.instance.version.removeListener(_loadCameras);
    super.dispose();
  }

  Future<String?> _getToken() async {
    if (UserSession.instance.token != null) return UserSession.instance.token;
    try {
      return await _storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  Dio _dio(String token) => ApiClient.instance.dio;

  Future<void> _loadCameras() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await _getToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Not logged in.';
      });
      return;
    }
    try {
      final res = await _dio(token).get('/admin/cameras');
      final cameras = (res.data as List)
          .map((item) => AdminCameraData.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      // กล้องที่ยังไม่ปักหมุดขึ้นก่อน (จะได้เห็นตัวที่เพิ่งเพิ่มใน CSV/ACTIVE_CAMERAS ทันที)
      cameras.sort((a, b) {
        if (a.located != b.located) return a.located ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.data?['detail']?.toString() ?? 'Could not load cameras.';
      });
    }
  }

  void _openCamera(AdminCameraData camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminCameraDetailScreen(camera: camera),
      ),
    );
  }

  Future<void> _deleteCamera(AdminCameraData camera) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Camera'),
        content: Text('Delete "${camera.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = await _getToken();
    if (token == null) return;
    try {
      await _dio(token).delete('/admin/cameras/${camera.id}');
      AdminCameraSync.instance.notifyChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data?['detail']?.toString() ?? 'Could not delete camera.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: _loadCameras,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _cameras.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null && _cameras.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 40, color: AppColors.error),
          const SizedBox(height: 12),
          Center(
            child: Text(_error!, style: const TextStyle(color: AppColors.error)),
          ),
        ],
      );
    }
    if (_cameras.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.videocam_off_outlined, size: 40, color: AppColors.onSurfaceVariant),
          SizedBox(height: 12),
          Center(
            child: Text(
              'No cameras yet.\nAdd one from the Map tab.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _cameras.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final camera = _cameras[index];
        return Card(
          margin: EdgeInsets.zero,
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => _openCamera(camera),
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.2),
              child: const Icon(Icons.videocam, color: AppColors.primary),
            ),
            title: Text(camera.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: camera.located
                ? Text(
                    camera.locationName.isNotEmpty
                        ? camera.locationName
                        : '${camera.point.latitude.toStringAsFixed(5)}, ${camera.point.longitude.toStringAsFixed(5)}',
                  )
                : Row(
                    children: [
                      Icon(Icons.location_off_outlined, size: 14, color: AppColors.error),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          camera.locationName.isNotEmpty
                              ? '${camera.locationName} · ยังไม่ปักหมุด (แตะเพื่อตั้งพิกัด)'
                              : 'ยังไม่ปักหมุด — แตะเพื่อตั้งพิกัด',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Delete',
              onPressed: () => _deleteCamera(camera),
            ),
          ),
        );
      },
    );
  }
}

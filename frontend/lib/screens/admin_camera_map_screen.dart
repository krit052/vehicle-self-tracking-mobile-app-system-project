import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import 'admin_camera_detail_screen.dart';
import 'login_screen.dart';

// Notifies every open admin camera screen (Map/Camera tabs, detail screen)
// to reload after a camera is created, edited, or deleted anywhere.
class AdminCameraSync {
  AdminCameraSync._();
  static final AdminCameraSync instance = AdminCameraSync._();
  final ValueNotifier<int> version = ValueNotifier(0);
  void notifyChanged() => version.value++;
}

class AdminCameraMapScreen extends StatefulWidget {
  const AdminCameraMapScreen({super.key});

  @override
  State<AdminCameraMapScreen> createState() => _AdminCameraMapScreenState();
}

class _AdminCameraMapScreenState extends State<AdminCameraMapScreen> {
  static const _mfuCenter = LatLng(20.0459, 99.8934);
  static const _baseUrl = 'http://localhost:8001';

  final _mapController = MapController();
  final _storage = const FlutterSecureStorage();

  List<AdminCameraData> _cameras = [];
  bool _loading = true;
  String? _error;
  bool _placingCamera = false;

  @override
  void initState() {
    super.initState();
    _loadCameras();
    AdminCameraSync.instance.version.addListener(_loadCameras);
  }

  @override
  void dispose() {
    AdminCameraSync.instance.version.removeListener(_loadCameras);
    _mapController.dispose();
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

  Dio _dio(String token) => Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      headers: {'Authorization': 'Bearer $token'},
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

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

  Future<void> _addCameraAt(LatLng point) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) {
        final nameController = TextEditingController();
        final rtspController = TextEditingController();
        return AlertDialog(
          title: const Text('Add Camera'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Camera name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rtspController,
                decoration: const InputDecoration(
                  hintText: 'RTSP URL (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                (nameController.text.trim(), rtspController.text.trim()),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (result == null || result.$1.isEmpty || !mounted) return;
    final (name, rtspUrl) = result;

    final token = await _getToken();
    if (token == null) return;
    try {
      await _dio(token).post(
        '/admin/cameras',
        data: {
          'name': name,
          'latitude': point.latitude,
          'longitude': point.longitude,
          if (rtspUrl.isNotEmpty) 'rtsp_url': rtspUrl,
        },
      );
      AdminCameraSync.instance.notifyChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['detail']?.toString() ?? 'Could not add camera.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mfuCenter,
                initialZoom: 17,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, point) {
                  if (_placingCamera) {
                    setState(() => _placingCamera = false);
                    _addCameraAt(point);
                  }
                },
                onLongPress: (_, point) => _addCameraAt(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.mfu.vehicletracker',
                ),
                MarkerLayer(
                  markers: _cameras
                      .map(
                        (camera) => Marker(
                          point: camera.point,
                          width: 44,
                          height: 44,
                          child: GestureDetector(
                            onTap: () => _openCamera(camera),
                            child: const _CameraPin(),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _HintBanner(
              loading: _loading,
              error: _error,
              placing: _placingCamera,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _placingCamera = !_placingCamera),
        backgroundColor: _placingCamera ? AppColors.error : null,
        icon: Icon(_placingCamera ? Icons.close : Icons.add_location_alt),
        label: Text(_placingCamera ? 'Cancel' : 'Add camera'),
      ),
    );
  }
}

class AdminCameraData {
  final String id;
  final String name;
  final String locationName;
  final LatLng point;
  final String rtspUrl;
  final List<Map<String, dynamic>> detectionZones;

  const AdminCameraData({
    required this.id,
    required this.name,
    required this.locationName,
    required this.point,
    required this.rtspUrl,
    required this.detectionZones,
  });

  factory AdminCameraData.fromJson(Map<String, dynamic> json) {
    return AdminCameraData(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Camera',
      locationName: json['location_name']?.toString() ?? '',
      point: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      rtspUrl: json['rtsp_url']?.toString() ?? '',
      detectionZones: (json['detection_zones'] as List? ?? [])
          .map((z) => Map<String, dynamic>.from(z as Map))
          .toList(),
    );
  }
}

class _CameraPin extends StatelessWidget {
  const _CameraPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
        ],
      ),
      child: const Icon(Icons.videocam, size: 16, color: Colors.white),
    );
  }
}

class _HintBanner extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool placing;
  const _HintBanner({
    required this.loading,
    required this.error,
    required this.placing,
  });

  @override
  Widget build(BuildContext context) {
    final text = error ??
        (loading
            ? 'Loading cameras…'
            : placing
                ? 'Tap the map to place the camera'
                : 'Tap "Add camera" then tap the map to mark a spot');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error != null ? Icons.error_outline : Icons.info_outline,
              size: 16,
              color: error != null ? AppColors.error : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: error != null ? AppColors.error : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  static const _baseUrl = 'https://primp-squeeze-dedicator.ngrok-free.dev';

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
          .map(
            (item) => AdminCameraData.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
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
        _error =
            e.response?.data?['detail']?.toString() ??
            'Could not load cameras.';
      });
    }
  }

  Future<void> _addCameraAt(LatLng point) async {
    final token = await _getToken();
    if (token == null) return;

    // ดึงรายชื่อกล้องจาก CSV ตรง ๆ (ไม่พึ่งสถานะ sync ใน Mongo → เห็นครบเสมอ)
    List<Map<String, dynamic>> csvCams;
    try {
      final res = await _dio(token).get('/admin/csv-cameras');
      csvCams =
          (res.data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((e) => e['pinned'] != true) // ตัดตัวที่ปักไปแล้วออก
              .toList()
            ..sort(
              (a, b) => (a['name'] as String).toLowerCase().compareTo(
                (b['name'] as String).toLowerCase(),
              ),
            );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['detail']?.toString() ??
                'โหลดรายชื่อกล้องจาก CSV ไม่ได้',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!mounted) return;
    if (csvCams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กล้องทุกตัวจาก CSV ถูกปักหมุดแล้ว')),
      );
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        Map<String, dynamic>? choice;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final rtsp = (choice?['rtsp_url'] as String?) ?? '';
            return AlertDialog(
              title: const Text('ปักหมุดกล้อง'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'จุดที่เลือก: ${point.latitude.toStringAsFixed(5)}, '
                    '${point.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButton<Map<String, dynamic>>(
                    isExpanded: true,
                    value: choice,
                    hint: const Text('เลือกกล้อง (จาก CSV)'),
                    items: csvCams.map((c) {
                      final pos = (c['position'] as String?) ?? '';
                      return DropdownMenuItem(
                        value: c,
                        child: Text(
                          pos.isNotEmpty ? '${c['name']} · $pos' : '${c['name']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setDialogState(() => choice = v),
                  ),
                  if (choice != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      rtsp.isNotEmpty ? 'RTSP: $rtsp' : 'RTSP: (ไม่มีใน CSV)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: choice == null
                      ? null
                      : () => Navigator.pop(context, choice),
                  child: const Text('ปักหมุด'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null || !mounted) return;

    try {
      // upsert ด้วยชื่อกล้อง (backend กันซ้ำให้) → located=True
      await _dio(token).post(
        '/admin/cameras',
        data: {
          'name': selected['name'],
          'latitude': point.latitude,
          'longitude': point.longitude,
          'rtsp_url': selected['rtsp_url'] ?? '',
          'location_name': selected['position'] ?? '',
        },
      );
      AdminCameraSync.instance.notifyChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['detail']?.toString() ?? 'ปักหมุดไม่สำเร็จ',
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
                  // แสดงเฉพาะกล้องที่ปักหมุดจริงแล้ว — กล้องจาก CSV ที่ยังไม่ปัก
                  // (located=false, พิกัด placeholder) ไปตั้งพิกัดได้ในแท็บ Camera
                  markers: _cameras
                      .where((camera) => camera.located)
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
  // false = กล้องมาจาก CSV แต่ยังไม่ได้ปักหมุดจริง (พิกัดเป็น placeholder)
  final bool located;

  const AdminCameraData({
    required this.id,
    required this.name,
    required this.locationName,
    required this.point,
    required this.rtspUrl,
    required this.detectionZones,
    required this.located,
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
      located: json['located'] as bool? ?? true,
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
    final text =
        error ??
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
              color: error != null
                  ? AppColors.error
                  : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: error != null
                      ? AppColors.error
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

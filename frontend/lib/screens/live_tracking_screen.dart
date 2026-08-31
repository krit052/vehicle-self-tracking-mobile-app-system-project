import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_client.dart';
import '../services/owner_tracking_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../utils/plate_format.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String vehicleId;
  final String vehicleName;
  final String licensePlate;
  final String province;

  const LiveTrackingScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleName,
    required this.licensePlate,
    this.province = '',
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  static const _mfuCenter = LatLng(20.0459, 99.8934);
  static const _ownerUploadInterval = Duration(seconds: 5);

  final _mapController = MapController();
  final _sheetController = DraggableScrollableController();
  final _storage = const FlutterSecureStorage();
  final _ownerTrackingService = OwnerTrackingService();

  // ตำแหน่งรถ = จุดที่กล้อง CCTV ตรวจจับป้ายได้ล่าสุด (ไม่ใช้ GPS มือถือแล้ว)
  LatLng? _currentPosition;
  List<_CameraMarkerData> _cameraMarkers = [];
  _CameraMarkerData? _selectedCamera;
  DateTime? _lastUpdate; // เวลาที่กล้องเห็นล่าสุด
  String? _detectedCamera; // ชื่อกล้องที่เห็นล่าสุด
  bool _locationLoading = true;
  String? _locationError;
  bool _followUser = true;
  Timer? _pollTimer;
  StreamSubscription<Position>? _ownerLocationSub;
  OwnerTrackingSnapshot _ownerTracking = OwnerTrackingSnapshot.fromJson(null);
  LatLng? _liveOwnerPosition;
  double? _liveOwnerAccuracy;
  bool _ownerTrackingStarting = false;
  DateTime? _lastOwnerUploadAt;
  String? _ownerTrackingError;

  bool _locked = false;
  bool _locking = false;

  late String _vehicleName = widget.vehicleName;
  late String _licensePlate = widget.licensePlate;
  late String _province = widget.province;
  bool _vehicleInfoLoading = false;

  // ซ่อนตำแหน่งกล้องบนแผนที่สำหรับ user ทั่วไป — admin เท่านั้นที่เห็นหมุดกล้อง
  bool get _isAdmin => UserSession.instance.role == 'admin';

  @override
  void initState() {
    super.initState();
    _loadVehicleInfo();
    if (_isAdmin) _loadCameraMarkers();
    // เริ่ม track ตำแหน่งเจ้าของอัตโนมัติทันทีที่เปิดหน้า ไม่ต้องกดปุ่มเอง — backend จะ
    // ตั้งจุดจอดจาก ping แรกเองและขยับตามตอนอยู่ใกล้รถ (ดู update_owner_location)
    _startOwnerTracking();
    // ดึงตำแหน่งรถ (last_detection) ซ้ำทุก 10 วิ ให้หมุดขยับตามที่กล้องเห็นล่าสุด
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadVehicleInfo(),
    );
  }

  Future<String?> _getToken() async {
    if (UserSession.instance.token != null) return UserSession.instance.token;
    try {
      return await _storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  bool get _ownerTrackingActive => _ownerLocationSub != null;
  LatLng? get _ownerMapPosition =>
      _liveOwnerPosition ?? _ownerTracking.ownerPosition;
  double? get _ownerMapAccuracy =>
      _liveOwnerAccuracy ?? _ownerTracking.accuracy;

  void _setLiveOwnerPosition(Position position, {bool moveCamera = false}) {
    final point = LatLng(position.latitude, position.longitude);
    if (!mounted) return;
    setState(() {
      _liveOwnerPosition = point;
      _liveOwnerAccuracy = position.accuracy;
    });
    if (moveCamera) {
      _mapController.move(point, 18);
    }
  }

  Future<void> _startOwnerTracking({Position? initialPosition}) async {
    if (_ownerTrackingActive || _ownerTrackingStarting) return;
    setState(() {
      _ownerTrackingStarting = true;
      _ownerTrackingError = null;
    });

    try {
      final position =
          initialPosition ?? await _ownerTrackingService.currentPosition();
      _setLiveOwnerPosition(position, moveCamera: initialPosition == null);
      await _uploadOwnerLocation(position, force: true);

      final subscription = _ownerTrackingService.positionStream().listen(
        _handleOwnerPosition,
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _ownerTrackingError = _ownerTrackingErrorMessage(error);
          });
        },
      );
      if (!mounted) {
        await subscription.cancel();
        return;
      }
      setState(() => _ownerLocationSub = subscription);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ownerTrackingError = _ownerTrackingErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _ownerTrackingStarting = false);
      }
    }
  }

  Future<void> _handleOwnerPosition(Position position) async {
    _setLiveOwnerPosition(position);
    final now = DateTime.now();
    final lastUpload = _lastOwnerUploadAt;
    if (lastUpload != null &&
        now.difference(lastUpload) < _ownerUploadInterval) {
      return;
    }
    _lastOwnerUploadAt = now;
    await _uploadOwnerLocation(position, force: true);
  }

  Future<bool> _uploadOwnerLocation(
    Position position, {
    bool force = false,
  }) async {
    final token = await _getToken();
    if (token == null) {
      if (mounted) {
        setState(() => _ownerTrackingError = 'Not logged in.');
      }
      return false;
    }

    if (!force) {
      final lastUpload = _lastOwnerUploadAt;
      if (lastUpload != null &&
          DateTime.now().difference(lastUpload) < _ownerUploadInterval) {
        return true;
      }
    }
    _lastOwnerUploadAt = DateTime.now();

    try {
      final res = await ApiClient.instance.dio.put(
        '/vehicles/${widget.vehicleId}/owner-location',
        data: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final vehicle = Map<String, dynamic>.from(res.data as Map);
      final owner = vehicle['owner_tracking'];
      if (!mounted) return true;
      setState(() {
        _ownerTracking = OwnerTrackingSnapshot.fromJson(
          owner is Map ? Map<String, dynamic>.from(owner) : null,
        );
        _ownerTrackingError = null;
        // ✅ sync locked ทันที เผื่อ backend auto lock/unlock ตามระยะห่างในรอบนี้
        _locked = (vehicle['locked'] as bool?) ?? _locked;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _ownerTrackingError = _ownerTrackingErrorMessage(e));
      return false;
    }
  }

  String _ownerTrackingErrorMessage(Object error) {
    if (error is OwnerLocationException) return error.message;
    if (error is DioException) {
      return error.response?.data?['detail']?.toString() ??
          'Could not update owner GPS.';
    }
    return 'Could not read owner GPS.';
  }

  Future<void> _loadCameraMarkers() async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final res = await ApiClient.instance.dio.get(
        '/cameras',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final cameras = (res.data as List)
          .map(
            (item) => _CameraMarkerData.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _cameraMarkers = cameras;
        _selectedCamera = cameras.isNotEmpty ? cameras.first : null;
      });

      if (_currentPosition == null && cameras.isNotEmpty) {
        _mapController.move(cameras.first.point, 18);
      }
    } on DioException catch (e) {
      debugPrint(
        '[LiveTracking] camera markers failed: ${e.message} '
        '(status ${e.response?.statusCode}, body ${e.response?.data})',
      );
    }
  }

  Future<void> _loadVehicleInfo() async {
    // final token = UserSession.instance.token;
    final token = await _getToken(); // เดิมใช้ UserSession.instance.token ตรงๆ
    if (token == null) {
      if (mounted) setState(() => _locationLoading = false);
      return;
    }
    setState(() => _vehicleInfoLoading = true);
    try {
      final res = await ApiClient.instance.dio.get(
        '/vehicles',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final vehicles = (res.data as List).cast<Map<String, dynamic>>();
      final vehicle = vehicles.firstWhere(
        (v) => v['id'] == widget.vehicleId,
        orElse: () => <String, dynamic>{},
      );
      if (!mounted) return;
      LatLng? detectedPoint;
      setState(() {
        if (vehicle['model'] != null) _vehicleName = vehicle['model'];
        if (vehicle['license_plate'] != null) {
          _licensePlate = vehicle['license_plate'];
        }
        if (vehicle['province'] != null) _province = vehicle['province'];
        // ✅ sync locked from backend/mongo
        _locked = (vehicle['locked'] as bool?) ?? false;
        final owner = vehicle['owner_tracking'];
        _ownerTracking = OwnerTrackingSnapshot.fromJson(
          owner is Map ? Map<String, dynamic>.from(owner) : null,
        );
        // ตำแหน่งรถ = จุดที่กล้อง CCTV ตรวจจับป้ายได้ล่าสุด
        final ld = vehicle['last_detection'];
        final lat = (ld is Map) ? (ld['latitude'] as num?)?.toDouble() : null;
        final lon = (ld is Map) ? (ld['longitude'] as num?)?.toDouble() : null;
        if (ld is Map && lat != null && lon != null) {
          detectedPoint = LatLng(lat, lon);
          _currentPosition = detectedPoint;
          _detectedCamera = ld['camera_name'] as String?;
          final at = ld['at'] as String?;
          _lastUpdate = at != null ? DateTime.tryParse(at) : DateTime.now();
        } else {
          // รถไม่ได้ถูกตรวจจับอยู่ (last_detection = null หรือหมดอายุจาก backend)
          // → เอาหมุดรถออกจากแผนที่ (เช่น เมื่อรถถูกเอาออกไปแล้ว)
          _currentPosition = null;
          _detectedCamera = null;
          _lastUpdate = null;
        }
        _locationLoading = false;
        _locationError = null;
        _vehicleInfoLoading = false;
      });
      // ตามรถอัตโนมัติเมื่อได้ตำแหน่งใหม่ (จนกว่า user จะเลื่อนแผนที่เอง)
      if (detectedPoint != null && _followUser) {
        _mapController.move(detectedPoint!, 18);
      }
    } on DioException {
      if (!mounted) return;
      setState(() {
        _locationLoading = false;
        _vehicleInfoLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ownerLocationSub?.cancel();
    _mapController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _centerOnUser() async {
    final ownerPoint = _ownerMapPosition;
    if (ownerPoint != null) {
      _mapController.move(ownerPoint, 18);
      setState(() => _followUser = true);
      return;
    }

    try {
      final position = await _ownerTrackingService.currentPosition();
      _setLiveOwnerPosition(position, moveCamera: true);
      setState(() {
        _followUser = true;
        _ownerTrackingError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final fallback = _currentPosition ?? _mfuCenter;
      _mapController.move(fallback, 18);
      setState(() {
        _followUser = true;
        _ownerTrackingError = _ownerTrackingErrorMessage(e);
      });
    }
  }

  Future<void> _toggleLock() async {
    final shouldLock = !_locked;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(shouldLock ? 'Lock Vehicle' : 'Unlock Vehicle'),
        content: Text(
          shouldLock
              ? 'Are you sure you want to lock this vehicle?'
              : 'Are you sure you want to unlock this vehicle?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: shouldLock ? AppColors.primary : AppColors.green,
            ),
            child: Text(shouldLock ? 'Lock' : 'Unlock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = await _getToken();
    if (token == null || !mounted) return;

    setState(() => _locking = true);
    try {
      final res = await ApiClient.instance.dio.put(
        "/vehicle/lock",
        data: {"vehicle_id": widget.vehicleId, "locked": shouldLock},
        options: Options(headers: {"Authorization": "Bearer $token"}),
      );

      if (!mounted) return;
      setState(() {
        _locked = res.data["locked"];
      });
    } on DioException catch (e) {
      debugPrint(e.response?.data.toString());
    } finally {
      if (mounted) {
        setState(() => _locking = false);
      }
    }
  }

  String get _lastUpdateLabel {
    if (_lastUpdate == null) return '—';
    final diff = DateTime.now().difference(_lastUpdate!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildSheet(),
          if (_locationLoading) _buildLoadingOverlay(),
          if (_locationError != null) _buildErrorBanner(),
          if (_selectedCamera != null) _buildCameraBanner(),
        ],
      ),
      floatingActionButton: Padding(
        // 130 ตั้งไว้ให้ลอยเหนือ handle ของ DraggableScrollableSheet พอดีตอนแนวตั้ง — แต่ค่า
        // fixed เดิมทำให้ปุ่ม lock+GPS ล้นจอ (RenderFlex overflow) ตอนหมุนเป็นแนวนอน เพราะจอ
        // สูงน้อยกว่ามากแต่ padding ยังกินพื้นที่เท่าเดิม ลดตอนแนวนอนให้เหลือพอดีตัว
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.of(context).orientation == Orientation.landscape
              ? 16
              : 130,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: "lock",

              backgroundColor: _locked ? AppColors.green : AppColors.primary,

              foregroundColor: Colors.white,

              onPressed: _locking ? null : _toggleLock,

              child: _locking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_locked ? Icons.lock : Icons.lock_open),
            ),

            const SizedBox(height: 12),

            FloatingActionButton.small(
              heroTag: "gps",

              onPressed: () => _centerOnUser(),

              backgroundColor: _followUser
                  ? AppColors.primary
                  : AppColors.surface,

              foregroundColor: _followUser ? Colors.white : AppColors.onSurface,

              child: const Icon(Icons.my_location),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final marker = _currentPosition;
    final ownerPoint = _ownerMapPosition;
    final initialCenter =
        ownerPoint ??
        marker ??
        _selectedCamera?.point ??
        (_cameraMarkers.isNotEmpty ? _cameraMarkers.first.point : _mfuCenter);
    return SizedBox.expand(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: 18,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onPositionChanged: (_, hasGesture) {
            if (hasGesture && _followUser) {
              setState(() => _followUser = false);
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.mfu.vehicletracker',
          ),
          if (_isAdmin && _cameraMarkers.isNotEmpty)
            MarkerLayer(
              markers: _cameraMarkers.map((camera) {
                final selected = camera.id == _selectedCamera?.id;
                return Marker(
                  point: camera.point,
                  width: 52,
                  height: 52,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCamera = camera;
                        _followUser = false;
                      });
                      _mapController.move(camera.point, 18);
                    },
                    child: _CameraMapPin(selected: selected),
                  ),
                );
              }).toList(),
            ),
          if (marker != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: marker,
                  width: 44,
                  // สูงเป็น 2 เท่าของ pin แล้ววางไอคอนไว้ครึ่งบน → ปลาย pin ชี้ตรงจุด
                  // (ตำแหน่งกล้อง) พอดี ส่วนตัว pin ลอยเหนือหมุดกล้อง ไม่ทับกัน
                  height: 96,
                  child: const _VehiclePin(),
                ),
              ],
            ),
          if (ownerPoint != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: ownerPoint,
                  width: 44,
                  height: 44,
                  child: _OwnerPin(status: _ownerTracking.status),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCameraBanner() {
    final camera = _selectedCamera!;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 64,
      left: 16,
      right: 16,
      child: _MapChip(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.videocam, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      camera.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      camera.locationName.isNotEmpty
                          ? camera.locationName
                          : '${camera.point.latitude.toStringAsFixed(6)}, ${camera.point.longitude.toStringAsFixed(6)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _selectedCamera = null),
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.22,
      minChildSize: 0.08,
      maxChildSize: 0.52,
      snap: true,
      snapSizes: const [0.08, 0.22, 0.52],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [_buildHandle(), _buildCardContent()],
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    final pos = _currentPosition;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.motorcycle,
                  color: AppColors.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vehicleName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      formatPlateWithProvince(_licensePlate, _province),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _vehicleInfoLoading ? null : _loadVehicleInfo,
                icon: _vehicleInfoLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh vehicle info',
                visualDensity: VisualDensity.compact,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              _StatusBadge(status: pos != null ? 'active' : 'searching'),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.outlineVariant, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              _InfoTile(
                icon: Icons.access_time,
                label: 'Seen',
                value: _lastUpdateLabel,
              ),
              _InfoTile(
                icon: Icons.videocam,
                label: 'Camera',
                value: (_detectedCamera != null && _detectedCamera!.isNotEmpty)
                    ? _detectedCamera!
                    : '—',
              ),
              _InfoTile(
                icon: Icons.check_circle_outline,
                label: 'Status',
                value: pos != null ? 'Detected' : '—',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.outlineVariant, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              _InfoTile(
                icon: Icons.location_on_outlined,
                label: 'Latitude',
                value: pos != null ? pos.latitude.toStringAsFixed(6) : '—',
              ),
              _InfoTile(
                icon: Icons.location_on_outlined,
                label: 'Longitude',
                value: pos != null ? pos.longitude.toStringAsFixed(6) : '—',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.outlineVariant, height: 1),
          const SizedBox(height: 14),
          _buildOwnerTrackingSection(),
        ],
      ),
    );
  }

  Widget _buildOwnerTrackingSection() {
    final tracking = _ownerTracking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.person_pin_circle_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Owner distance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            _OwnerStatusBadge(status: tracking.status),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _InfoTile(
              icon: Icons.social_distance,
              label: 'Distance',
              value: _distanceLabel(tracking.distanceFromParkingM),
            ),
            _InfoTile(
              icon: tracking.accuracyAccepted
                  ? Icons.gps_fixed
                  : Icons.gps_not_fixed,
              label: 'Accuracy',
              value: _accuracyLabel(_ownerMapAccuracy),
            ),
            _InfoTile(
              icon: _ownerTrackingActive
                  ? Icons.sensors
                  : Icons.sensors_off_outlined,
              label: 'GPS',
              value: _ownerTrackingActive ? 'Tracking' : 'Paused',
            ),
          ],
        ),
        if (_ownerTrackingError != null) ...[
          const SizedBox(height: 10),
          Text(
            _ownerTrackingError!,
            style: const TextStyle(fontSize: 12, color: AppColors.error),
          ),
        ],
      ],
    );
  }

  String _distanceLabel(double? meters) {
    if (meters == null) return '-';
    final decimals = meters < 10 ? 1 : 0;
    return '${meters.toStringAsFixed(decimals)} m';
  }

  String _accuracyLabel(double? meters) {
    if (meters == null) return '-';
    return '+/- ${meters.toStringAsFixed(1)} m';
  }

  Widget _buildLoadingOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: _MapChip(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Getting your location…',
                style: TextStyle(fontSize: 13, color: AppColors.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: _MapChip(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.location_off, size: 16, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _locationError!,
                  style: const TextStyle(fontSize: 13, color: AppColors.error),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _locationError = null;
                    _locationLoading = true;
                  });
                  _loadVehicleInfo();
                },
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraMarkerData {
  final String id;
  final String name;
  final String locationName;
  final LatLng point;

  const _CameraMarkerData({
    required this.id,
    required this.name,
    required this.locationName,
    required this.point,
  });

  factory _CameraMarkerData.fromJson(Map<String, dynamic> json) {
    return _CameraMarkerData(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Camera',
      locationName: json['location_name']?.toString() ?? '',
      point: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
    );
  }
}

class _CameraMapPin extends StatelessWidget {
  final bool selected;

  const _CameraMapPin({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 46 : 34,
          height: selected ? 46 : 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: selected ? 0.22 : 0.10),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(
            Icons.videocam,
            size: 16,
            color: selected ? AppColors.onPrimary : AppColors.primary,
          ),
        ),
      ],
    );
  }
}

// ── Vehicle Pin (ตำแหน่งรถที่กล้องตรวจจับ) ─────────────────────────────────────
// pin เขียวลอยเหนือจุด ปลายชี้ที่ตำแหน่งกล้อง แยกออกจากหมุดกล้อง (สี primary) ชัดเจน

class _VehiclePin extends StatelessWidget {
  const _VehiclePin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        SizedBox(
          width: 44,
          height: 46,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              const Icon(Icons.location_on, size: 44, color: AppColors.green),
              const Positioned(
                top: 7,
                child: Icon(Icons.motorcycle, size: 15, color: Colors.white),
              ),
            ],
          ),
        ),
        // ครึ่งล่างเว้นว่าง เพื่อให้ปลาย pin (ด้านบน) ตกที่จุดกึ่งกลาง = ตำแหน่งกล้อง
        const Spacer(),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _OwnerPin extends StatelessWidget {
  final String status;

  const _OwnerPin({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'NEAR' => AppColors.blue,
      'AWAY' => AppColors.error,
      _ => AppColors.blue,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 6,
            ),
          ],
        ),
        child: const Icon(Icons.person, size: 15, color: Colors.white),
      ),
    );
  }
}

class _OwnerStatusBadge extends StatelessWidget {
  final String status;

  const _OwnerStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'NEAR' => ('Near', const Color(0xFFE3F2FD), AppColors.blue),
      'AWAY' => ('Away', const Color(0xFFFFEBEE), AppColors.error),
      _ => ('Unknown', const Color(0xFFF5F5F5), AppColors.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'active' => ('Live', const Color(0xFFE6F4EA), const Color(0xFF1E8A3E)),
      'searching' => (
        'Searching…',
        const Color(0xFFFFF3E0),
        const Color(0xFFE65100),
      ),
      _ => ('Unknown', const Color(0xFFF5F5F5), AppColors.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  final Widget child;
  const _MapChip({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String vehicleId;
  final String vehicleName;
  final String licensePlate;

  const LiveTrackingScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleName,
    required this.licensePlate,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  static const _mfuCenter = LatLng(20.0459, 99.8934);
  static const _baseUrl = 'http://localhost:8001';

  final _mapController = MapController();
  final _sheetController = DraggableScrollableController();
  final _storage = const FlutterSecureStorage();

  LatLng? _currentPosition;
  List<_CameraMarkerData> _cameraMarkers = [];
  _CameraMarkerData? _selectedCamera;
  double? _currentSpeed;
  double? _currentAccuracy;
  DateTime? _lastUpdate;
  bool _locationLoading = true;
  String? _locationError;
  bool _followUser = true;
  StreamSubscription<Position>? _positionSub;

  bool _locked = false;
  bool _locking = false;

  late String _vehicleName = widget.vehicleName;
  late String _licensePlate = widget.licensePlate;
  bool _vehicleInfoLoading = false;

  // ตำแหน่งล่าสุดที่กล้อง CCTV จับป้ายรถคันนี้ได้ (มาจาก backend /vehicles)
  LatLng? _lastDetectionPoint;
  String? _lastDetectionCamera;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadVehicleInfo();
    _loadCameraMarkers();
  }

  Future<String?> _getToken() async {
    if (UserSession.instance.token != null) return UserSession.instance.token;
    try {
      return await _storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCameraMarkers() async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).get('/cameras');

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
    if (token == null) return;
    setState(() => _vehicleInfoLoading = true);
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).get('/vehicles');
      final vehicles = (res.data as List).cast<Map<String, dynamic>>();
      final vehicle = vehicles.firstWhere(
        (v) => v['id'] == widget.vehicleId,
        orElse: () => <String, dynamic>{},
      );
      if (!mounted) return;
      setState(() {
        if (vehicle['model'] != null) _vehicleName = vehicle['model'];
        if (vehicle['license_plate'] != null) {
          _licensePlate = vehicle['license_plate'];
        }
        // ✅ sync locked from backend/mongo
        _locked = (vehicle['locked'] as bool?) ?? false;
        // ตำแหน่งล่าสุดที่กล้องจับป้ายได้ (ถ้ามี)
        final ld = vehicle['last_detection'];
        if (ld is Map) {
          final lat = (ld['latitude'] as num?)?.toDouble();
          final lon = (ld['longitude'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            _lastDetectionPoint = LatLng(lat, lon);
            _lastDetectionCamera = ld['camera_name'] as String?;
          }
        }
        _vehicleInfoLoading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _vehicleInfoLoading = false);
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationError = 'Location services are disabled.';
        _locationLoading = false;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _locationError = 'Location permission denied.';
        _locationLoading = false;
      });
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _applyPosition(pos);
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError = 'Could not get location.';
          _locationLoading = false;
        });
      }
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen(_applyPosition, onError: (_) {});
  }

  void _applyPosition(Position pos) {
    final point = LatLng(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _currentPosition = point;
      _currentSpeed = pos.speed;
      _currentAccuracy = pos.accuracy;
      _lastUpdate = DateTime.now();
      _locationLoading = false;
      _locationError = null;
    });
    if (_followUser) {
      _mapController.move(point, 18);
    }
    _sendLocationUpdate(pos);
  }

  Future<void> _sendLocationUpdate(Position pos) async {
    final token = UserSession.instance.token;
    if (token == null) {
      debugPrint('[LiveTracking] skip location update: no token');
      return;
    }
    try {
      await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).post(
        '/vehicles/${widget.vehicleId}/location',
        data: {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'speed': pos.speed,
          'accuracy': pos.accuracy,
        },
      );
      debugPrint('[LiveTracking] location update sent for ${widget.vehicleId}');
    } on DioException catch (e) {
      debugPrint(
        '[LiveTracking] location update failed: ${e.message} '
        '(status ${e.response?.statusCode}, body ${e.response?.data})',
      );
    }
  }

  void _centerOnUser() {
    final target = _currentPosition ?? _mfuCenter;
    _mapController.move(target, 18);
    setState(() => _followUser = true);
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
      final res =
          await Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              headers: {"Authorization": "Bearer $token"},
            ),
          ).put(
            "/vehicle/lock",
            data: {"vehicle_id": widget.vehicleId, "locked": shouldLock},
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

  String get _speedLabel {
    if (_currentSpeed == null) return '—';
    final kmh = _currentSpeed! * 3.6;
    return '${kmh.toStringAsFixed(1)} km/h';
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
        padding: const EdgeInsets.only(bottom: 130),
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

              onPressed: _centerOnUser,

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
    final initialCenter =
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
          if (_cameraMarkers.isNotEmpty)
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
          if (_lastDetectionPoint != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _lastDetectionPoint!,
                  width: 140,
                  height: 56,
                  child: _LastSeenMarker(cameraName: _lastDetectionCamera),
                ),
              ],
            ),
          if (marker != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: marker,
                  width: 56,
                  height: 56,
                  child: const _PulsingMarker(),
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
                      _licensePlate,
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
                label: 'Updated',
                value: _lastUpdateLabel,
              ),
              _InfoTile(icon: Icons.speed, label: 'Speed', value: _speedLabel),
              _InfoTile(
                icon: Icons.radar,
                label: 'Accuracy',
                value: _currentAccuracy != null
                    ? '±${_currentAccuracy!.toStringAsFixed(0)}m'
                    : '—',
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
        ],
      ),
    );
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
                  _initLocation();
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

class _LastSeenMarker extends StatelessWidget {
  final String? cameraName;
  const _LastSeenMarker({this.cameraName});

  @override
  Widget build(BuildContext context) {
    final label = (cameraName != null && cameraName!.isNotEmpty)
        ? 'Last seen · $cameraName'
        : 'Last seen by CCTV';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Icon(Icons.directions_car, color: AppColors.blue, size: 28),
      ],
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

// ── Pulsing GPS Marker ────────────────────────────────────────────────────────

class _PulsingMarker extends StatefulWidget {
  const _PulsingMarker();

  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulse = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 56 * _pulse.value,
            height: 56 * _pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(
                alpha: (1 - _pulse.value) * 0.35,
              ),
            ),
          ),
        ),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
              ),
            ],
          ),
          child: const Icon(
            Icons.person_pin_circle,
            color: AppColors.primary,
            size: 16,
          ),
        ),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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

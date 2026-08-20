import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../theme/app_theme.dart';
import 'admin_camera_map_screen.dart';
import 'login_screen.dart';

class AdminCameraDetailScreen extends StatefulWidget {
  final AdminCameraData camera;

  const AdminCameraDetailScreen({super.key, required this.camera});

  @override
  State<AdminCameraDetailScreen> createState() => _AdminCameraDetailScreenState();
}

class _AdminCameraDetailScreenState extends State<AdminCameraDetailScreen> {
  static const _baseUrl = 'https://primp-squeeze-dedicator.ngrok-free.dev';

  final _storage = const FlutterSecureStorage();

  late final _nameController = TextEditingController(text: widget.camera.name);
  late final _locationController = TextEditingController(text: widget.camera.locationName);
  late final _latController = TextEditingController(text: widget.camera.point.latitude.toString());
  late final _lngController = TextEditingController(text: widget.camera.point.longitude.toString());
  late final _rtspController = TextEditingController(text: widget.camera.rtspUrl);

  Player? _player;
  VideoController? _videoController;

  late List<List<Offset>> _zones;
  List<Offset> _drawingPoints = [];
  bool _drawing = false;

  bool _saving = false;
  bool _savingZones = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _zones = widget.camera.detectionZones
        .map<List<Offset>>(
          (zone) => (zone['points'] as List)
              .map(
                (p) => Offset(
                  (p['x'] as num).toDouble(),
                  (p['y'] as num).toDouble(),
                ),
              )
              .toList(),
        )
        .toList();
    _initPlayer();
  }

  void _initPlayer() {
    if (widget.camera.rtspUrl.isEmpty) return;
    final player = Player();
    _videoController = VideoController(player);
    player.open(Media(widget.camera.rtspUrl));
    _player = player;
  }

  @override
  void dispose() {
    _player?.dispose();
    _nameController.dispose();
    _locationController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _rtspController.dispose();
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

  Future<void> _save() async {
    final token = await _getToken();
    if (token == null) return;

    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Latitude/longitude must be numbers.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _dio(token).patch(
        '/admin/cameras/${widget.camera.id}',
        data: {
          'name': _nameController.text.trim(),
          'location_name': _locationController.text.trim(),
          'latitude': lat,
          'longitude': lng,
          'rtsp_url': _rtspController.text.trim(),
        },
      );
      AdminCameraSync.instance.notifyChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera saved.')),
      );
      if (_rtspController.text.trim() != widget.camera.rtspUrl) {
        await _player?.dispose();
        _player = null;
        _videoController = null;
        setState(() {});
        _initPlayer();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data?['detail']?.toString() ?? 'Could not save camera.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveZones() async {
    final token = await _getToken();
    if (token == null) return;

    setState(() => _savingZones = true);
    try {
      await _dio(token).patch(
        '/admin/cameras/${widget.camera.id}/detection-zones',
        data: {
          'detection_zones': [
            for (var i = 0; i < _zones.length; i++)
              {
                'id': 'zone-$i',
                'points': _zones[i].map((p) => {'x': p.dx, 'y': p.dy}).toList(),
              },
          ],
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detection zones saved.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data?['detail']?.toString() ?? 'Could not save zones.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingZones = false);
    }
  }

  Future<void> _deleteCamera() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Camera'),
        content: Text('Delete "${widget.camera.name}"? This cannot be undone.'),
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

    setState(() => _deleting = true);
    try {
      await _dio(token).delete('/admin/cameras/${widget.camera.id}');
      AdminCameraSync.instance.notifyChanged();
      if (!mounted) return;
      Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data?['detail']?.toString() ?? 'Could not delete camera.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _onZoneTap(TapUpDetails details, BoxConstraints constraints) {
    if (!_drawing) return;
    final dx = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final dy = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    setState(() => _drawingPoints.add(Offset(dx, dy)));
  }

  void _startDrawing() {
    setState(() {
      _drawing = true;
      _drawingPoints = [];
    });
  }

  void _finishDrawing() {
    if (_drawingPoints.length >= 3) {
      setState(() {
        _zones.add(List.of(_drawingPoints));
      });
    }
    setState(() {
      _drawing = false;
      _drawingPoints = [];
    });
  }

  void _cancelDrawing() {
    setState(() {
      _drawing = false;
      _drawingPoints = [];
    });
  }

  void _deleteZone(int index) {
    setState(() => _zones.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Camera', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              widget.camera.name,
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        actions: [
          IconButton(
            onPressed: _deleting ? null : _deleteCamera,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, color: AppColors.error),
            tooltip: 'Delete camera',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildVideoWithOverlay(),
          const SizedBox(height: 12),
          _buildDrawControls(),
          const SizedBox(height: 8),
          _buildZoneList(),
          const SizedBox(height: 20),
          _buildEditForm(),
        ],
      ),
    );
  }

  Widget _buildVideoWithOverlay() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black),
                if (_videoController != null)
                  Video(
                    controller: _videoController!,
                    fit: BoxFit.contain,
                    controls: NoVideoControls,
                  )
                else
                  const Center(
                    child: Text(
                      'No stream configured.\nSet an RTSP URL below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => _onZoneTap(details, constraints),
                  child: CustomPaint(
                    painter: _ZonesPainter(
                      zones: _zones,
                      drawingPoints: _drawingPoints,
                    ),
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrawControls() {
    if (!_drawing) {
      return Row(
        children: [
          OutlinedButton.icon(
            onPressed: _startDrawing,
            style: OutlinedButton.styleFrom(minimumSize: Size.zero),
            icon: const Icon(Icons.crop_free, size: 18),
            label: const Text('Add zone'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _savingZones ? null : _saveZones,
            icon: _savingZones
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save zones'),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            'Tap to add points (${_drawingPoints.length}), then finish.',
            style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
        ),
        TextButton(onPressed: _cancelDrawing, child: const Text('Cancel')),
        FilledButton(
          onPressed: _drawingPoints.length >= 3 ? _finishDrawing : null,
          child: const Text('Finish'),
        ),
      ],
    );
  }

  Widget _buildZoneList() {
    if (_zones.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _zones.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.polyline_outlined, size: 18),
            title: Text('Zone ${i + 1} (${_zones[i].length} points)'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteZone(i),
            ),
          ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Camera details',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(labelText: 'Location'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _lngController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _rtspController,
          decoration: const InputDecoration(labelText: 'RTSP URL'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }
}

class _ZonesPainter extends CustomPainter {
  final List<List<Offset>> zones;
  final List<Offset> drawingPoints;

  _ZonesPainter({required this.zones, required this.drawingPoints});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final pointPaint = Paint()..color = Colors.white;

    for (final zone in zones) {
      final path = _polygonPath(zone, size);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    if (drawingPoints.isNotEmpty) {
      final path = _polygonPath(drawingPoints, size, closed: false);
      canvas.drawPath(path, strokePaint);
      for (final p in drawingPoints) {
        canvas.drawCircle(Offset(p.dx * size.width, p.dy * size.height), 4, pointPaint);
      }
    }
  }

  Path _polygonPath(List<Offset> points, Size size, {bool closed = true}) {
    final path = Path();
    if (points.isEmpty) return path;
    final scaled = points.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
    path.moveTo(scaled.first.dx, scaled.first.dy);
    for (final p in scaled.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (closed) path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ZonesPainter oldDelegate) => true;
}

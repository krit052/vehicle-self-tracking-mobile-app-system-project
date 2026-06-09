import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';

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
  static const _mfuCenter = LatLng(18.9143, 99.0490);
  static const _mockVehiclePoint = LatLng(18.9150, 99.0498);

  final _mapController = MapController();

  final _lastSeenLabel = '2 min ago';

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }


  void _centerOnVehicle() {
    _mapController.move(_mockVehiclePoint, 18);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildVehicleCard(),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 160),
        child: FloatingActionButton(
          onPressed: _centerOnVehicle,
          backgroundColor: AppColors.secondaryContainer,
          foregroundColor: AppColors.onSurface,
          mini: true,
          child: const Icon(Icons.my_location),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: _mockVehiclePoint,
        initialZoom: 18,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.mfu.vehicletracker',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _mockVehiclePoint,
              width: 48,
              height: 48,
              child: const _VehicleMarker(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVehicleCard() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _buildCardContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.motorcycle, color: AppColors.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.vehicleName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    widget.licensePlate,
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
              onPressed: _centerOnVehicle,
              icon: const Icon(Icons.sync, color: AppColors.primary),
              tooltip: 'Refresh location',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: AppColors.outlineVariant, height: 1),
        const SizedBox(height: 12),
        Row(
          children: [
            _InfoTile(
              icon: Icons.access_time,
              label: 'Last seen',
              value: _lastSeenLabel,
            ),
            const SizedBox(width: 16),
            _InfoTile(
              icon: Icons.location_searching,
              label: 'Latitude',
              value: _mockVehiclePoint.latitude.toStringAsFixed(5),
            ),
            const SizedBox(width: 16),
            _InfoTile(
              icon: Icons.location_searching,
              label: 'Longitude',
              value: _mockVehiclePoint.longitude.toStringAsFixed(5),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: const Icon(Icons.motorcycle, color: AppColors.primary, size: 24),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool large;
  const _StatusBadge({required this.status, this.large = false});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'parked'  => ('Parked',  const Color(0xFFE6F4EA), const Color(0xFF1E8A3E)),
      'moving'  => ('Moving',  const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      'unknown' => ('Unknown', const Color(0xFFF5F5F5), AppColors.onSurfaceVariant),
      _         => ('Unknown', const Color(0xFFF5F5F5), AppColors.onSurfaceVariant),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 4 : 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(
          fontSize: large ? 12 : 11,
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
  const _InfoTile({required this.icon, required this.label, required this.value});

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
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface),
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

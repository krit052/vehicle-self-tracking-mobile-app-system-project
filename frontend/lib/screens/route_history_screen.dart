import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

class RouteHistoryScreen extends StatefulWidget {
  final String vehicleId;

  const RouteHistoryScreen({super.key, required this.vehicleId});

  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen> {
  static const _mfuCenter = LatLng(18.9143, 99.0490);
  static const _baseUrl = 'http://localhost:8001';

  final _mapController = MapController();
  final _calendarScrollController = ScrollController();

  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;

  _RouteEntry? _selectedRoute;
  String? _userName;
  List<_RouteEntry> _routes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _initUser();
    _fetchRoutes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDay(DateTime.now().day, animate: false);
    });
  }

  Future<void> _fetchRoutes() async {
    final token = UserSession.instance.token;
    if (token == null) {
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
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).get('/vehicles/${widget.vehicleId}/history');
      final data = (res.data as List).cast<Map<String, dynamic>>();
      setState(() {
        _routes = data.map(_RouteEntry.fromJson).toList();
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _error = e.response?.data?['detail']?.toString() ??
            'Could not load route history.';
      });
    }
  }

  Future<void> _initUser() async {
    final session = UserSession.instance;
    if (session.user != null) {
      if (mounted) setState(() => _userName = session.user!['name'] as String?);
      return;
    }
    final token = session.token;
    if (token == null) return;
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).get('/auth/me');
      session.user = Map<String, dynamic>.from(res.data as Map);
      if (mounted) setState(() => _userName = session.user!['name'] as String?);
    } catch (_) {}
  }

  @override
  void dispose() {
    _mapController.dispose();
    _calendarScrollController.dispose();
    super.dispose();
  }

  List<_RouteEntry> get _filteredRoutes {
    if (_selectedDate == null) return _routes;
    return _routes.where((r) {
      final d = r.startTime;
      return d.year == _selectedDate!.year &&
          d.month == _selectedDate!.month &&
          d.day == _selectedDate!.day;
    }).toList();
  }

  void _selectRoute(_RouteEntry route) {
    setState(() => _selectedRoute = route);
    if (route.waypoints.isNotEmpty) {
      _mapController.move(route.waypoints.first, 17);
    }
  }

  void _scrollToDay(int day, {bool animate = true}) {
    if (!_calendarScrollController.hasClients) return;
    const itemWidth = 48.0;
    final viewport = _calendarScrollController.position.viewportDimension;
    final offset = ((day - 1) * itemWidth) - (viewport / 2) + (itemWidth / 2);
    final clamped = offset.clamp(
      _calendarScrollController.position.minScrollExtent,
      _calendarScrollController.position.maxScrollExtent,
    );
    if (animate) {
      _calendarScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _calendarScrollController.jumpTo(clamped);
    }
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      _selectedDate = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calendarScrollController.jumpTo(0);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      _selectedDate = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isCurrentMonth =
          _focusedMonth.year == now.year && _focusedMonth.month == now.month;
      isCurrentMonth
          ? _scrollToDay(now.day, animate: false)
          : _calendarScrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildCalendarStrip(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      centerTitle: false,
      leading: Padding(
        padding: const EdgeInsets.all(10),
        child: CircleAvatar(
          backgroundColor: AppColors.primaryContainer,
          child: Text(
            _userName != null && _userName!.isNotEmpty
                ? _userName![0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
            ),
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MFU TRACKER',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          if (_userName != null)
            Text(
              _userName!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.onPrimary,
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          icon: const Icon(
            Icons.notifications_outlined,
            color: AppColors.onPrimary,
          ),
          padding: const EdgeInsets.only(right: 8),
        ),
      ],
    );
  }

  Widget _buildCalendarStrip() {
    final daysInMonth = DateUtils.getDaysInMonth(
      _focusedMonth.year,
      _focusedMonth.month,
    );
    final monthLabel = _monthName(_focusedMonth.month);
    const itemWidth = 48.0;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _prevMonth,
                icon: const Icon(
                  Icons.chevron_left,
                  color: AppColors.onSurfaceVariant,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                '$monthLabel ${_focusedMonth.year}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              IconButton(
                onPressed: _nextMonth,
                icon: const Icon(
                  Icons.chevron_right,
                  color: AppColors.onSurfaceVariant,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 66,
            child: ListView.builder(
              controller: _calendarScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: daysInMonth,
              itemExtent: itemWidth,
              itemBuilder: (context, i) {
                final day = i + 1;
                final date = DateTime(
                  _focusedMonth.year,
                  _focusedMonth.month,
                  day,
                );
                final now = DateTime.now();
                final isSelected =
                    _selectedDate?.day == day &&
                    _selectedDate?.month == _focusedMonth.month &&
                    _selectedDate?.year == _focusedMonth.year;
                final isToday =
                    date.day == now.day &&
                    date.month == now.month &&
                    date.year == now.year;
                final hasRoutes = _routes.any(
                  (r) =>
                      r.startTime.day == day &&
                      r.startTime.month == _focusedMonth.month &&
                      r.startTime.year == _focusedMonth.year,
                );

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDate = date);
                    _scrollToDay(day);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _dayLetter(date.weekday),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isToday && !isSelected
                              ? Border.all(color: AppColors.primary, width: 1.5)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppColors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedOpacity(
                        opacity: hasRoutes ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : AppColors.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
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
              onPressed: _fetchRoutes,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final filtered = _filteredRoutes;
    if (filtered.isEmpty) return _buildEmptyState();

    return ListView(
      padding: EdgeInsets.zero,
      children: [_buildMap(), _buildRouteList(filtered)],
    );
  }

  Widget _buildMap() {
    final polylinePoints = _selectedRoute?.waypoints ?? [];

    return SizedBox(
      height: 240,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: polylinePoints.isNotEmpty
                  ? polylinePoints.first
                  : _mfuCenter,
              initialZoom: 17,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mfu.vehicletracker',
              ),
              if (polylinePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: polylinePoints,
                      color: AppColors.primary,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              if (polylinePoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: polylinePoints.first,
                      width: 28,
                      height: 28,
                      child: _RouteEndpoint(
                        color: const Color(0xFF1E8A3E),
                        icon: Icons.trip_origin,
                      ),
                    ),
                    Marker(
                      point: polylinePoints.last,
                      width: 28,
                      height: 28,
                      child: _RouteEndpoint(
                        color: AppColors.error,
                        icon: Icons.location_on,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                _MapFab(
                  icon: Icons.my_location,
                  onTap: () {
                    final center = polylinePoints.isNotEmpty
                        ? polylinePoints.first
                        : _mfuCenter;
                    _mapController.move(center, 17);
                  },
                ),
                const SizedBox(height: 8),
                if (_selectedRoute != null)
                  _MapFab(
                    icon: Icons.flag_outlined,
                    onTap: () {
                      if (polylinePoints.isNotEmpty) {
                        _mapController.move(polylinePoints.last, 17);
                      }
                    },
                  ),
              ],
            ),
          ),
          if (_selectedRoute == null)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.center,
                  color: Colors.black.withValues(alpha: 0.05),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Tap a route below to view on map',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRouteList(List<_RouteEntry> routes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'Route History Log',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${routes.length} trip${routes.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...routes.asMap().entries.map(
            (e) => _RouteCard(
              entry: e.value,
              index: e.key,
              isSelected: _selectedRoute?.id == e.value.id,
              onTap: () => _selectRoute(e.value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final label = _selectedDate != null
        ? '${_selectedDate!.day} ${_monthName(_selectedDate!.month)} ${_selectedDate!.year}'
        : '${_monthName(_focusedMonth.month)} ${_focusedMonth.year}';
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
              Icons.history,
              size: 36,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No routes found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No tracking data for $label',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month];

  String _dayLetter(int weekday) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];
}

// ── Route Card ────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final _RouteEntry entry;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _RouteCard({
    required this.entry,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isSelected ? AppColors.primary : AppColors.outlineVariant,
              width: isSelected ? 4 : 2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: isSelected ? 12 : 6,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Start: ${_fmtDateTime(entry.startTime)} • End: ${_fmtTime(entry.endTime)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryContainer.withValues(alpha: 0.15)
                        : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    entry.distanceLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _WaypointRow(
              icon: Icons.trip_origin,
              color: const Color(0xFF1E8A3E),
              label: 'Point A',
              value: entry.startLabel,
            ),
            Container(
              margin: const EdgeInsets.only(left: 6),
              width: 1,
              height: 12,
              color: AppColors.outlineVariant,
            ),
            _WaypointRow(
              icon: Icons.location_on,
              color: AppColors.error,
              label: 'Point B',
              value: entry.endLabel,
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    final day = dt.day;
    final month = const [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][dt.month];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$day $month, $h:$m $period';
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }
}

class _WaypointRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _WaypointRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Map FAB ───────────────────────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: AppColors.onSurface),
      ),
    );
  }
}

// ── Route Endpoint Marker ─────────────────────────────────────────────────────

class _RouteEndpoint extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _RouteEndpoint({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }
}

// ── Data Model ────────────────────────────────────────────────────────────────

class _RouteEntry {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final List<LatLng> waypoints;

  const _RouteEntry({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.waypoints,
  });

  factory _RouteEntry.fromJson(Map<String, dynamic> json) => _RouteEntry(
    id: json['id'] as String,
    startTime: DateTime.parse(json['start_time'] as String).toLocal(),
    endTime: DateTime.parse(json['end_time'] as String).toLocal(),
    waypoints: (json['waypoints'] as List)
        .cast<Map<String, dynamic>>()
        .map((w) => LatLng(w['lat'] as double, w['lng'] as double))
        .toList(),
  );

  String get startLabel => 'MFU Campus';
  String get endLabel => 'Last known location';

  String get distanceLabel {
    if (waypoints.length < 2) {
      final minutes = endTime.difference(startTime).inMinutes;
      return '~${minutes}min';
    }
    double total = 0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      total += _haversineKm(waypoints[i], waypoints[i + 1]);
    }
    return total >= 1
        ? '${total.toStringAsFixed(1)} km'
        : '${(total * 1000).round()} m';
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final x =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.latitude)) *
            math.cos(_deg2rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  static double _deg2rad(double deg) => deg * math.pi / 180;
}

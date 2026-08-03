import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme/app_theme.dart';
import 'live_tracking_screen.dart';
import 'login_screen.dart' show UserSession;
import 'route_history_screen.dart';
import 'vehicle_profile_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _baseUrl = 'http://localhost:8001';

  final _storage = const FlutterSecureStorage();

  int _selectedIndex = 0;
  bool _loadingVehicle = true;
  String? _vehicleError;
  Map<String, dynamic>? _vehicle;

  @override
  void initState() {
    super.initState();
    _loadVehicle();
  }

  Future<String?> _getToken() async {
    if (UserSession.instance.token != null) return UserSession.instance.token;
    try {
      return await _storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadVehicle() async {
    setState(() {
      _loadingVehicle = true;
      _vehicleError = null;
    });
    final token = await _getToken();
    if (token == null) {
      setState(() {
        _loadingVehicle = false;
        _vehicleError = 'Not logged in.';
      });
      return;
    }
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).get('/vehicles');
      final vehicles = (res.data as List).cast<Map<String, dynamic>>();
      setState(() {
        _vehicle = vehicles.isNotEmpty ? vehicles.first : null;
        _vehicleError = vehicles.isEmpty ? 'No vehicle registered yet.' : null;
        _loadingVehicle = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loadingVehicle = false;
        _vehicleError =
            e.response?.data?['detail']?.toString() ??
            'Could not load vehicle.';
      });
    }
  }

  List<Widget> _buildPages() {
    final vehicle = _vehicle;
    final noVehicleView = _NoVehicleView(
      loading: _loadingVehicle,
      message: _vehicleError,
      onRetry: _loadVehicle,
    );
    return [
      vehicle != null
          ? LiveTrackingScreen(
              vehicleId: vehicle['id'] as String,
              vehicleName: vehicle['model'] as String? ?? 'My Vehicle',
              licensePlate: vehicle['license_plate'] as String? ?? '—',
            )
          : noVehicleView,
      vehicle != null
          ? RouteHistoryScreen(vehicleId: vehicle['id'] as String)
          : noVehicleView,
      const VehicleProfileScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _buildPages()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primaryContainer.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: AppColors.primary),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: AppColors.primary),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.motorcycle_sharp),
            selectedIcon: Icon(
              Icons.motorcycle_sharp,
              color: AppColors.primary,
            ),
            label: 'Vehicle',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primary),
            label: 'Profile',
          ),
        ],
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
      ),
    );
  }
}

// ── Shown on the Map/History tabs when the user has no vehicle in MongoDB ────

class _NoVehicleView extends StatelessWidget {
  final bool loading;
  final String? message;
  final VoidCallback onRetry;

  const _NoVehicleView({
    required this.loading,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.two_wheeler_outlined,
              size: 48,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message ?? 'No vehicle registered yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

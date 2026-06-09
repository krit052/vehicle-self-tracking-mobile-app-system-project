import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'live_tracking_screen.dart';
import 'route_history_screen.dart';
import 'vehicle_profile_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          LiveTrackingScreen(
            vehicleId: '31233',
            vehicleName: 'Honda Wave 110i',
            licensePlate: 'กข-1234',
          ),
          RouteHistoryScreen(vehicleId: '31233'),
          VehicleProfileScreen(),
          ProfileScreen(),
        ],
      ),
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
            selectedIcon: Icon(Icons.motorcycle_sharp, color: AppColors.primary),
            label: 'Vehicle',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primary),
            label: 'Profile',
          ),
        ],
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

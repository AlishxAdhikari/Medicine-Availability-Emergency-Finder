import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import 'ambulance_screen.dart';
import 'blood_bank_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'medicine_screen.dart';
import 'profile_screen.dart';

final selectedTabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    // Initialize location provider when app starts
    ref.watch(locationProvider);

    if (authState.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!authState.isLoggedIn) {
      return const LoginScreen();
    }

    return const _MainAppShell();
  }
}

class _MainAppShell extends ConsumerWidget {
  const _MainAppShell();

  static const _screens = [
    HomeScreen(),
    MedicineScreen(),
    BloodBankScreen(),
    AmbulanceScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => ref.read(selectedTabProvider.notifier).state = index,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: 'Medicines',
          ),
          NavigationDestination(
            icon: Icon(Icons.bloodtype_outlined),
            selectedIcon: Icon(Icons.bloodtype),
            label: 'Blood',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Ambulance',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

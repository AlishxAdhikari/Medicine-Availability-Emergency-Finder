import 'package:flutter/material.dart';
import '../state.dart';
import '../services/auth_service.dart';
import '../services/medical_profile_service.dart';
import '../widgets/initials_avatar.dart';
import 'pharmacy_search_screen.dart';
import 'emergency_screen.dart';
import 'medical_id_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const HomeDashboardTab(),
    const PharmacySearchScreen(),
    const EmergencyScreen(),
    const MedicalIdScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Pull the persisted medical profile (blood group, allergies,
    // medications, emergency contact) as soon as the user lands on the
    // home shell after login, so the Medical ID tab -- and the QR code it
    // generates -- reflects real backend data rather than whatever was
    // set at registration. Silently ignored on failure (e.g. offline);
    // the screen just keeps showing whatever's already in local state.
    MedicalProfileService.instance.fetch().catchError((_) {
      return AppStateManager.instance.userProfileNotifier.value;
    });
  }

  void navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                AppStateManager.instance.setLoggedIn(false);
                AppStateManager.instance.resetProfile();
                await AuthService.instance.logout();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, ThemeData theme, bool isDark) {
    final state = AppStateManager.instance;
    
    return Drawer(
      child: Container(
        color: isDark ? const Color(0xFF191C20) : Colors.white,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF282A2F) : theme.colorScheme.primary,
              ),
              accountName: ValueListenableBuilder<UserProfile>(
                valueListenable: state.userProfileNotifier,
                builder: (context, profile, _) => Text(
                  profile.fullName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              accountEmail: ValueListenableBuilder<UserProfile>(
                valueListenable: state.userProfileNotifier,
                builder: (context, profile, _) => Text(
                  profile.medicalId,
                ),
              ),
              currentAccountPicture: ValueListenableBuilder<UserProfile>(
                valueListenable: state.userProfileNotifier,
                builder: (context, profile, _) {
                  return InitialsAvatar(
                    name: profile.fullName,
                    imageUrl: profile.profilePictureUrl,
                    radius: 20,
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                navigateToTab(0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_pharmacy),
              title: const Text('Pharmacy Search'),
              onTap: () {
                navigateToTab(1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emergency_share),
              title: const Text('Emergency Services'),
              onTap: () {
                navigateToTab(2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.contact_emergency),
              title: const Text('Medical ID'),
              onTap: () {
                navigateToTab(3);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
              ),
              title: Text(isDark ? 'Light Mode' : 'Dark Mode'),
              onTap: () {
                state.toggleTheme();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFBA1A1A)),
              title: const Text('Logout', style: TextStyle(color: Color(0xFFBA1A1A))),
              onTap: () {
                Navigator.pop(context);
                _showLogoutDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF191C20) : theme.colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          'MedAlert',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              AppStateManager.instance.toggleTheme();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            color: theme.colorScheme.onSurfaceVariant,
            onPressed: () {
              _showLogoutDialog(context);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _tabs[_currentIndex],
      drawer: _buildDrawer(context, theme, isDark),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: navigateToTab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDark ? const Color(0xFF191C20) : Colors.white,
        selectedItemColor: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_pharmacy),
            label: 'Pharmacy',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emergency_share),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contact_emergency),
            label: 'Medical ID',
          ),
        ],
      ),
    );
  }
}

class HomeDashboardTab extends StatelessWidget {
  const HomeDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = AppStateManager.instance;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Welcome Section
          ValueListenableBuilder<UserProfile>(
            valueListenable: state.userProfileNotifier,
            builder: (context, profile, _) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1D2024) : const Color(0xFFF1F3FC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good morning,',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hello, ${profile.fullName.split(' ').first}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFFAAC7FF)
                              : theme.colorScheme.primaryContainer,
                          width: 2,
                        ),
                      ),
                      child: InitialsAvatar(
                        name: profile.fullName,
                        imageUrl: profile.profilePictureUrl,
                        radius: 26,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Quick Actions Bento Grid
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  'Quick Actions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _buildQuickActionCard(
                    context,
                    icon: Icons.local_pharmacy,
                    label: 'Pharmacy Search',
                    color: isDark
                        ? const Color(0xFF282A2F)
                        : Colors.white,
                    iconColor: isDark
                        ? const Color(0xFFAAC7FF)
                        : theme.colorScheme.primary,
                    onTap: () {
                      final shell = context.findAncestorStateOfType<_AppShellState>();
                      shell?.navigateToTab(1);
                    },
                  ),
                  _buildQuickActionCard(
                    context,
                    icon: Icons.emergency,
                    label: 'Emergency Services',
                    color: const Color(0xFFFFDAD6).withValues(alpha: 0.3),
                    iconColor: const Color(0xFFBA1A1A),
                    borderColor: const Color(0xFFBA1A1A).withValues(alpha: 0.3),
                    onTap: () {
                      final shell = context.findAncestorStateOfType<_AppShellState>();
                      shell?.navigateToTab(2);
                    },
                  ),
                  _buildQuickActionCard(
                    context,
                    icon: Icons.badge,
                    label: 'Medical ID',
                    color: isDark
                        ? const Color(0xFF282A2F)
                        : Colors.white,
                    iconColor: isDark
                        ? const Color(0xFFAAC7FF)
                        : theme.colorScheme.primary,
                    onTap: () {
                      final shell = context.findAncestorStateOfType<_AppShellState>();
                      shell?.navigateToTab(3);
                    },
                  ),
                  _buildQuickActionCard(
                    context,
                    icon: Icons.bloodtype,
                    label: 'Blood Bank',
                    color: isDark
                        ? const Color(0xFF282A2F)
                        : Colors.white,
                    iconColor: isDark
                        ? const Color(0xFFFFB68C)
                        : theme.colorScheme.tertiary,
                    onTap: () {
                      final shell = context.findAncestorStateOfType<_AppShellState>();
                      shell?.navigateToTab(2); // Goes to emergency (which contains blood banks)
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Nearby Blood Banks
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nearby Blood Banks',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          final shell = context.findAncestorStateOfType<_AppShellState>();
                          state.isBloodBankMapViewNotifier.value = true;
                          shell?.navigateToTab(2);
                        },
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text('View on Map', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () {
                          final shell = context.findAncestorStateOfType<_AppShellState>();
                          state.isBloodBankMapViewNotifier.value = false;
                          shell?.navigateToTab(2);
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('View All', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildBloodBankCard(
                      context,
                      name: 'Central Blood Bank',
                      distance: '1.2 miles away',
                      availability: [
                        {'type': 'O+', 'status': 'Available', 'color': const Color(0xFF008800)},
                        {'type': 'A-', 'status': 'Critical', 'color': const Color(0xFFBA1A1A)},
                      ],
                    ),
                    const SizedBox(width: 12),
                    _buildBloodBankCard(
                      context,
                      name: 'Red Cross Center',
                      distance: '3.5 miles away',
                      availability: [
                        {'type': 'B+', 'status': 'Low Stock', 'color': const Color(0xFFB47A00)},
                        {'type': 'AB+', 'status': 'Available', 'color': const Color(0xFF008800)},
                      ],
                    ),
                    const SizedBox(width: 12),
                    _buildBloodBankCard(
                      context,
                      name: 'City General Hospital',
                      distance: '5.0 miles away',
                      availability: [
                        {'type': 'O-', 'status': 'Critical', 'color': const Color(0xFFBA1A1A)},
                        {'type': 'A+', 'status': 'Low Stock', 'color': const Color(0xFFB47A00)},
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor ??
                (isDark
                    ? const Color(0xFF44474E).withValues(alpha: 0.3)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBloodBankCard(
      BuildContext context, {
      required String name,
      required String distance,
      required List<Map<String, dynamic>> availability,
    }) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;

      return Container(
        width: 280,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1D2024) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            distance,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF282A2F)
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Current Availability:',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: availability.map((item) {
                  final statusColor = item['color'] as Color;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF15181C)
                            : const Color(0xFFF1F3FC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item['type'],
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['status'],
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }
}
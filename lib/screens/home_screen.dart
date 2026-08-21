import 'package:flutter/material.dart';
import '../state.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/medical_profile_service.dart';
import '../widgets/emergency_call.dart';
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

              final biometricOn = await BiometricService.instance.isEnabled;

              if (biometricOn) {
                final p = AppStateManager.instance.userProfileNotifier.value;
                await BiometricService.instance.saveUserSnapshot(profileToSnapshot(p));
              }

              await AuthService.instance.logout(keepBiometricSession: biometricOn);

              AppStateManager.instance.clearOwnerRole();
              AppStateManager.instance.setLoggedIn(false);
              if (!biometricOn) {
                AppStateManager.instance.resetProfile();
              }

              if (context.mounted) {
                // RemoveUntil, not pushReplacement. An owner reaches this
                // shell from the dashboard's home button, which pushes ON TOP
                // of /owner -- so replacing only this route leaves /owner
                // sitting underneath, and one back press hands a logged-out
                // person the stock editor. Clearing the stack is also what
                // makes logging out mean the same thing from every screen.
                Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
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
            // Owners only. The dashboard's own app bar can send them here, and
            // without this the only route back was the hardware back button --
            // which does not exist on a fingerprint login that landed on
            // /owner and walked forward, and does not exist at all on iOS.
            ValueListenableBuilder<bool>(
              valueListenable: state.isPharmacyOwnerNotifier,
              builder: (context, isOwner, _) {
                if (!isOwner) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.store),
                  title: const Text('My Pharmacy'),
                  subtitle: ValueListenableBuilder<String>(
                    valueListenable: state.ownedPharmacyNameNotifier,
                    builder: (context, name, _) =>
                        name.isEmpty ? const SizedBox.shrink() : Text(name),
                  ),
                  onTap: () {
                    Navigator.pop(context); // close the drawer
                    // RemoveUntil so walking /owner -> /home -> /owner doesn't
                    // stack a second dashboard behind this one. Leaves the
                    // owner exactly where login puts them.
                    Navigator.pushNamedAndRemoveUntil(
                      context, '/owner', (route) => false,
                    );
                  },
                );
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
      // One tap to the ambulance from wherever the user happens to be, instead
      // of a tab switch and a scroll. Hidden on the emergency tab itself,
      // which already leads with a much larger version of the same action.
      floatingActionButton:
          _currentIndex == 2 ? null : const SosFloatingButton(),
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = AppStateManager.instance;
    final bg = isDark ? const Color(0xFF111418) : const Color(0xFFF0F2F7);

    return ColoredBox(
      color: bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Welcome hero ──
            ValueListenableBuilder<UserProfile>(
              valueListenable: state.userProfileNotifier,
              builder: (context, profile, _) {
                final first = profile.fullName.trim().isEmpty
                    ? 'there'
                    : profile.fullName.trim().split(' ').first;
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF003D7A),
                        Color(0xFF005AB4),
                        Color(0xFF0A73E0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF005AB4).withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              first,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                profile.bloodGroup.isNotEmpty
                                    ? 'Blood · ${profile.bloodGroup}'
                                    : 'Your health dashboard',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: InitialsAvatar(
                          name: profile.fullName.isNotEmpty
                              ? profile.fullName
                              : 'U',
                          imageUrl: profile.profilePictureUrl,
                          radius: 28,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 18),

            // ── Quick actions ──
            _sectionLabel(context, 'Quick Actions'),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.35,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: [
                _actionTile(
                  context,
                  icon: Icons.local_pharmacy_rounded,
                  label: 'Pharmacy\nSearch',
                  accent: const Color(0xFF0A73E0),
                  onTap: () {
                    context
                        .findAncestorStateOfType<_AppShellState>()
                        ?.navigateToTab(1);
                  },
                ),
                _actionTile(
                  context,
                  icon: Icons.emergency_rounded,
                  label: 'Emergency\nServices',
                  accent: const Color(0xFFBA1A1A),
                  softBg: true,
                  onTap: () {
                    context
                        .findAncestorStateOfType<_AppShellState>()
                        ?.navigateToTab(2);
                  },
                ),
                _actionTile(
                  context,
                  icon: Icons.badge_rounded,
                  label: 'Medical\nID',
                  accent: const Color(0xFF0A73E0),
                  onTap: () {
                    context
                        .findAncestorStateOfType<_AppShellState>()
                        ?.navigateToTab(3);
                  },
                ),
                _actionTile(
                  context,
                  icon: Icons.bloodtype_rounded,
                  label: 'Blood\nBank',
                  accent: const Color(0xFFB45309),
                  onTap: () {
                    context
                        .findAncestorStateOfType<_AppShellState>()
                        ?.navigateToTab(2);
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ── Nearby blood banks ──
            Row(
              children: [
                Expanded(child: _sectionLabel(context, 'Nearby Blood Banks')),
                TextButton(
                  onPressed: () {
                    state.isBloodBankMapViewNotifier.value = true;
                    context
                        .findAncestorStateOfType<_AppShellState>()
                        ?.navigateToTab(2);
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Map', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () {
                    state.isBloodBankMapViewNotifier.value = false;
                    context
                        .findAncestorStateOfType<_AppShellState>()
                        ?.navigateToTab(2);
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('View all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 168,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _bloodPreviewCard(
                    context,
                    name: 'Central Blood Bank',
                    distance: '1.2 miles',
                    availability: const [
                      ('O+', 'Available', Color(0xFF00897B)),
                      ('A-', 'Critical', Color(0xFFBA1A1A)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  _bloodPreviewCard(
                    context,
                    name: 'Red Cross Center',
                    distance: '3.5 miles',
                    availability: const [
                      ('B+', 'Low Stock', Color(0xFFB47A00)),
                      ('AB+', 'Available', Color(0xFF00897B)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  _bloodPreviewCard(
                    context,
                    name: 'City General Hospital',
                    distance: '5.0 miles',
                    availability: const [
                      ('O-', 'Critical', Color(0xFFBA1A1A)),
                      ('A+', 'Low Stock', Color(0xFFB47A00)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
    bool softBg = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: softBg
                ? const Color(0xFFBA1A1A).withValues(alpha: isDark ? 0.14 : 0.07)
                : (isDark ? const Color(0xFF1D2024) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: softBg
                  ? const Color(0xFFBA1A1A).withValues(alpha: 0.22)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE6EAF0)),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.2,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bloodPreviewCard(
    BuildContext context, {
    required String name,
    required String distance,
    required List<(String, String, Color)> availability,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D2024) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE6EAF0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFBA1A1A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.bloodtype_rounded,
                    size: 16, color: Color(0xFFBA1A1A)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    Text(
                      distance,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: availability.map((item) {
                final (type, status, color) = item;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          type,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
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

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/medical_profile_service.dart';
import '../state.dart';
import '../widgets/medalert_mark.dart';

/// Picks the landing route from the `role` field on the login response
/// (core/serializers.py's UserSerializer). Falls back to the user home when
/// role is missing, so an older backend degrades to the read-only
/// experience rather than opening an editor the account can't use.
String routeForRole(Map<String, dynamic> user) {
  return user['role'] == 'pharmacy_owner' ? '/owner' : '/home';
}

/// Records the owner role from a `user` object -- either the one on the login
/// response or the one GET /auth/me/ returns, which are the same shape
/// (UserSerializer). Shared so the password and biometric paths cannot drift.
///
/// `as num?` on the id rather than `as int?`: JSON that round-tripped through
/// storage can hand back a whole number as a double, and a hard cast would
/// throw where the rest of this degrades to a default.
void applyRoleFromUser(Map<String, dynamic> user) {
  final pharmacy = user['pharmacy'] as Map<String, dynamic>?;
  AppStateManager.instance.setOwnerRole(
    isOwner: user['role'] == 'pharmacy_owner',
    pharmacyId: (pharmacy?['id'] as num?)?.toInt(),
    pharmacyName: pharmacy?['name'] as String? ?? '',
  );
  final username = (user['username'] as String? ?? '').trim();
  if (username.isNotEmpty) {
    AppStateManager.instance.setUsername(username);
  }
}

/// Clips a container into the curved "hero" shape used behind the header:
/// a flat top and sides with the bottom edge sweeping down into a shallow
/// smile, so the brand-color panel reads as one continuous curved shape
/// rather than a rectangle.
class _HeaderCurveClipper extends CustomClipper<Path> {
  const _HeaderCurveClipper();

  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - 56)
      ..quadraticBezierTo(size.width * 0.5, size.height + 36, size.width, size.height - 56)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _biometricLoading = false;

  Future<void> _handleBiometricLogin() async {
    setState(() => _biometricLoading = true);
    try {
      final success = await BiometricService.instance.loginWithBiometrics();
      if (!mounted) return;

      if (success) {
        AppStateManager.instance.clearOwnerRole();

        final snapshot = await BiometricService.instance.getUserSnapshot();
        if (snapshot != null) {
          AppStateManager.instance.updateProfile(profileFromSnapshot(snapshot));
          applyOwnerRoleFromSnapshot(snapshot);
        }

        try {
          applyRoleFromUser(await AuthService.instance.currentUser());
        } catch (_) {}

        try {
          await MedicalProfileService.instance.fetch();
        } catch (_) {}

        final p = AppStateManager.instance.userProfileNotifier.value;
        await BiometricService.instance.saveUserSnapshot(profileToSnapshot(p));
        if (!mounted) return;

        AppStateManager.instance.setLoggedIn(true);
        Navigator.pushReplacementNamed(
          context,
          AppStateManager.instance.isPharmacyOwnerNotifier.value ? '/owner' : '/home',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometric login failed. Make sure you enabled it during signup and this device has a fingerprint enrolled.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _biometricLoading = false);
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Says how a forgotten password actually gets reset today.
  ///
  /// Self-service reset needs an endpoint the backend does not have and a
  /// mail sender it is not configured for; until both exist, an administrator
  /// resetting the account through the Django admin is the real answer, and
  /// the screen should say so rather than imply a flow that isn't there.
  void _showPasswordHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot your password?'),
        content: const Text(
          'MedAlert cannot reset passwords from the app yet. Ask your '
          'MedAlert administrator to reset it for you, then sign in with '
          'the new password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final identifier = _identifierController.text.trim();
      final loginData = await AuthService.instance.login(
        username: identifier,
        password: _passwordController.text,
      );
      if (!mounted) return;
      final user = (loginData['user'] ?? {}) as Map<String, dynamic>;
      final firstName = (user['first_name'] as String? ?? '').trim();
      final lastName = (user['last_name'] as String? ?? '').trim();
      final persistedName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
      AppStateManager.instance.updateProfile(
        AppStateManager.instance.buildProfileFromAuth(
          fullName: persistedName.isNotEmpty ? persistedName : null,
          email: user['email'] as String? ?? identifier,
          phoneNumber: null,
        ),
      );

      try {
        await MedicalProfileService.instance.fetch();
      } catch (_) {}

      applyRoleFromUser(user);

      if (await BiometricService.instance.isEnabled) {
        final p = AppStateManager.instance.userProfileNotifier.value;
        await BiometricService.instance.saveUserSnapshot(profileToSnapshot(p));
      }
      if (!mounted) return;

      AppStateManager.instance.setLoggedIn(true);
      Navigator.pushReplacementNamed(context, routeForRole(user));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not reach the server. Check your connection and try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor = isDark ? const Color(0xFF14335C) : theme.colorScheme.primary;
    final scaffoldBg = theme.scaffoldBackgroundColor;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppStateManager.instance.themeModeNotifier,
      builder: (context, themeMode, _) {
        return Scaffold(
          backgroundColor: scaffoldBg,
          body: Stack(
            children: [
              Positioned(
                top: 220,
                left: -70,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: -90,
                right: -70,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.05),
                  ),
                ),
              ),

              SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Curved brand-color hero
                      ClipPath(
                        clipper: const _HeaderCurveClipper(),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                headerColor,
                                isDark ? const Color(0xFF0B2444) : theme.colorScheme.primaryContainer,
                              ],
                            ),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: -60,
                                right: -40,
                                child: Container(
                                  width: 180,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                              ),
                              Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _HeaderIconButton(
                                        icon: isDark ? Icons.light_mode : Icons.dark_mode,
                                        onPressed: () => AppStateManager.instance.toggleTheme(),
                                      ),
                                      const SizedBox(width: 8),
                                      _HeaderIconButton(
                                        icon: Icons.dns_outlined,
                                        tooltip: 'Server settings',
                                        onPressed: () => Navigator.of(context).pushNamed('/settings'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Original mark (no image)
                                  MedAlertMark(size: 60, holeColor: headerColor),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'MedAlert',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'When It Matters, We\'re There.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Full-bleed form content below the hero.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _identifierController,
                                decoration: const InputDecoration(
                                  hintText: 'Email or Phone Number',
                                  prefixIcon: Icon(Icons.person),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter email or phone number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter password';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),

                              // A "Forgot Password?" link used to sit here and
                              // push /forgot_password, a route that was never
                              // registered -- tapping it threw. There is no
                              // reset endpoint on the backend either, so the
                              // honest thing is to say who can reset it rather
                              // than offer a door that opens onto nothing.
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => _showPasswordHelp(context),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Forgot Password?',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                                  foregroundColor: isDark ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _isLoading
                                    ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: isDark ? Colors.black : Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Login to MedAlert',
                                            style: theme.textTheme.labelLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.black : Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward,
                                            size: 18,
                                            color: isDark ? Colors.black : Colors.white,
                                          ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 24),

                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: Text(
                                      'Or continue with',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.outline,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              OutlinedButton(
                                onPressed: _biometricLoading ? null : _handleBiometricLogin,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _biometricLoading
                                        ? SizedBox(
                                            height: 32,
                                            width: 32,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.secondary,
                                            ),
                                          )
                                        : Icon(
                                            Icons.fingerprint,
                                            size: 32,
                                            color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.secondary,
                                          ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Biometric Login',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: isDark ? Colors.white70 : theme.colorScheme.secondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'New to MedAlert?',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pushNamed(context, '/create_account');
                                      },
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'Create Account',
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
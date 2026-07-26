import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../state.dart';

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digitsOnly.length > 8 ? digitsOnly.substring(0, 8) : digitsOnly;

    final buffer = StringBuffer();
    for (int i = 0; i < truncated.length; i++) {
      if (i == 4 || i == 6) {
        buffer.write('-');
      }
      buffer.write(truncated[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _selectedGender;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _enableBiometricLogin = false; // the toggle's value

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    DateTime initialDate = DateTime(2000, 1, 1);
    if (_dobController.text.trim().length == 10) {
      try {
        final parts = _dobController.text.trim().split('-');
        final y = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final d = int.parse(parts[2]);
        initialDate = DateTime(y, m, d);
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      final formattedMonth = picked.month.toString().padLeft(2, '0');
      final formattedDay = picked.day.toString().padLeft(2, '0');
      _dobController.text = '${picked.year}-$formattedMonth-$formattedDay';
    }
  }

  String? _validateDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your date of birth';
    }
    final val = value.trim();
    final regex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!regex.hasMatch(val)) {
      return 'Enter date in YYYY-MM-DD format';
    }
    final parts = val.split('-');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);

    if (year == null || month == null || day == null) {
      return 'Invalid date';
    }
    if (year < 1900 || year > DateTime.now().year) {
      return 'Year must be between 1900 and ${DateTime.now().year}';
    }
    if (month < 1 || month > 12) {
      return 'Month must be between 01 and 12';
    }
    if (day < 1 || day > 31) {
      return 'Day must be between 01 and 31';
    }
    try {
      final parsedDate = DateTime(year, month, day);
      if (parsedDate.isAfter(DateTime.now())) {
        return 'Date of birth cannot be in the future';
      }
    } catch (_) {
      return 'Invalid date';
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final fullName = _nameController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final password = _passwordController.text;
      // Django's username field rejects spaces, so it can never safely be
      // the person's raw full name -- derive a valid one from the email
      // instead, and send the real name separately so it's persisted.
      final username = AuthService.generateUsername(email);

      await AuthService.instance.register(
        username: username,
        email: email,
        password: password,
        phone: phone,
        fullName: fullName,
      );
      await AuthService.instance.login(username: username, password: password);

      // Must come after login() so a refresh token is already saved --
      // biometric login works by unlocking that stored token, not by
      // storing any fingerprint data anywhere.
     if (!mounted) return;

      final newProfile = AppStateManager.instance.buildProfileFromAuth(
        fullName: fullName,
        email: email,
        phoneNumber: phone,
        dob: _dobController.text.trim(),
        gender: _selectedGender,
      );
      AppStateManager.instance.updateProfile(newProfile);

      // Enroll AFTER profile exists so full user snapshot is saved
      if (_enableBiometricLogin) {
        final enrolled = await BiometricService.instance.enroll(
          userSnapshot: profileToSnapshot(newProfile),
        );
        if (!enrolled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account created, but biometric enrollment failed. You can try again from the login screen.',
              ),
            ),
          );
        }
      }

      AppStateManager.instance.setLoggedIn(true);
      Navigator.pushReplacementNamed(context, '/home');
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

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppStateManager.instance.themeModeNotifier,
      builder: (context, themeMode, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF191C20) : theme.colorScheme.surface.withValues(alpha: 0.8),
            elevation: 0,
            leadingWidth: 150,
            leading: Row(
              children: [
                const SizedBox(width: 16),
                Icon(
                  Icons.location_on,
                  color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'MedAlert',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.secondary,
                ),
                onPressed: () {
                  AppStateManager.instance.toggleTheme();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Stack(
            children: [
              // Atmospheric Glows
              Positioned(
                top: -100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -100,
                right: -100,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Content
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF191C20) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF44474E).withValues(alpha: 0.3)
                            : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Branding / Header
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF282A2F)
                                        : theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.transparent
                                          : theme.colorScheme.primary.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.person_add_alt_1,
                                    size: 32,
                                    color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Create Account',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.5,
                                    fontSize: 24,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Register to access medical resources',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Full Name
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              hintText: 'Full Name',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your full name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Date of Birth
                          TextFormField(
                            controller: _dobController,
                            decoration: InputDecoration(
                              hintText: 'Date of Birth (YYYY-MM-DD)',
                              prefixIcon: const Icon(Icons.calendar_today),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.edit_calendar),
                                tooltip: 'Select Date',
                                onPressed: () => _selectDate(context),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              DateInputFormatter(),
                            ],
                            validator: _validateDate,
                          ),
                          const SizedBox(height: 16),

                          // Gender Selection
                          DropdownButtonFormField<String>(
                            initialValue: _selectedGender,
                            hint: const Text('Select Gender'),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.people),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Male', child: Text('Male')),
                              DropdownMenuItem(value: 'Female', child: Text('Female')),
                              DropdownMenuItem(value: 'Other', child: Text('Other')),
                            ],
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedGender = newValue;
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please select your gender';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Phone Number
                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              hintText: 'Phone Number',
                              prefixIcon: Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Email
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              hintText: 'Email Address',
                              prefixIcon: Icon(Icons.email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password
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
                                return 'Please enter a password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Fingerprint enrollment toggle
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _enableBiometricLogin,
                            onChanged: (value) => setState(() => _enableBiometricLogin = value),
                            secondary: Icon(
                              Icons.fingerprint,
                              color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                            ),
                            title: const Text('Enable biometric login'),
                            subtitle: Text(
                              'Use your fingerprint to sign in next time',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Language Selector Toggle
                          ValueListenableBuilder<String>(
                            valueListenable: AppStateManager.instance.languageNotifier,
                            builder: (context, lang, _) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Preferred Language',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SegmentedButton<String>(
                                    segments: const <ButtonSegment<String>>[
                                      ButtonSegment<String>(
                                          value: 'en', label: Text('EN')),
                                      ButtonSegment<String>(
                                          value: 'ne', label: Text('NEP')),
                                    ],
                                    selected: <String>{lang},
                                    onSelectionChanged: (Set<String> selection) {
                                      AppStateManager.instance.toggleLanguage();
                                    },
                                    style: SegmentedButton.styleFrom(
                                      selectedBackgroundColor: isDark
                                          ? const Color(0xFFAAC7FF)
                                          : theme.colorScheme.primary,
                                      selectedForegroundColor:
                                          isDark ? Colors.black : Colors.white,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // Sign Up Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleSignUp,
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
                                        'Register to MedAlert',
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

                          // Footer Link
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Already have an account?',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Login',
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

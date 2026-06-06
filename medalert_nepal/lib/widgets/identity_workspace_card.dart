import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class IdentityWorkspaceCard extends StatefulWidget {
  const IdentityWorkspaceCard({super.key});

  @override
  State<IdentityWorkspaceCard> createState() => _IdentityWorkspaceCardState();
}

class _IdentityWorkspaceCardState extends State<IdentityWorkspaceCard> {
  final GlobalKey<FormState> _signInFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _signUpFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _medicalIdFormKey = GlobalKey<FormState>();

  final TextEditingController _signInEmailController = TextEditingController();
  final TextEditingController _signInPasswordController = TextEditingController();

  final TextEditingController _signUpNameController = TextEditingController();
  final TextEditingController _signUpEmailController = TextEditingController();
  final TextEditingController _signUpPasswordController = TextEditingController();
  final TextEditingController _signUpConfirmPasswordController = TextEditingController();

  final TextEditingController _bloodGroupController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  Position? _currentPosition;
  String _locationMessage = 'No GPS location fetched yet.';
  bool _isFetchingLocation = false;
  bool _obscureSignInPassword = true;
  bool _obscureSignUpPassword = true;
  bool _obscureSignUpConfirmPassword = true;

  final Map<String, String> _medicalId = {
    'bloodGroup': 'O+',
    'height': '171 cm',
    'weight': '68 kg',
  };

  @override
  void initState() {
    super.initState();
    _bloodGroupController.text = _medicalId['bloodGroup'] ?? '';
    _heightController.text = _medicalId['height'] ?? '';
    _weightController.text = _medicalId['weight'] ?? '';
  }

  @override
  void dispose() {
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmPasswordController.dispose();
    _bloodGroupController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isFetchingLocation = true;
      _locationMessage = 'Checking location permissions...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationMessage = 'Location services are disabled on this device/emulator.';
          _isFetchingLocation = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _locationMessage = 'Location permission denied.';
          _isFetchingLocation = false;
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationMessage = 'Location permission permanently denied. Enable it in settings.';
          _isFetchingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _locationMessage = 'GPS fix found at ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        _isFetchingLocation = false;
      });
    } catch (error) {
      setState(() {
        _locationMessage = 'Unable to fetch location: $error';
        _isFetchingLocation = false;
      });
    }
  }

  void _saveMedicalId() {
    if (!(_medicalIdFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _medicalId['bloodGroup'] = _bloodGroupController.text.trim();
      _medicalId['height'] = _heightController.text.trim();
      _medicalId['weight'] = _weightController.text.trim();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Medical ID saved locally on this device.')),
    );
  }

  void _submitSignIn() {
    if (!(_signInFormKey.currentState?.validate() ?? false)) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Signed in as ${_signInEmailController.text.trim()}')),
    );
  }

  void _submitSignUp() {
    if (!(_signUpFormKey.currentState?.validate() ?? false)) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Account created for ${_signUpNameController.text.trim()}')),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, String subtitle, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapPreview(BuildContext context) {
    final mapSupported = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!mapSupported || _currentPosition == null) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 44, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              _currentPosition == null ? 'Fetch GPS to preview the map' : 'Map preview available on Android/iOS devices',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final target = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 220,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: target, zoom: 15),
          markers: {
            Marker(markerId: const MarkerId('current-location'), position: target),
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colors.surface.withOpacity(0.94),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              context,
              'Authentication & Medical ID Master',
              'Sign-up, sign-in, and offline profile storage in one place.',
              Icons.verified_user_outlined,
            ),
            const SizedBox(height: 16),
            DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'Sign in'),
                      Tab(text: 'Sign up'),
                    ],
                    labelColor: colors.primary,
                    unselectedLabelColor: Colors.black54,
                    indicatorColor: colors.primary,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 355,
                    child: TabBarView(
                      children: [
                        Form(
                          key: _signInFormKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _signInEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: _fieldDecoration('Email address'),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter your email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _signInPasswordController,
                                obscureText: _obscureSignInPassword,
                                decoration: _fieldDecoration('Password').copyWith(
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscureSignInPassword = !_obscureSignInPassword;
                                      });
                                    },
                                    icon: Icon(_obscureSignInPassword ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.length < 6) {
                                    return 'Use at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _submitSignIn,
                                  child: const Text('Sign in'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFFAF7),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'This is a local UI form for demo onboarding. Wire it to your Django auth endpoint later.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Form(
                          key: _signUpFormKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _signUpNameController,
                                decoration: _fieldDecoration('Full name'),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter your name';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _signUpEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: _fieldDecoration('Email address'),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter your email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _signUpPasswordController,
                                obscureText: _obscureSignUpPassword,
                                decoration: _fieldDecoration('Password').copyWith(
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscureSignUpPassword = !_obscureSignUpPassword;
                                      });
                                    },
                                    icon: Icon(_obscureSignUpPassword ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.length < 6) {
                                    return 'Use at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _signUpConfirmPasswordController,
                                obscureText: _obscureSignUpConfirmPassword,
                                decoration: _fieldDecoration('Confirm password').copyWith(
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscureSignUpConfirmPassword = !_obscureSignUpConfirmPassword;
                                      });
                                    },
                                    icon: Icon(_obscureSignUpConfirmPassword ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                validator: (value) {
                                  if (value != _signUpPasswordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _submitSignUp,
                                  child: const Text('Create account'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader(
              context,
              'Medical ID Storage',
              'Save blood group, height, and weight locally for emergency access.',
              Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
            Form(
              key: _medicalIdFormKey,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _bloodGroupController,
                          decoration: _fieldDecoration('Blood group'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _heightController,
                          decoration: _fieldDecoration('Height'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _weightController,
                    decoration: _fieldDecoration('Weight'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _saveMedicalId,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save local medical ID'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'Stored value: ${_medicalId['bloodGroup']} | ${_medicalId['height']} | ${_medicalId['weight']}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader(
              context,
              'Geospatial Explorer',
              'Fetch the user GPS location on emulator and preview it in Google Maps when supported.',
              Icons.explore_outlined,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isFetchingLocation ? null : _fetchCurrentLocation,
                icon: _isFetchingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.my_location_outlined),
                label: Text(_isFetchingLocation ? 'Fetching location...' : 'Use current GPS location'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _locationMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            _buildMapPreview(context),
          ],
        ),
      ),
    );
  }
}

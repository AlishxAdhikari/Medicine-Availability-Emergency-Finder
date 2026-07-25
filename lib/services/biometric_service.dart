import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'api_client.dart';

/// Handles biometric login. Important: this never touches raw fingerprint
/// data -- that stays inside the phone's secure hardware. We only ask the
/// OS "did the fingerprint/face check pass?" (true/false), and on true we
/// unlock the JWT refresh token that's already saved in secure storage
/// from a normal password login, then use it to get a fresh access token.
class BiometricService {
  BiometricService._internal();
  static final BiometricService instance = BiometricService._internal();

  final _localAuth = LocalAuthentication();
  final _client = ApiClient.instance;
  static const _storage = FlutterSecureStorage();
  static const _enabledKey = 'biometric_login_enabled';

  /// True if this device has fingerprint/face hardware AND at least one
  /// fingerprint/face is enrolled in the device's own settings.
  Future<bool> isDeviceCapable() async {
    // local_auth has no web implementation -- browsers have no API for
    // this. Short-circuit instead of letting every check below fail
    // silently with a confusing "biometric login failed" message.
    if (kIsWeb) return false;
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Whether the current user has previously opted in on this device.
  Future<bool> get isEnabled async =>
      (await _storage.read(key: _enabledKey)) == 'true';

  /// Call after a successful password login/registration to turn biometric
  /// login on for this device. Prompts the fingerprint scan once to confirm
  /// it works, then flags this device as enrolled.
  Future<bool> enroll() async {
    final capable = await isDeviceCapable();
    if (!capable) return false;

    final refresh = await _client.refreshToken;
    if (refresh == null) return false; // must already be logged in

    final confirmed = await _authenticate(
      reason: 'Confirm your fingerprint to enable biometric login',
    );
    if (!confirmed) return false;

    await _storage.write(key: _enabledKey, value: 'true');
    return true;
  }

  /// Turns biometric login back off on this device. Does not log the user
  /// out or touch their password.
  Future<void> disable() async {
    await _storage.delete(key: _enabledKey);
  }

  /// The "Biometric Login" button action. Returns true if the user is now
  /// logged in.
  Future<bool> loginWithBiometrics() async {
    // Gate on the opt-in toggle -- without this check, biometric login
    // would silently work for anyone with a stored refresh token even if
    // they never turned the setting on during signup.
    if (!await isEnabled) return false;

    final refresh = await _client.refreshToken;
    if (refresh == null) {
      // Token was cleared (e.g. explicit logout elsewhere) -- biometrics
      // has nothing left to unlock, so fall back to password login.
      await disable();
      return false;
    }

    final confirmed = await _authenticate(
      reason: 'Authenticate to log in to MedAlert',
    );
    if (!confirmed) return false;

    return _client.refreshAccessToken();
  }

  Future<bool> _authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      // Hardware error, user cancelled, lockout from too many attempts, etc.
      return false;
    }
  }
}

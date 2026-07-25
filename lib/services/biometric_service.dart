import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'api_client.dart';

class BiometricService {
  BiometricService._internal();
  static final BiometricService instance = BiometricService._internal();

  final _localAuth = LocalAuthentication();
  final _client = ApiClient.instance;
  static const _storage = FlutterSecureStorage();
  static const _enabledKey = 'biometric_login_enabled';
  static const _userSnapshotKey = 'biometric_user_snapshot';

  Future<bool> isDeviceCapable() async {
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

  Future<bool> get isEnabled async =>
      (await _storage.read(key: _enabledKey)) == 'true';

  Future<bool> enroll({Map<String, dynamic>? userSnapshot}) async {
    final capable = await isDeviceCapable();
    if (!capable) return false;

    final refresh = await _client.refreshToken;
    if (refresh == null) return false;

    final confirmed = await _authenticate(
      reason: 'Confirm your fingerprint to enable biometric login',
    );
    if (!confirmed) return false;

    await _storage.write(key: _enabledKey, value: 'true');
    if (userSnapshot != null) {
      await saveUserSnapshot(userSnapshot);
    }
    return true;
  }

  Future<void> saveUserSnapshot(Map<String, dynamic> snapshot) async {
    await _storage.write(key: _userSnapshotKey, value: jsonEncode(snapshot));
  }

  Future<Map<String, dynamic>?> getUserSnapshot() async {
    final raw = await _storage.read(key: _userSnapshotKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> disable() async {
    await _storage.delete(key: _enabledKey);
    await _storage.delete(key: _userSnapshotKey);
  }

  Future<bool> loginWithBiometrics() async {
    if (!await isEnabled) return false;

    final refresh = await _client.refreshToken;
    if (refresh == null) {
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
      return false;
    }
  }
}
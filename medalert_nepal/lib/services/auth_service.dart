import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import '../models/medical_profile.dart';

class AuthService {
  final _client = ApiClient();
  final _storage = const FlutterSecureStorage();

  Future<bool> login(String username, String password) async {
    try {
      final response = await _client.dio.post('/auth/token/', data: {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 200) {
        final accessToken = response.data['access'] as String;
        final refreshToken = response.data['refresh'] as String;

        await _storage.write(key: 'access_token', value: accessToken);
        await _storage.write(key: 'refresh_token', value: refreshToken);
        await _storage.write(key: 'username', value: username);
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<bool> register(String username, String email, String password) async {
    try {
      final response = await _client.dio.post('/auth/register/', data: {
        'username': username,
        'email': email,
        'password': password,
        'password_confirm': password, // matched field
      });
      return response.statusCode == 201;
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'username');
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }

  Future<MedicalProfile> getProfile() async {
    try {
      final response = await _client.dio.get('/auth/profile/me/');
      return MedicalProfile.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to load profile: $e');
    }
  }

  Future<MedicalProfile> updateProfile(MedicalProfile profile) async {
    try {
      final response = await _client.dio.put('/auth/profile/me/', data: profile.toJson());
      return MedicalProfile.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to update medical ID profile: $e');
    }
  }
}

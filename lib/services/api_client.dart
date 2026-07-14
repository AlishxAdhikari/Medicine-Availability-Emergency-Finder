import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown for any non-2xx response. `errors` holds the parsed JSON body
/// when the server sent one (DRF validation errors, e.g. {"email": [...]})
/// so screens can show field-specific messages instead of a generic string.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? errors;

  ApiException(this.statusCode, this.message, {this.errors});

  @override
  String toString() => message;
}

/// Talks to the Django backend built in core/ and pharmacy/.
///
/// Handles three things every screen would otherwise have to repeat:
/// 1. Picking the right base URL for whichever platform is running.
/// 2. Storing/attaching the JWT access token.
/// 3. Transparently refreshing an expired access token once, then retrying.
class ApiClient {
  ApiClient._internal();
  static final ApiClient instance = ApiClient._internal();

  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  /// Android emulators can't reach the host machine via localhost -- they
  /// need the special 10.0.2.2 alias. iOS simulators and desktop/web can
  /// use localhost directly. Change this if you're testing on a physical
  /// device (use your machine's LAN IP instead).
  String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000/api/v1';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
    return 'http://127.0.0.1:8000/api/v1';
  }

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  Future<bool> get isLoggedIn async => (await accessToken) != null;

  Future<Map<String, String>> _headers({bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// GET with query params, e.g. get('/pharmacies/', query: {'district': 'Kathmandu'})
  Future<dynamic> get(String path, {Map<String, dynamic>? query, bool auth = false}) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
    );
    final response = await http.get(uri, headers: await _headers(auth: auth));
    return _handleResponse(response, retryRequest: () => get(path, query: query, auth: auth));
  }

  Future<dynamic> post(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.post(uri, headers: await _headers(auth: auth), body: jsonEncode(body));
    return _handleResponse(response, retryRequest: () => post(path, body, auth: auth));
  }

  /// PUT with a JSON body, e.g. put('/medical-id/', {...}, auth: true).
  /// Needed for endpoints like MedicalProfileView (RetrieveUpdateAPIView)
  /// that only accept PUT/PATCH, not POST, for updates.
  Future<dynamic> put(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.put(uri, headers: await _headers(auth: auth), body: jsonEncode(body));
    return _handleResponse(response, retryRequest: () => put(path, body, auth: auth));
  }

  Future<dynamic> _handleResponse(http.Response response, {required Future<dynamic> Function() retryRequest}) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    // Access token expired -- try to refresh once and replay the original
    // request, rather than making every screen handle 401s itself.
    if (response.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) return retryRequest();
      await clearTokens();
    }

    Map<String, dynamic>? errors;
    String message = 'Request failed (${response.statusCode})';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        errors = decoded;
        message = _firstErrorMessage(decoded) ?? message;
      }
    } catch (_) {
      // body wasn't JSON -- keep the generic message
    }
    throw ApiException(response.statusCode, message, errors: errors);
  }

  String? _firstErrorMessage(Map<String, dynamic> errors) {
    for (final value in errors.values) {
      if (value is List && value.isNotEmpty) return value.first.toString();
      if (value is String) return value;
    }
    return null;
  }

  Future<bool> _tryRefresh() async {
    final refresh = await refreshToken;
    if (refresh == null) return false;
    try {
      final uri = Uri.parse('$baseUrl/auth/refresh/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      );
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      await _storage.write(key: _accessKey, value: decoded['access'] as String);
      // ROTATE_REFRESH_TOKENS is on in settings.py, so a new refresh token
      // comes back too -- save it or the next refresh will fail.
      if (decoded['refresh'] != null) {
        await _storage.write(key: _refreshKey, value: decoded['refresh'] as String);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
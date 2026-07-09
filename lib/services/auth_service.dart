import 'api_client.dart';

/// Thin wrapper around the /api/v1/auth/ endpoints built in core/views.py.
/// Screens call these instead of talking to ApiClient directly, so the
/// request shape (what fields, what path) only needs to change in one place
/// if the backend contract changes.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _client = ApiClient.instance;

  /// POST /api/v1/auth/register/ -- creates the account only, does not log
  /// the user in. Matches RegisterView in core/views.py, which intentionally
  /// does not issue tokens itself.
  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? phone,
  }) async {
    await _client.post('/auth/register/', {
      'username': username,
      'email': email,
      'password': password,
      if (phone != null) 'phone': phone,
    });
  }

  /// POST /api/v1/auth/login/ -- simplejwt's TokenObtainPairView. On success
  /// stores both tokens via ApiClient so every future request can attach
  /// the access token automatically.
  Future<Map<String, dynamic>> login({required String username, required String password}) async {
    final data = await _client.post('/auth/login-identifier/', {
      'identifier': username,
      'password': password,
    });
    final loginData = Map<String, dynamic>.from(data as Map);
    await _client.saveTokens(
      access: loginData['access'] as String,
      refresh: loginData['refresh'] as String,
    );
    return loginData;
  }

  Future<void> logout() => _client.clearTokens();

  Future<bool> get isLoggedIn => _client.isLoggedIn;
}

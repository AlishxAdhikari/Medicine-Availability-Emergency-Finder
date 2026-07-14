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
  ///
  /// [username] must be a valid Django username (letters/digits/@/./+/-/_,
  /// no spaces) -- callers should generate one (e.g. from the email), not
  /// pass a raw display name. [fullName] is the person's actual name and is
  /// stored separately on the backend so it can be shown on any device.
  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? phone,
    String? fullName,
  }) async {
    await _client.post('/auth/register/', {
      'username': username,
      'email': email,
      'password': password,
      if (phone != null) 'phone': phone,
      if (fullName != null) 'full_name': fullName,
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

  /// Derives a Django-valid username (letters/digits/@/./+/-/_ only, no
  /// spaces) from an email address, since a person's full name -- which
  /// usually has spaces -- can never safely be sent as-is.
  ///
  /// Not guaranteed unique: two people signing up with the same
  /// email-local-part on different domains (e.g. jane@gmail.com and
  /// jane@yahoo.com) will collide, in which case registration will fail
  /// with a normal "username already exists" error from the backend.
  static String generateUsername(String email) {
    final localPart = email.contains('@') ? email.split('@').first : email;
    final sanitized = localPart.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.+_-]'), '');
    if (sanitized.isNotEmpty) return sanitized;
    // Fallback for an email with no usable characters before the @ --
    // practically shouldn't happen given the form's email validation.
    return 'user${DateTime.now().millisecondsSinceEpoch}';
  }
}
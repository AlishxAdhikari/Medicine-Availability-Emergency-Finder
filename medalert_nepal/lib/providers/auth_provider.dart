import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final String? errorMessage;
  final String? username;

  AuthState({
    this.isLoggedIn = false,
    this.isLoading = false,
    this.errorMessage,
    this.username,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    String? errorMessage,
    String? username,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage, // resets error if null not passed
      username: username ?? this.username,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState()) {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final loggedIn = await _authService.isLoggedIn();
      if (loggedIn) {
        state = AuthState(isLoggedIn: true, isLoading: false);
      } else {
        state = AuthState(isLoggedIn: false, isLoading: false);
      }
    } catch (_) {
      state = AuthState(isLoggedIn: false, isLoading: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final success = await _authService.login(username, password);
      if (success) {
        state = AuthState(isLoggedIn: true, isLoading: false, username: username);
        return true;
      } else {
        state = AuthState(isLoggedIn: false, isLoading: false, errorMessage: 'Invalid credentials');
        return false;
      }
    } catch (e) {
      state = AuthState(isLoggedIn: false, isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> register(String username, String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final success = await _authService.register(username, email, password);
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _authService.logout();
    state = AuthState(isLoggedIn: false, isLoading: false);
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final service = ref.watch(authServiceProvider);
  return AuthNotifier(service);
});

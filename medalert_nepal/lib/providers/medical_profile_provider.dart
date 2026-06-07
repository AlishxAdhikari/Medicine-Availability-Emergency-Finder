import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/auth_service.dart';
import '../models/medical_profile.dart';
import 'auth_provider.dart';

class MedicalProfileNotifier extends StateNotifier<AsyncValue<MedicalProfile>> {
  final AuthService _authService;
  late final Box _cacheBox;

  MedicalProfileNotifier(this._authService, Ref ref) : super(const AsyncValue.loading()) {
    // Watch auth status to reload profile when auth status changes
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isLoggedIn) {
        fetchProfile();
      } else {
        state = AsyncValue.data(MedicalProfile.empty());
      }
    });
    
    _initHiveAndLoad();
  }

  Future<void> _initHiveAndLoad() async {
    _cacheBox = await Hive.openBox('medical_profile_cache');
    final cachedData = _cacheBox.get('profile');
    if (cachedData != null) {
      final map = Map<String, dynamic>.from(cachedData as Map);
      state = AsyncValue.data(MedicalProfile.fromJson(map));
    } else {
      state = AsyncValue.data(MedicalProfile.empty());
    }
    
    // Attempt to fetch fresh from API if logged in
    final loggedIn = await _authService.isLoggedIn();
    if (loggedIn) {
      fetchProfile();
    }
  }

  Future<void> fetchProfile() async {
    state = const AsyncValue.loading();
    try {
      final profile = await _authService.getProfile();
      await _cacheBox.put('profile', profile.toJson());
      state = AsyncValue.data(profile);
    } catch (e, stack) {
      // If offline, we might fail. Keep cached data if available.
      if (state.hasValue) {
        state = AsyncValue.data(state.value!);
      } else {
        state = AsyncValue.error(e, stack);
      }
    }
  }

  Future<bool> updateProfile(MedicalProfile profile) async {
    final oldState = state;
    state = const AsyncValue.loading();
    try {
      final updated = await _authService.updateProfile(profile);
      await _cacheBox.put('profile', updated.toJson());
      state = AsyncValue.data(updated);
      return true;
    } catch (e) {
      state = oldState; // revert on failure
      return false;
    }
  }

  Future<void> updateLocalProfile(MedicalProfile profile) async {
    // Used when user is offline or not logged in - updates Hive and local state
    await _cacheBox.put('profile', profile.toJson());
    state = AsyncValue.data(profile);
  }
}

final medicalProfileProvider = StateNotifierProvider<MedicalProfileNotifier, AsyncValue<MedicalProfile>>((ref) {
  final service = ref.watch(authServiceProvider);
  return MedicalProfileNotifier(service, ref);
});

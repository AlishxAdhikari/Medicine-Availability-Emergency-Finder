import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class LocationState {
  final Position? position;
  final bool isLoading;
  final bool hasPermission;
  final String? errorMessage;

  LocationState({
    this.position,
    this.isLoading = false,
    this.hasPermission = false,
    this.errorMessage,
  });

  LocationState copyWith({
    Position? position,
    bool? isLoading,
    bool? hasPermission,
    String? errorMessage,
  }) {
    return LocationState(
      position: position ?? this.position,
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
      errorMessage: errorMessage,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final LocationService _locationService;

  LocationNotifier(this._locationService) : super(LocationState()) {
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    state = state.copyWith(isLoading: true);
    final hasPermission = await _locationService.hasPermission();
    state = state.copyWith(isLoading: false, hasPermission: hasPermission);
    
    if (hasPermission) {
      await getCurrentLocation();
    }
  }

  Future<void> getCurrentLocation() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        state = LocationState(
          position: position,
          isLoading: false,
          hasPermission: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Could not get location',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> requestPermission() async {
    state = state.copyWith(isLoading: true);
    final hasPermission = await _locationService.hasPermission();
    state = state.copyWith(isLoading: false, hasPermission: hasPermission);
    
    if (hasPermission) {
      await getCurrentLocation();
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final locationProvider = StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  final service = ref.watch(locationServiceProvider);
  return LocationNotifier(service);
});

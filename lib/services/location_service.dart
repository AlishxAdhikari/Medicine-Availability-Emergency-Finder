import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Where the app thinks the user is, and -- just as importantly -- whether
/// that is a real reading or a stand-in.
///
/// The two are kept in one object on purpose. Every screen here sorts results
/// by distance from this point, so a fallback silently passed off as a fix
/// produces a confidently wrong "1.2km away" for a pharmacy that is across the
/// country. Callers are expected to look at [isPrecise] and say so in the UI.
class UserLocation {
  const UserLocation({
    required this.latitude,
    required this.longitude,
    required this.isPrecise,
    this.status = LocationStatus.ok,
  });

  final double latitude;
  final double longitude;

  /// True only when these coordinates came from the device's location
  /// services. False means [LocationService.fallback] -- a city-centre guess.
  final bool isPrecise;

  /// Why the location is what it is, so the UI can offer the right remedy
  /// (turn on GPS vs. open app settings vs. nothing to fix).
  final LocationStatus status;
}

/// The outcomes worth telling the user apart. `denied` and `deniedForever`
/// are separate because only one of them can be fixed by asking again --
/// `deniedForever` needs a trip to the system settings, and re-prompting
/// silently no-ops.
enum LocationStatus {
  ok,
  servicesDisabled,
  denied,
  deniedForever,
  /// Location services answered, but not before [_timeout]. Common indoors.
  timedOut,
  unsupported,
}

extension LocationStatusMessage on LocationStatus {
  /// A short line for a banner. Null for [LocationStatus.ok] -- nothing to say
  /// when the location is real.
  String? get message {
    switch (this) {
      case LocationStatus.ok:
        return null;
      case LocationStatus.servicesDisabled:
        return 'Location is turned off. Showing results around Kathmandu instead.';
      case LocationStatus.denied:
        return 'Location permission denied. Showing results around Kathmandu instead.';
      case LocationStatus.deniedForever:
        return 'Location permission is blocked in system settings. '
            'Showing results around Kathmandu instead.';
      case LocationStatus.timedOut:
        return 'Could not get a location fix. Showing results around Kathmandu instead.';
      case LocationStatus.unsupported:
        return 'This device cannot report a location. Showing results around Kathmandu.';
    }
  }

  /// Whether re-running the permission request could plausibly change the
  /// answer. Drives whether the UI offers a "Try again" or a "Open settings".
  bool get isRetryable =>
      this == LocationStatus.servicesDisabled || this == LocationStatus.timedOut;
}

/// Real device GPS, with an explicit, labelled fallback.
///
/// Replaces the hardcoded Kathmandu constants that PharmacyService and
/// EmergencyService each used to carry. The fallback still exists -- a
/// distance-sorted search needs *some* origin, and refusing to search at all
/// when a user declines the permission would be worse than searching around
/// the capital -- but it is now one constant in one place, and it travels with
/// a flag saying it isn't real.
class LocationService {
  LocationService._internal();
  static final LocationService instance = LocationService._internal();

  /// Kathmandu city centre. Used when there is no usable fix. Never returned
  /// with `isPrecise: true`.
  static const UserLocation fallback = UserLocation(
    latitude: 27.7172,
    longitude: 85.3240,
    isPrecise: false,
  );

  /// A fix is worth reusing for this long. Pharmacy search re-runs on every
  /// keystroke-debounce and every radius drag; asking the GPS chip each time
  /// would add seconds of latency to a search the user expects to feel
  /// instant, for a position that has not meaningfully moved.
  static const Duration _cacheTtl = Duration(minutes: 2);

  /// Indoors, `getCurrentPosition` can hang until it gets a satellite lock.
  /// The search behind it is the whole screen, so it gets a bounded wait and
  /// then falls back rather than leaving a spinner up indefinitely.
  static const Duration _timeout = Duration(seconds: 10);

  UserLocation? _cached;
  DateTime? _cachedAt;

  /// In-flight request, so two widgets asking at once (the map and the list
  /// both build on the same frame) share one permission prompt and one fix
  /// instead of racing two.
  Future<UserLocation>? _pending;

  /// The user's current position, or the labelled [fallback] if one can't be
  /// obtained. Never throws and never returns null: callers are search
  /// screens that must render something.
  ///
  /// Set [forceRefresh] for an explicit user action ("recenter"), where
  /// handing back a two-minute-old cached point would look like the button
  /// did nothing.
  Future<UserLocation> current({bool forceRefresh = false}) {
    if (!forceRefresh) {
      final cached = _cached;
      final cachedAt = _cachedAt;
      if (cached != null &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt) < _cacheTtl) {
        return Future.value(cached);
      }
      final pending = _pending;
      if (pending != null) return pending;
    }

    final request = _resolve().then((location) {
      // Only a real reading is cached. Caching a fallback would pin the user
      // to Kathmandu for the next two minutes even after they granted the
      // permission and the very next call could have succeeded.
      if (location.isPrecise) {
        _cached = location;
        _cachedAt = DateTime.now();
      }
      return location;
    }).whenComplete(() => _pending = null);

    _pending = request;
    return request;
  }

  /// The last known real fix, if one is still fresh. Lets a widget draw
  /// immediately with what we already have instead of showing a spinner while
  /// [current] re-derives the same answer.
  UserLocation? get cachedOrNull {
    final cachedAt = _cachedAt;
    if (_cached == null || cachedAt == null) return null;
    return DateTime.now().difference(cachedAt) < _cacheTtl ? _cached : null;
  }

  Future<UserLocation> _resolve() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _fallbackWith(LocationStatus.servicesDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return _fallbackWith(LocationStatus.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return _fallbackWith(LocationStatus.denied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // `high`, not `best`: the results are sorted into 5-20km radii, so
          // the extra seconds `best` spends chasing the last few metres buy
          // nothing the user can see.
          accuracy: LocationAccuracy.high,
          timeLimit: _timeout,
        ),
      );

      return UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        isPrecise: true,
      );
    } on TimeoutException {
      return _fallbackWith(LocationStatus.timedOut);
    } on LocationServiceDisabledException {
      return _fallbackWith(LocationStatus.servicesDisabled);
    } on PermissionDefinitionsNotFoundException {
      // The platform manifest is missing the permission entries -- a build
      // configuration bug, not something the user can act on.
      return _fallbackWith(LocationStatus.unsupported);
    } catch (_) {
      // Unsupported platform, a plugin-side failure, a device with no
      // location hardware. None of these should take a search screen down;
      // it searches around the fallback and says so.
      return _fallbackWith(LocationStatus.unsupported);
    }
  }

  UserLocation _fallbackWith(LocationStatus status) => UserLocation(
        latitude: fallback.latitude,
        longitude: fallback.longitude,
        isPrecise: false,
        status: status,
      );

  /// Opens the OS settings page where a `deniedForever` permission can be
  /// un-blocked -- the only route back from that state, since re-requesting
  /// returns immediately without prompting.
  Future<bool> openPermissionSettings() => Geolocator.openAppSettings();

  /// Opens the OS location-services toggle, for [LocationStatus.servicesDisabled].
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Straight-line distance in kilometres. Used for labelling rows the backend
  /// didn't annotate with a `distance_km` (ambulance providers have no
  /// coordinates, blood banks do).
  double distanceKmTo(UserLocation from, double lat, double lng) =>
      Geolocator.distanceBetween(from.latitude, from.longitude, lat, lng) / 1000;

  /// Test seam: drops the cache so a test (or a sign-out) doesn't inherit the
  /// previous session's position.
  void reset() {
    _cached = null;
    _cachedAt = null;
    _pending = null;
  }
}

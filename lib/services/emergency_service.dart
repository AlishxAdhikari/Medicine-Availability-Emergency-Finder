import '../state.dart' as app_state;
import 'api_client.dart';
import 'location_service.dart';

/// Wraps the /api/v1/blood-banks/ and /api/v1/ambulances/ endpoints built
/// in emergency/views.py, and maps the JSON response into the UI's
/// existing BloodBank/Ambulance models (state.dart), same pattern as
/// PharmacyService for pharmacy/views.py.
class EmergencyService {
  EmergencyService._internal();
  static final EmergencyService instance = EmergencyService._internal();

  final _client = ApiClient.instance;

  /// [origin] is the point the results are distance-sorted around. Omitted, it
  /// is resolved from the device via LocationService (same contract as
  /// PharmacyService.search -- real fix when there is one, a labelled
  /// Kathmandu fallback when there isn't).
  Future<List<app_state.BloodBank>> searchBloodBanks({
    String? district,
    String? bloodGroup,
    UserLocation? origin,
  }) async {
    final location = origin ?? await LocationService.instance.current();
    final params = <String, dynamic>{
      if (district != null && district.isNotEmpty) 'district': district,
      if (bloodGroup != null && bloodGroup.isNotEmpty) 'blood_group': bloodGroup,
      'lat': location.latitude,
      'lng': location.longitude,
    };

    final results = await _fetchAllPages('/blood-banks/', params);
    return results.map(_toBloodBank).toList();
  }

  /// The districts that actually have rows, so the UI's district filter can't
  /// drift out of sync with the data (a hardcoded list silently hides any
  /// district the backend knows about but the list doesn't mention).
  ///
  /// The district list is a refinement of the filter, not the screen's
  /// payload, so it must never be able to take the ambulance/blood-bank lists
  /// (or the SOS button) down with it: an app build running against a backend
  /// that predates these endpoints gets a 404, and either call can fail on its
  /// own transiently. Each failure degrades to "no districts from this
  /// endpoint" and the caller falls back to its own list when nothing at all
  /// comes back.
  ///
  /// [complete] is false when either endpoint failed, because the union alone
  /// can't tell a whole answer from half of one: if /ambulances/districts/
  /// answers and /blood-banks/districts/ 404s, the result is non-empty and
  /// looks authoritative while silently omitting every blood-bank-only
  /// district -- the exact failure these endpoints exist to prevent. Callers
  /// may still show an incomplete list (some real districts beat none), but
  /// must not treat it as settled.
  Future<({List<String> districts, bool complete})> fetchDistricts() async {
    final results = await Future.wait([
      _districtsFrom('/ambulances/districts/'),
      _districtsFrom('/blood-banks/districts/'),
    ]);
    final districts = <String>{for (final list in results) ...?list}.toList();
    districts.sort();
    return (districts: districts, complete: !results.contains(null));
  }

  /// Null means this endpoint failed, as distinct from an empty list, which
  /// means it answered and has no districts of its own.
  Future<List<String>?> _districtsFrom(String path) async {
    try {
      final list = await _client.get(path);
      // List.from, not .cast(): cast() checks elements lazily on iteration, so
      // a malformed payload (a null or a number among the districts) would
      // throw at the caller's fold instead of here, escaping this catch and
      // taking the whole screen down with it.
      return List<String>.from(list as List);
    } catch (_) {
      return null;
    }
  }

  Future<List<app_state.Ambulance>> searchAmbulances({
    String? district,
    bool? has24Hour,
    bool? hasIcu,
    bool? hasOxygen,
  }) async {
    final params = <String, dynamic>{
      if (district != null && district.isNotEmpty) 'district': district,
      'is_24_hour': ?has24Hour,
      'has_icu': ?hasIcu,
      'has_oxygen': ?hasOxygen,
    };

    final results = await _fetchAllPages('/ambulances/', params);
    return results.map(_toAmbulance).toList();
  }

  // Both endpoints are paginated (PAGE_SIZE 20 in settings.py), and callers
  // here want a whole list, not a page -- reading only 'results' of page 1
  // silently drops everything past row 20. Follows 'next' by page number
  // (ApiClient builds URLs from a path + query, so the absolute 'next' URL
  // isn't usable directly), capped so a paging bug can't loop forever.
  //
  // The cap is a runaway guard, not a supported limit: hitting it while the
  // server still reports a next page means either that bug or a dataset this
  // client can no longer read whole. Returning the truncated list there would
  // reintroduce exactly the silent data loss this paging exists to fix --
  // partial results that look complete -- so it throws instead and the screen
  // shows its error state. Raising the ceiling properly means paging less
  // often, i.e. giving the backend a page_size query param (DRF ignores one
  // unless PAGE_SIZE_QUERY_PARAM is set, which settings.py doesn't set).
  static const int _maxPages = 25;

  Future<List<Map<String, dynamic>>> _fetchAllPages(
    String path,
    Map<String, dynamic> params,
  ) async {
    final all = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final data = await _client.get(
        path,
        query: {...params, if (page > 1) 'page': page},
      );
      all.addAll((data['results'] as List).cast<Map<String, dynamic>>());
      if (data['next'] == null) return all;
    }
    throw StateError(
      'Paged past $_maxPages pages of $path and the server still reports more '
      'results; refusing to return a truncated list.',
    );
  }

  app_state.BloodBank _toBloodBank(Map<String, dynamic> json) {
    final distanceKm = json['distance_km'];
    final stockList = (json['stock'] as List).cast<Map<String, dynamic>>();

    return app_state.BloodBank(
      name: json['name'] as String,
      location: json['district'] as String,
      distance: distanceKm != null ? '${distanceKm}km' : '',
      availability: stockList.map((s) {
        return app_state.BloodStock(
          type: s['blood_group'] as String,
          status: _levelToStatus(s['level'] as String),
        );
      }).toList(),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      phone: json['phone'] as String? ?? '',
    );
  }

  /// See PharmacyService._toDouble -- whole-numbered coordinates come back as
  /// int from JSON, and a hard `as double` cast would throw on them.
  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  app_state.Ambulance _toAmbulance(Map<String, dynamic> json) {
    // No lat/lng on AmbulanceProvider (matches the spec -- these are matched
    // by district, not exact coordinates), so there is no distance to show
    // and the card names the service type as a service type.
    final serviceType = json['service_type'] as String;
    final label = serviceType.isNotEmpty
        ? serviceType[0].toUpperCase() + serviceType.substring(1)
        : '';

    return app_state.Ambulance(
      name: json['name'] as String,
      location: json['district'] as String,
      serviceType: label,
      // Required (not blank=True) on AmbulanceProvider, so this should always
      // be present -- defaulted anyway so a serializer change can't crash the
      // screen, and the Call button reports "no number on file" instead.
      phone: json['phone'] as String? ?? '',
      // The backend has no real-time "available now" status, so the UI says
      // what this genuinely is -- a 24-hour line or not -- rather than
      // dressing it up as live availability.
      isOpen24Hours: json['is_24_hour'] as bool,
    );
  }

  // Backend uses adequate/low/critical/unavailable; the existing UI only
  // has special colors for CRITICAL and LOW (see emergency_screen.dart),
  // everything else renders as the "normal/ok" color -- so unavailable is
  // mapped to CRITICAL rather than falling through to a false-reassuring
  // green.
  String _levelToStatus(String level) {
    switch (level) {
      case 'low':
        return 'LOW';
      case 'critical':
        return 'CRITICAL';
      case 'unavailable':
        return 'CRITICAL';
      default:
        return 'NORMAL';
    }
  }
}
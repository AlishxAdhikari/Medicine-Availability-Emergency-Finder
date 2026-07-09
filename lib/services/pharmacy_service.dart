import '../state.dart' as app_state;
import 'api_client.dart';

/// Wraps the /api/v1/pharmacies/ and /api/v1/medicines/ endpoints built in
/// pharmacy/views.py, and maps the JSON response into the UI's existing
/// Pharmacy model (state.dart) so the screen layer doesn't need to change
/// its widget code, only where the data comes from.
class PharmacyService {
  PharmacyService._internal();
  static final PharmacyService instance = PharmacyService._internal();

  final _client = ApiClient.instance;

  // Placeholder "current location" until GPS is wired in (the geolocator
  // package isn't in pubspec.yaml yet). Kathmandu city centre -- swap this
  // for a real position once location permissions are added.
  static const double _fallbackLat = 27.7172;
  static const double _fallbackLng = 85.3240;

  /// Searches pharmacies by name/address/district/medicine name, sorted by
  /// distance from [lat]/[lng] (defaults to the Kathmandu placeholder).
  /// For each pharmacy returned, also fetches its stock list so the search
  /// screen can show which medicines are in stock -- capped by the search
  /// endpoint's own page size (20), so this stays a small number of calls.
  Future<List<app_state.Pharmacy>> search({
    String query = '',
    double? lat,
    double? lng,
    double? radiusKm,
  }) async {
    final params = <String, dynamic>{
      if (query.isNotEmpty) 'search': query,
      'lat': lat ?? _fallbackLat,
      'lng': lng ?? _fallbackLng,
      if (radiusKm != null) 'radius_km': radiusKm,
    };

    final data = await _client.get('/pharmacies/', query: params);
    final results = (data['results'] as List).cast<Map<String, dynamic>>();

    // Fetch each pharmacy's stock in parallel rather than one-by-one --
    // this is a search-results page (max ~20 rows), not a bulk export, so
    // N parallel requests is fine; it would need rethinking at larger scale.
    final pharmacies = await Future.wait(results.map((json) => _toPharmacy(json)));
    return pharmacies;
  }

  Future<app_state.Pharmacy> _toPharmacy(Map<String, dynamic> json) async {
    List<Map<String, dynamic>> items = [];
    try {
      final stock = await _client.get('/pharmacies/${json['id']}/stock/') as List;
      items = stock
          .cast<Map<String, dynamic>>()
          .take(6) // enough to show a few stock chips without cluttering the card
          .map((row) => {
                'name': row['medicine']['name'],
                'inStock': (row['quantity'] as num) > 0,
              })
          .toList();
    } catch (_) {
      // Stock lookup failing shouldn't hide the pharmacy itself from
      // results -- just show it with an empty stock list.
    }

    final distanceKm = json['distance_km'];
    return app_state.Pharmacy(
      name: json['name'] as String,
      distance: distanceKm != null ? '${distanceKm}km' : json['district'] as String,
      address: json['address'] as String,
      isOpen: json['is_24_hour'] as bool,
      items: items,
    );
  }
}

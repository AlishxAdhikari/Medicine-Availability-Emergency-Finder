import '../state.dart' as app_state;
import 'api_client.dart';
import 'location_service.dart';

/// Wraps the /api/v1/pharmacies/ and /api/v1/medicines/ endpoints built in
/// pharmacy/views.py, and maps the JSON response into the UI's existing
/// Pharmacy model (state.dart) so the screen layer doesn't need to change
/// its widget code, only where the data comes from.
class PharmacyService {
  PharmacyService._internal();
  static final PharmacyService instance = PharmacyService._internal();

  final _client = ApiClient.instance;

  /// Searches pharmacies by name/address/district/medicine name, sorted by
  /// distance from [origin]. When [origin] is omitted the device's real
  /// position is resolved via LocationService, which falls back to a labelled
  /// Kathmandu city-centre point if there is no usable fix -- the search still
  /// needs an origin to sort around, but callers can see from
  /// `UserLocation.isPrecise` that the distances are nominal and say so.
  ///
  /// Screens generally pass [origin] explicitly, because they need the same
  /// location for the map and the "location is off" banner and shouldn't have
  /// to resolve it twice.
  ///
  /// For each pharmacy returned, also fetches its stock list so the search
  /// screen can show which medicines are in stock -- capped by the search
  /// endpoint's own page size (20), so this stays a small number of calls.
  Future<List<app_state.Pharmacy>> search({
    String query = '',
    UserLocation? origin,
    double? radiusKm,
  }) async {
    final location = origin ?? await LocationService.instance.current();
    final params = <String, dynamic>{
      if (query.isNotEmpty) 'search': query,
      'lat': location.latitude,
      'lng': location.longitude,
      'radius_km': ?radiusKm,
    };

    final data = await _client.get('/pharmacies/', query: params);
    final results = (data['results'] as List).cast<Map<String, dynamic>>();

    // Fetch each pharmacy's stock in parallel rather than one-by-one --
    // this is a search-results page (max ~20 rows), not a bulk export, so
    // N parallel requests is fine; it would need rethinking at larger scale.
    final pharmacies = await Future.wait(results.map((json) => _toPharmacy(json)));
    return pharmacies;
  }

  /// GET /api/v1/medicines/?search= -- the catalog the owner picks from when
  /// adding a medicine their pharmacy doesn't stock yet.
  ///
  /// Reads `['results']` because MedicineViewSet is a ReadOnlyModelViewSet
  /// (pharmacy/views.py:15), so it goes through GenericAPIView and DOES pick
  /// up REST_FRAMEWORK's DEFAULT_PAGINATION_CLASS / PAGE_SIZE 20. That is the
  /// opposite of /my-pharmacy/stock/, whose bare ViewSet returns a naked list
  /// -- do not copy this shape across to that one.
  ///
  /// Only page one is read. That is deliberate and safe here in a way it is
  /// not for the owner's own stock: this backs a type-ahead picker where the
  /// user narrows the query until the medicine they want is visible, so 20
  /// candidates is a UI cap, not silent data loss.
  Future<List<Map<String, dynamic>>> searchMedicines(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final data = await _client.get('/medicines/', query: {'search': q});
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    if (data is Map && data['results'] is List) {
      return (data['results'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Resolve a catalog medicine by free-text name (exact → contains → first word).
  /// Returns null if nothing plausible is found.
  Future<Map<String, dynamic>?> resolveMedicine(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return null;

    Future<List<Map<String, dynamic>>> trySearch(String q) async {
      try {
        return await searchMedicines(q);
      } catch (_) {
        return [];
      }
    }

    // 1) Full name
    var found = await trySearch(name);
    // 2) Without strength / dosage tokens (e.g. "Amoxicillin 250mg" → "Amoxicillin")
    if (found.isEmpty) {
      final stripped = name
          .replaceAll(RegExp(r'\b\d+([./]\d+)?\s*(mg|mcg|g|ml|iu|%)\b', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (stripped.isNotEmpty && stripped.toLowerCase() != name.toLowerCase()) {
        found = await trySearch(stripped);
      }
    }
    // 3) First word only
    if (found.isEmpty) {
      final first = name.split(RegExp(r'\s+')).first;
      if (first.length >= 3) found = await trySearch(first);
    }
    if (found.isEmpty) return null;

    final lower = name.toLowerCase();
    // Prefer exact name match
    for (final m in found) {
      final n = (m['name'] as String? ?? '').toLowerCase();
      if (n == lower) return m;
    }
    // Prefer name that contains the query or vice-versa
    for (final m in found) {
      final n = (m['name'] as String? ?? '').toLowerCase();
      if (n.contains(lower) || lower.contains(n)) return m;
    }
    return found.first;
  }

  Future<app_state.Pharmacy> _toPharmacy(Map<String, dynamic> json) async {
    List<Map<String, dynamic>> items = [];
    try {
      final stock = await _client.get('/pharmacies/${json['id']}/stock/') as List;
      items = stock
          .cast<Map<String, dynamic>>()
          .take(6) // enough to show a few stock chips without cluttering the card
          // `quantity` and `lowThreshold` are carried alongside `inStock`
          // rather than replacing it, because the search screen can render
          // either shape (see StockDisplayMode) and the map/filter code still
          // asks the cheap boolean question. Both are kept in sync by
          // applyStockLevel() in state.dart -- update them together or a live
          // push will leave the chip's colour disagreeing with its number.
          .map((row) => {
                'name': row['medicine']['name'],
                'quantity': (row['quantity'] as num).toInt(),
                'lowThreshold': (row['low_threshold'] as num?)?.toInt() ?? 0,
                'inStock': (row['quantity'] as num) > 0,
              })
          .toList();
    } catch (_) {
      // Stock lookup failing shouldn't hide the pharmacy itself from
      // results -- just show it with an empty stock list.
    }

    final distanceKm = json['distance_km'];
    return app_state.Pharmacy(
      id: json['id'] as int,
      name: json['name'] as String,
      distance: distanceKm != null ? '${distanceKm}km' : json['district'] as String,
      address: json['address'] as String,
      isOpen: json['is_24_hour'] as bool,
      items: items,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      phone: json['phone'] as String? ?? '',
    );
  }

  /// JSON numbers arrive as int when the stored value happens to be whole
  /// (a pharmacy sitting on exactly 27.0), and `as double` would throw on
  /// those. Returns null for anything unparseable so a bad row loses its map
  /// pin rather than the whole result list.
  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
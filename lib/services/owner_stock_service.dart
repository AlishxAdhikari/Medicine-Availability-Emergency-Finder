import 'api_client.dart';

/// One row of the owner's own stock, as returned by OwnerStockSerializer
/// in pharmacy/serializers.py.
class OwnerStock {
  final int id;
  final int medicineId;
  final String medicineName;
  final int quantity;
  final String price;

  /// The quantity at or below which the backend pushes a low-stock alert
  /// (sync/signals.py's check_threshold). Read strictly, not defaulted like
  /// [price]: this one is editable, and inventing a value the server did not
  /// send would let the owner PATCH a threshold back onto the row that they
  /// never actually chose.
  final int lowThreshold;

  OwnerStock({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.price,
    required this.lowThreshold,
  });

  factory OwnerStock.fromJson(Map<String, dynamic> json) {
    final medicine = Map<String, dynamic>.from(json['medicine'] as Map);
    return OwnerStock(
      id: json['id'] as int,
      medicineId: medicine['id'] as int,
      medicineName: medicine['name'] as String,
      quantity: json['quantity'] as int,
      lowThreshold: json['low_threshold'] as int,
      // DRF renders DecimalField as a string. The server cannot actually omit
      // this key or send null -- PharmacyMedicineStock.price is a non-nullable
      // DecimalField with no model default, and apply_stock_change() creates
      // rows with defaults={'price': 0.0}, which serialises as "0.00", not as
      // an absent key. The fallback is pure defensiveness against a future
      // serializer change; it is unreachable against today's backend.
      price: json['price']?.toString() ?? '0',
    );
  }
}

/// Decodes whatever the stock list endpoint sent back.
///
/// Today the payload is a bare JSON list: OwnerStockViewSet is a plain
/// `viewsets.ViewSet` whose `list()` hand-serializes the queryset, and a bare
/// ViewSet never applies REST_FRAMEWORK's DEFAULT_PAGINATION_CLASS (that is
/// GenericAPIView machinery). But the project-wide default IS
/// PageNumberPagination with PAGE_SIZE 20, so the day someone promotes this to
/// a ModelViewSet -- the obvious refactor -- the response silently becomes
/// `{count, next, previous, results}` and a plain `data as List` would throw a
/// cast error in the user's face. Reading both shapes is drift insurance.
///
/// This is NOT pagination support, and it deliberately does not become it by
/// accident: a wrapper whose `next` is non-null means the server is holding
/// rows this client did not read, so it throws instead of returning page one.
/// Returning those rows would reintroduce exactly the silent data loss that
/// commit b30fd41 ("Fix emergency districts disappearing behind API
/// pagination") fixed -- partial results that look complete. Concretely, an
/// owner whose 25th medicine is invisible on the dashboard would try to re-add
/// it and get a contradictory 400 "This pharmacy already stocks that medicine."
/// Same reasoning as EmergencyService._fetchAllPages, which refuses to return a
/// truncated list for the same reason.
///
/// Following `next` is a real design decision (page in the dashboard, or cap
/// the endpoint), not something to invent as a side effect. If that refactor
/// happens, fix paging deliberately rather than leaning on this.
List<OwnerStock> parseStockPayload(dynamic data) {
  if (data is Map && data['next'] != null) {
    throw StateError(
      '/my-pharmacy/stock/ returned a paginated response and the server still '
      'reports more results (next: ${data['next']}); this client does not '
      'follow pages, so it is refusing to return a truncated list.',
    );
  }
  final rows = switch (data) {
    List() => data,
    {'results': final List results} => results,
    _ => throw FormatException(
        'Unexpected /my-pharmacy/stock/ payload: ${data.runtimeType}',
      ),
  };
  return rows
      .map((row) => OwnerStock.fromJson(Map<String, dynamic>.from(row as Map)))
      .toList();
}

/// Wraps /api/v1/my-pharmacy/stock/ -- the owner-only write API built in
/// pharmacy/owner_views.py. Every call is authenticated; the backend
/// resolves which pharmacy from the token, so no pharmacy id is ever sent.
class OwnerStockService {
  OwnerStockService._internal();
  static final OwnerStockService instance = OwnerStockService._internal();

  final _client = ApiClient.instance;

  Future<List<OwnerStock>> fetchStock() async {
    final data = await _client.get('/my-pharmacy/stock/', auth: true);
    return parseStockPayload(data);
  }

  /// Sends the absolute count the owner sees on the shelf. The server
  /// derives the delta inside a row lock -- see apply_stock_change().
  Future<OwnerStock> setQuantity(int stockId, int quantity) async {
    final data = await _client.patch(
      '/my-pharmacy/stock/$stockId/', {'quantity': quantity}, auth: true,
    );
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<OwnerStock> setPrice(int stockId, String price) async {
    final data = await _client.patch(
      '/my-pharmacy/stock/$stockId/', {'price': price}, auth: true,
    );
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Sets the level at which this medicine starts raising low-stock alerts.
  /// Sent on its own rather than folded into setQuantity, so the owner can
  /// retune the alert without the server writing a stock adjustment for it.
  Future<OwnerStock> setLowThreshold(int stockId, int threshold) async {
    final data = await _client.patch(
      '/my-pharmacy/stock/$stockId/', {'low_threshold': threshold}, auth: true,
    );
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<OwnerStock> addMedicine({
    required int medicineId,
    required int quantity,
    required String price,
    int? lowThreshold,
  }) async {
    final data = await _client.post('/my-pharmacy/stock/', {
      'medicine': medicineId,
      'quantity': quantity,
      'price': price,
      // Omitted rather than guessed when the owner leaves it blank, so the
      // server's own default (10) stays the single source of that number.
      'low_threshold': ?lowThreshold,
    }, auth: true);
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> removeStock(int stockId) async {
    await _client.delete('/my-pharmacy/stock/$stockId/', auth: true);
  }
}

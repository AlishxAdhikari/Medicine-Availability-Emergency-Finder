import 'api_client.dart';

/// One row of the owner's own stock, as returned by OwnerStockSerializer
/// in pharmacy/serializers.py.
class OwnerStock {
  final int id;
  final int medicineId;
  final String medicineName;
  final int quantity;
  final String price;

  OwnerStock({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.price,
  });

  factory OwnerStock.fromJson(Map<String, dynamic> json) {
    final medicine = Map<String, dynamic>.from(json['medicine'] as Map);
    return OwnerStock(
      id: json['id'] as int,
      medicineId: medicine['id'] as int,
      medicineName: medicine['name'] as String,
      quantity: json['quantity'] as int,
      // DRF renders DecimalField as a string; a row the POS created defaults
      // to 0.0, so don't assume the key is always present.
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
/// This is NOT pagination support: a genuinely paginated response with a
/// non-null `next` would still be truncated to its first page here. Following
/// `next` is a real design decision (page in the dashboard, or cap the
/// endpoint), not something to invent as a side effect -- and silently
/// truncating a list is exactly the repo's most recent bug, commit b30fd41,
/// "Fix emergency districts disappearing behind API pagination". If that
/// refactor happens, fix paging deliberately rather than leaning on this.
List<OwnerStock> parseStockPayload(dynamic data) {
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

  Future<OwnerStock> addMedicine({
    required int medicineId,
    required int quantity,
    required String price,
  }) async {
    final data = await _client.post('/my-pharmacy/stock/', {
      'medicine': medicineId,
      'quantity': quantity,
      'price': price,
    }, auth: true);
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> removeStock(int stockId) async {
    await _client.delete('/my-pharmacy/stock/$stockId/', auth: true);
  }
}

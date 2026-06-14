import 'api_client.dart';
import '../models/medicine.dart';

class MedicineService {
  final _client = ApiClient();

  Future<List<Medicine>> getMedicines({
    String? search,
    int? categoryId,
    bool? isEssential,
    double? lat,
    double? lon,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (categoryId != null) {
        queryParams['category'] = categoryId;
      }
      if (isEssential != null) {
        queryParams['is_essential'] = isEssential;
      }
      if (lat != null && lon != null) {
        queryParams['lat'] = lat;
        queryParams['lon'] = lon;
      }

      final response = await _client.dio.get('/medicines/', queryParameters: queryParams);

      List dataList;
      if (response.data is Map && response.data.containsKey('results')) {
        dataList = response.data['results'] as List;
      } else if (response.data is List) {
        dataList = response.data as List;
      } else {
        dataList = [];
      }

      return dataList.map((json) => Medicine.fromJson(json as Map<String, dynamic>)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load medicines catalog: $e');
    }
  }

  Future<List<MedicineCategory>> getCategories() async {
    try {
      final response = await _client.dio.get('/medicines/categories/');
      List dataList;
      if (response.data is Map && response.data.containsKey('results')) {
        dataList = response.data['results'] as List;
      } else if (response.data is List) {
        dataList = response.data as List;
      } else {
        dataList = [];
      }
      return dataList.map((json) => MedicineCategory.fromJson(json as Map<String, dynamic>)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load categories: $e');
    }
  }

  Future<List<PharmacyMedicineStock>> getMedicineAvailability(int medicineId) async {
    try {
      final response = await _client.dio.get('/pharmacies/stocks/', queryParameters: {
        'medicine': medicineId,
      });

      List dataList;
      if (response.data is Map && response.data.containsKey('results')) {
        dataList = response.data['results'] as List;
      } else if (response.data is List) {
        dataList = response.data as List;
      } else {
        dataList = [];
      }

      return dataList.map((json) => PharmacyMedicineStock.fromJson(json as Map<String, dynamic>)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load medicine availability: $e');
    }
  }
}

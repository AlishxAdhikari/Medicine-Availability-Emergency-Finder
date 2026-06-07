import 'api_client.dart';
import '../models/pharmacy.dart';
import '../models/medicine.dart';

class PharmacyService {
  final _client = ApiClient();

  Future<List<Pharmacy>> getPharmacies({
    String? search,
    String? district,
    double? lat,
    double? lon,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (district != null && district != 'All' && district.isNotEmpty) {
        queryParams['district'] = district;
      }
      if (lat != null && lon != null) {
        queryParams['lat'] = lat;
        queryParams['lon'] = lon;
      }

      final response = await _client.dio.get('/pharmacies/', queryParameters: queryParams);
      
      // DRF might return paginated results (results list) or plain list
      List dataList;
      if (response.data is Map && response.data.containsKey('results')) {
        dataList = response.data['results'] as List;
      } else if (response.data is List) {
        dataList = response.data as List;
      } else {
        dataList = [];
      }

      return dataList.map((json) => Pharmacy.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      throw Exception('Failed to load pharmacies: $e');
    }
  }

  Future<Pharmacy> getPharmacy(int id) async {
    try {
      final response = await _client.dio.get('/pharmacies/$id/');
      return Pharmacy.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to load pharmacy details: $e');
    }
  }

  Future<List<PharmacyMedicineStock>> getPharmacyStock(int pharmacyId) async {
    try {
      final response = await _client.dio.get('/pharmacies/stocks/', queryParameters: {
        'pharmacy': pharmacyId,
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
    } catch (e) {
      throw Exception('Failed to load pharmacy stock: $e');
    }
  }
}

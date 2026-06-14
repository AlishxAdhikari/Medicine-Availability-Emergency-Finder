import 'api_client.dart';
import '../models/ambulance.dart';

class AmbulanceService {
  final _client = ApiClient();



  Future<List<AmbulanceProvider>> getAmbulanceProviders({
    String? search,
    String? serviceType,
    String? district,
    bool? hasIcu,
    bool? hasOxygen,
    double? lat,
    double? lon,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (serviceType != null && serviceType != 'All' && serviceType.isNotEmpty) {
        queryParams['service_type'] = serviceType.toLowerCase();
      }
      if (district != null && district != 'All' && district.isNotEmpty) {
        queryParams['district'] = district;
      }
      if (hasIcu != null && hasIcu) queryParams['has_icu'] = true;
      if (hasOxygen != null && hasOxygen) queryParams['has_oxygen'] = true;
      if (lat != null && lon != null) {
        queryParams['lat'] = lat;
        queryParams['lon'] = lon;
      }

      final response = await _client.dio.get('/ambulances/', queryParameters: queryParams);

      List dataList;
      if (response.data is Map && response.data.containsKey('results')) {
        dataList = response.data['results'] as List;
      } else if (response.data is List) {
        dataList = response.data as List;
      } else {
        dataList = [];
      }

      return dataList.map((json) => AmbulanceProvider.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      throw Exception('Failed to load ambulance providers: $e');
    }
  }
}

import '../state.dart' as app_state;
import 'api_client.dart';

/// Wraps the /api/v1/blood-banks/ and /api/v1/ambulances/ endpoints built
/// in emergency/views.py, and maps the JSON response into the UI's
/// existing BloodBank/Ambulance models (state.dart), same pattern as
/// PharmacyService for pharmacy/views.py.
class EmergencyService {
  EmergencyService._internal();
  static final EmergencyService instance = EmergencyService._internal();

  final _client = ApiClient.instance;

  // Same placeholder-location approach as PharmacyService, until real GPS
  // is wired in.
  static const double _fallbackLat = 27.7172;
  static const double _fallbackLng = 85.3240;

  Future<List<app_state.BloodBank>> searchBloodBanks({
    String? district,
    String? bloodGroup,
    double? lat,
    double? lng,
  }) async {
    final params = <String, dynamic>{
      if (district != null && district.isNotEmpty) 'district': district,
      if (bloodGroup != null && bloodGroup.isNotEmpty) 'blood_group': bloodGroup,
      'lat': lat ?? _fallbackLat,
      'lng': lng ?? _fallbackLng,
    };

    final data = await _client.get('/blood-banks/', query: params);
    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    return results.map(_toBloodBank).toList();
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

    final data = await _client.get('/ambulances/', query: params);
    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    return results.map(_toAmbulance).toList();
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
    );
  }

  app_state.Ambulance _toAmbulance(Map<String, dynamic> json) {
    // No lat/lng on AmbulanceProvider (matches the spec -- these are
    // matched by district, not exact coordinates), so the "distance" slot
    // shows the service type instead of a real distance.
    final serviceType = json['service_type'] as String;
    final label = serviceType.isNotEmpty
        ? serviceType[0].toUpperCase() + serviceType.substring(1)
        : '';

    return app_state.Ambulance(
      name: json['name'] as String,
      location: json['district'] as String,
      distance: label,
      // PLACEHOLDER: there's no real-time "available now" field on the
      // backend yet, so this approximates availability with is_24_hour.
      // Revisit if/when the backend gets a real availability status.
      isAvailable: json['is_24_hour'] as bool,
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
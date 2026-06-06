class Ambulance {
  final String hospitalName;
  final String contactNumber;
  final double distanceInKm; // Calculated on the fly using user GPS
  final double latitude;
  final double longitude;

  Ambulance({
    required this.hospitalName,
    required this.contactNumber,
    required this.distanceInKm,
    required this.latitude,
    required this.longitude,
  });

  // Factory constructor to easily parse JSON incoming from your Django REST API
  factory Ambulance.fromJson(Map<String, dynamic> json, double userLat, double userLng) {
    // You will implement the distance formula logic here later
    return Ambulance(
      hospitalName: json['hospital_name'],
      contactNumber: json['contact_number'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      distanceInKm: 0.0, // Placeholder for the calculation logic
    );
  }
}
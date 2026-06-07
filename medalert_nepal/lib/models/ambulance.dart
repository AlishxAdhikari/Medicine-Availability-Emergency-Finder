class AmbulanceProvider {
  final int id;
  final String hospitalName;
  final String serviceType; // government, private, ngo
  final String contactNumber;
  final String? contactAlt;
  final String address;
  final String district;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final bool is24h;
  final bool hasIcu;
  final bool hasOxygen;
  final String notes;

  AmbulanceProvider({
    required this.id,
    required this.hospitalName,
    required this.serviceType,
    required this.contactNumber,
    this.contactAlt,
    required this.address,
    required this.district,
    this.latitude,
    this.longitude,
    required this.isActive,
    required this.is24h,
    required this.hasIcu,
    required this.hasOxygen,
    required this.notes,
  });

  factory AmbulanceProvider.fromJson(Map<String, dynamic> json) {
    return AmbulanceProvider(
      id: json['id'] as int,
      hospitalName: json['hospital_name'] as String,
      serviceType: json['service_type'] as String? ?? 'government',
      contactNumber: json['contact_number'] as String? ?? '',
      contactAlt: json['contact_alt'] as String?,
      address: json['address'] as String? ?? '',
      district: json['district'] as String? ?? '',
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
      isActive: json['is_active'] as bool? ?? true,
      is24h: json['is_24h'] as bool? ?? true,
      hasIcu: json['has_icu'] as bool? ?? false,
      hasOxygen: json['has_oxygen'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hospital_name': hospitalName,
      'service_type': serviceType,
      'contact_number': contactNumber,
      'contact_alt': contactAlt,
      'address': address,
      'district': district,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive,
      'is_24h': is24h,
      'has_icu': hasIcu,
      'has_oxygen': hasOxygen,
      'notes': notes,
    };
  }
}
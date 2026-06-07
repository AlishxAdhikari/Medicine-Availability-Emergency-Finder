class Pharmacy {
  final int id;
  final String name;
  final String slug;
  final String address;
  final String district;
  final String phone;
  final String? phoneAlt;
  final String? email;
  final double? latitude;
  final double? longitude;
  final bool is24h;
  final String? opensAt;
  final String? closesAt;
  final bool isActive;
  final String verificationStatus;

  Pharmacy({
    required this.id,
    required this.name,
    required this.slug,
    required this.address,
    required this.district,
    required this.phone,
    this.phoneAlt,
    this.email,
    this.latitude,
    this.longitude,
    required this.is24h,
    this.opensAt,
    this.closesAt,
    required this.isActive,
    required this.verificationStatus,
  });

  factory Pharmacy.fromJson(Map<String, dynamic> json) {
    return Pharmacy(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      address: json['address'] as String,
      district: json['district'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      phoneAlt: json['phone_alt'] as String?,
      email: json['email'] as String?,
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
      is24h: json['is_24h'] as bool? ?? false,
      opensAt: json['opens_at'] as String?,
      closesAt: json['closes_at'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      verificationStatus: json['verification_status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'address': address,
      'district': district,
      'phone': phone,
      'phone_alt': phoneAlt,
      'email': email,
      'latitude': latitude,
      'longitude': longitude,
      'is_24h': is24h,
      'opens_at': opensAt,
      'closes_at': closesAt,
      'is_active': isActive,
      'verification_status': verificationStatus,
    };
  }
}

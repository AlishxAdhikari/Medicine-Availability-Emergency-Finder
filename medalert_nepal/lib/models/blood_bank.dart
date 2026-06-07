class BloodStock {
  final int id;
  final String bloodGroup;
  final String stockLevel; // adequate, low, critical, unavailable
  final int? unitsAvailable;
  final String notes;

  BloodStock({
    required this.id,
    required this.bloodGroup,
    required this.stockLevel,
    this.unitsAvailable,
    required this.notes,
  });

  factory BloodStock.fromJson(Map<String, dynamic> json) {
    return BloodStock(
      id: json['id'] as int,
      bloodGroup: json['blood_group'] as String,
      stockLevel: json['stock_level'] as String? ?? 'adequate',
      unitsAvailable: json['units_available'] as int?,
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'blood_group': bloodGroup,
      'stock_level': stockLevel,
      'units_available': unitsAvailable,
      'notes': notes,
    };
  }
}

class BloodBank {
  final int id;
  final String name;
  final String address;
  final String district;
  final String phone;
  final String? phoneAlt;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final bool is24h;
  final List<BloodStock> bloodStocks;

  BloodBank({
    required this.id,
    required this.name,
    required this.address,
    required this.district,
    required this.phone,
    this.phoneAlt,
    this.latitude,
    this.longitude,
    required this.isActive,
    required this.is24h,
    required this.bloodStocks,
  });

  factory BloodBank.fromJson(Map<String, dynamic> json) {
    var stockList = json['blood_stocks'] as List? ?? [];
    List<BloodStock> stocks = stockList.map((s) => BloodStock.fromJson(s as Map<String, dynamic>)).toList();

    return BloodBank(
      id: json['id'] as int,
      name: json['name'] as String,
      address: json['address'] as String,
      district: json['district'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      phoneAlt: json['phone_alt'] as String?,
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
      isActive: json['is_active'] as bool? ?? true,
      is24h: json['is_24h'] as bool? ?? false,
      bloodStocks: stocks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'district': district,
      'phone': phone,
      'phone_alt': phoneAlt,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive,
      'is_24h': is24h,
      'blood_stocks': bloodStocks.map((s) => s.toJson()).toList(),
    };
  }
}
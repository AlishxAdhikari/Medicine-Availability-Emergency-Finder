import 'pharmacy.dart';

class MedicineCategory {
  final int id;
  final String name;
  final String icon;

  MedicineCategory({
    required this.id,
    required this.name,
    required this.icon,
  });

  factory MedicineCategory.fromJson(Map<String, dynamic> json) {
    return MedicineCategory(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'medication',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
    };
  }
}

class Medicine {
  final int id;
  final String name;
  final String genericName;
  final String brandName;
  final int? category;
  final MedicineCategory? categoryDetail;
  final String dosageForm;
  final String strength;
  final String description;
  final bool isEssential;
  final bool requiresPrescription;

  Medicine({
    required this.id,
    required this.name,
    required this.genericName,
    required this.brandName,
    this.category,
    this.categoryDetail,
    required this.dosageForm,
    required this.strength,
    required this.description,
    required this.isEssential,
    required this.requiresPrescription,
  });

  factory Medicine.fromJson(Map<String, dynamic> json) {
    return Medicine(
      id: json['id'] as int,
      name: json['name'] as String,
      genericName: json['generic_name'] as String? ?? '',
      brandName: json['brand_name'] as String? ?? '',
      category: json['category'] as int?,
      categoryDetail: json['category_detail'] != null
          ? MedicineCategory.fromJson(json['category_detail'] as Map<String, dynamic>)
          : null,
      dosageForm: json['dosage_form'] as String? ?? '',
      strength: json['strength'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isEssential: json['is_essential'] as bool? ?? false,
      requiresPrescription: json['requires_prescription'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'generic_name': genericName,
      'brand_name': brandName,
      'category': category,
      'category_detail': categoryDetail?.toJson(),
      'dosage_form': dosageForm,
      'strength': strength,
      'description': description,
      'is_essential': isEssential,
      'requires_prescription': requiresPrescription,
    };
  }
}

class PharmacyMedicineStock {
  final int id;
  final int? pharmacy;
  final Pharmacy? pharmacyDetail;
  final int? medicine;
  final Medicine? medicineDetail;
  final String availability; // available, low_stock, out_of_stock
  final double? priceNpr;
  final int? quantityOnHand;
  final String notes;
  final String updatedAt;

  PharmacyMedicineStock({
    required this.id,
    this.pharmacy,
    this.pharmacyDetail,
    this.medicine,
    this.medicineDetail,
    required this.availability,
    this.priceNpr,
    this.quantityOnHand,
    required this.notes,
    required this.updatedAt,
  });

  factory PharmacyMedicineStock.fromJson(Map<String, dynamic> json) {
    return PharmacyMedicineStock(
      id: json['id'] as int,
      pharmacy: json['pharmacy'] as int?,
      pharmacyDetail: json['pharmacy_detail'] != null
          ? Pharmacy.fromJson(json['pharmacy_detail'] as Map<String, dynamic>)
          : null,
      medicine: json['medicine'] as int?,
      medicineDetail: json['medicine_detail'] != null
          ? Medicine.fromJson(json['medicine_detail'] as Map<String, dynamic>)
          : null,
      availability: json['availability'] as String? ?? 'available',
      priceNpr: json['price_npr'] != null ? double.tryParse(json['price_npr'].toString()) : null,
      quantityOnHand: json['quantity_on_hand'] as int?,
      notes: json['notes'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pharmacy': pharmacy,
      'pharmacy_detail': pharmacyDetail?.toJson(),
      'medicine': medicine,
      'medicine_detail': medicineDetail?.toJson(),
      'availability': availability,
      'price_npr': priceNpr,
      'quantity_on_hand': quantityOnHand,
      'notes': notes,
      'updated_at': updatedAt,
    };
  }
}

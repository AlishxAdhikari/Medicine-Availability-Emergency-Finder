class MedicalProfile {
  final String bloodGroup;
  final int? heightCm;
  final double? weightKg;
  final String allergies;
  final String chronicConditions;
  final String currentMedications;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String emergencyContactRelation;

  MedicalProfile({
    required this.bloodGroup,
    this.heightCm,
    this.weightKg,
    required this.allergies,
    required this.chronicConditions,
    required this.currentMedications,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.emergencyContactRelation,
  });

  factory MedicalProfile.fromJson(Map<String, dynamic> json) {
    return MedicalProfile(
      bloodGroup: json['blood_group'] as String? ?? '',
      heightCm: json['height_cm'] as int?,
      weightKg: json['weight_kg'] != null ? double.tryParse(json['weight_kg'].toString()) : null,
      allergies: json['allergies'] as String? ?? '',
      chronicConditions: json['chronic_conditions'] as String? ?? '',
      currentMedications: json['current_medications'] as String? ?? '',
      emergencyContactName: json['emergency_contact_name'] as String? ?? '',
      emergencyContactPhone: json['emergency_contact_phone'] as String? ?? '',
      emergencyContactRelation: json['emergency_contact_relation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blood_group': bloodGroup,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'allergies': allergies,
      'chronic_conditions': chronicConditions,
      'current_medications': currentMedications,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'emergency_contact_relation': emergencyContactRelation,
    };
  }

  factory MedicalProfile.empty() {
    return MedicalProfile(
      bloodGroup: 'O+',
      heightCm: null,
      weightKg: null,
      allergies: '',
      chronicConditions: '',
      currentMedications: '',
      emergencyContactName: '',
      emergencyContactPhone: '',
      emergencyContactRelation: '',
    );
  }
}

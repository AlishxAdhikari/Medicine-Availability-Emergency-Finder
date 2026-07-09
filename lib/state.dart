import 'package:flutter/material.dart';

class EmergencyContact {
  final String name;
  final String relationship;
  final String phoneNumber;
  final String? initials;

  EmergencyContact({
    required this.name,
    required this.relationship,
    required this.phoneNumber,
    this.initials,
  });

  EmergencyContact copyWith({
    String? name,
    String? relationship,
    String? phoneNumber,
    String? initials,
  }) {
    return EmergencyContact(
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      initials: initials ?? this.initials,
    );
  }
}

class Medication {
  final String name;
  final String dosage;
  final String frequency;

  Medication({
    required this.name,
    required this.dosage,
    required this.frequency,
  });
}

class UserProfile {
  final String fullName;
  final String dob;
  final String gender;
  final String phoneNumber;
  final String medicalId;
  final String bloodGroup;
  final String height;
  final String weight;
  final List<String> allergies;
  final List<Medication> medications;
  final List<EmergencyContact> emergencyContacts;

  UserProfile({
    required this.fullName,
    required this.dob,
    required this.gender,
    required this.phoneNumber,
    required this.medicalId,
    required this.bloodGroup,
    required this.height,
    required this.weight,
    required this.allergies,
    required this.medications,
    required this.emergencyContacts,
  });

  UserProfile copyWith({
    String? fullName,
    String? dob,
    String? gender,
    String? phoneNumber,
    String? medicalId,
    String? bloodGroup,
    String? height,
    String? weight,
    List<String>? allergies,
    List<Medication>? medications,
    List<EmergencyContact>? emergencyContacts,
  }) {
    return UserProfile(
      fullName: fullName ?? this.fullName,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      medicalId: medicalId ?? this.medicalId,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
    );
  }
}

class Pharmacy {
  final String name;
  final String distance;
  final String address;
  final bool isOpen;
  final List<Map<String, dynamic>> items; // {'name': 'Insulin', 'inStock': true}

  Pharmacy({
    required this.name,
    required this.distance,
    required this.address,
    required this.isOpen,
    required this.items,
  });
}

class Ambulance {
  final String name;
  final String location;
  final String distance;
  final bool isAvailable;

  Ambulance({
    required this.name,
    required this.location,
    required this.distance,
    required this.isAvailable,
  });
}

class BloodStock {
  final String type;
  final String status; // 'CRITICAL', 'NORMAL', 'LOW'

  BloodStock({required this.type, required this.status});
}

class BloodBank {
  final String name;
  final String location;
  final String distance;
  final List<BloodStock> availability;

  BloodBank({
    required this.name,
    required this.location,
    required this.distance,
    required this.availability,
  });
}

class AppStateManager {
  static final AppStateManager instance = AppStateManager._internal();

  AppStateManager._internal();

  // Mode Notifier
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

  // Authentication State
  final ValueNotifier<bool> isLoggedInNotifier = ValueNotifier<bool>(false);

  // Current Language Code ('en' or 'ne')
  final ValueNotifier<String> languageNotifier = ValueNotifier<String>('en');

  // Selected District filter for emergency screen
  final ValueNotifier<String> selectedDistrictNotifier = ValueNotifier<String>('Kathmandu');

  // Selected Radius filter for blood banks in emergency screen
  final ValueNotifier<int> bloodBankRadiusNotifier = ValueNotifier<int>(5);

  // Search Radius filter for pharmacy search screen
  final ValueNotifier<double> pharmacyRadiusNotifier = ValueNotifier<double>(12.0);

  // Search Query for pharmacy screen
  final ValueNotifier<String> pharmacySearchQueryNotifier = ValueNotifier<String>('');

  // Selected view mode for blood banks (List vs Map)
  final ValueNotifier<bool> isBloodBankMapViewNotifier = ValueNotifier<bool>(false);

  // User Profile Notifier
  late final ValueNotifier<UserProfile> userProfileNotifier = ValueNotifier<UserProfile>(
    UserProfile(
      fullName: 'Sarah Jenkins',
      dob: '1981-04-12',
      gender: 'Female',
      phoneNumber: '(555) 123-4567',
      medicalId: 'MA-882-991',
      bloodGroup: 'O+',
      height: '5\' 6"',
      weight: '145',
      allergies: ['Penicillin', 'Latex'],
      medications: [
        Medication(name: 'Metformin', dosage: '500mg', frequency: 'Twice Daily'),
        Medication(name: 'Lisinopril', dosage: '10mg', frequency: 'Once Daily'),
      ],
      emergencyContacts: [
        EmergencyContact(
          name: 'David Jenkins',
          relationship: 'Spouse',
          phoneNumber: '(555) 987-6543',
        ),
        EmergencyContact(
          name: 'Martha Roberts',
          relationship: 'Mother',
          phoneNumber: '(555) 222-3333',
          initials: 'MR',
        ),
      ],
    ),
  );

  // Mock Pharmacies List
  final List<Pharmacy> mockPharmacies = [
    Pharmacy(
      name: 'City Central Pharmacy',
      distance: '1.2 km',
      address: '123 Health Ave.',
      isOpen: true,
      items: [
        {'name': 'Insulin', 'inStock': true},
        {'name': 'Paracetamol', 'inStock': true},
      ],
    ),
    Pharmacy(
      name: 'MediQuick 24/7',
      distance: '3.5 km',
      address: '45 West Blvd.',
      isOpen: true,
      items: [
        {'name': 'Insulin', 'inStock': false},
        {'name': 'Paracetamol', 'inStock': true},
      ],
    ),
    Pharmacy(
      name: 'Patan Pharmacy Services',
      distance: '4.8 km',
      address: 'Lagankhel, Lalitpur',
      isOpen: false,
      items: [
        {'name': 'Insulin', 'inStock': true},
        {'name': 'Metformin', 'inStock': true},
      ],
    ),
  ];

  // Mock Ambulances
  final List<Ambulance> mockAmbulances = [
    Ambulance(
      name: 'Red Cross Ambulance',
      location: 'Teku, Kathmandu',
      distance: '2.5 km',
      isAvailable: true,
    ),
    Ambulance(
      name: 'Grande Hospital Unit',
      location: 'Dhapasi, Kathmandu',
      distance: '4.1 km',
      isAvailable: true,
    ),
    Ambulance(
      name: 'Alka Hospital Ambulance',
      location: 'Jawalakhel, Lalitpur',
      distance: '6.2 km',
      isAvailable: false,
    ),
  ];

  // Mock Blood Banks
  final List<BloodBank> mockBloodBanks = [
    BloodBank(
      name: 'Central Blood Transfusion',
      location: 'Pradarshani Marg, Kathmandu',
      distance: '3.2 km',
      availability: [
        BloodStock(type: 'A+', status: 'CRITICAL'),
        BloodStock(type: 'O+', status: 'NORMAL'),
        BloodStock(type: 'B-', status: 'LOW'),
        BloodStock(type: 'AB+', status: 'NORMAL'),
      ],
    ),
    BloodBank(
      name: 'Red Cross Blood Bank',
      location: 'Balkhu, Kathmandu',
      distance: '4.8 km',
      availability: [
        BloodStock(type: 'A-', status: 'NORMAL'),
        BloodStock(type: 'O-', status: 'CRITICAL'),
        BloodStock(type: 'B+', status: 'NORMAL'),
        BloodStock(type: 'AB-', status: 'LOW'),
      ],
    ),
  ];

  UserProfile buildProfileFromAuth({
    String? fullName,
    String? email,
    String? phoneNumber,
    String? dob,
    String? gender,
    String? medicalId,
    String? bloodGroup,
    String? height,
    String? weight,
  }) {
    final currentProfile = userProfileNotifier.value;
    final hasCustomProfile =
        currentProfile.fullName != 'Sarah Jenkins' ||
        currentProfile.phoneNumber != '(555) 123-4567' ||
        currentProfile.medicalId != 'MA-882-991';

    final rawFullName = fullName?.trim();
    final rawEmail = email?.trim();
    final fallbackName = rawEmail != null && rawEmail.isNotEmpty
        ? (rawEmail.contains('@') ? rawEmail.split('@').first : rawEmail)
        : currentProfile.fullName;
    final resolvedName = (rawFullName != null && rawFullName.isNotEmpty)
        ? rawFullName
        : (hasCustomProfile ? currentProfile.fullName : fallbackName);

    final resolvedEmail = rawEmail;
    final medicalIdSeed = resolvedEmail ?? resolvedName;
    final generatedMedicalId = medicalIdSeed.isEmpty
        ? currentProfile.medicalId
        : 'MA-${medicalIdSeed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase().substring(0, medicalIdSeed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length > 6 ? 6 : medicalIdSeed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length)}';

    return currentProfile.copyWith(
      fullName: resolvedName,
      dob: dob ?? currentProfile.dob,
      gender: gender ?? currentProfile.gender,
      phoneNumber: phoneNumber ?? currentProfile.phoneNumber,
      medicalId: medicalId?.trim().isNotEmpty == true
          ? medicalId!.trim()
          : (hasCustomProfile ? currentProfile.medicalId : generatedMedicalId),
      bloodGroup: bloodGroup ?? currentProfile.bloodGroup,
      height: height ?? currentProfile.height,
      weight: weight ?? currentProfile.weight,
    );
  }
  void toggleTheme() {
    themeModeNotifier.value =
        themeModeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }

  void setLoggedIn(bool status) {
    isLoggedInNotifier.value = status;
  }

  void toggleLanguage() {
    languageNotifier.value = languageNotifier.value == 'en' ? 'ne' : 'en';
  }

  void updateProfile(UserProfile profile) {
    userProfileNotifier.value = profile;
  }
}

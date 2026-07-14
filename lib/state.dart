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
  final String address;
  final List<String> allergies;
  final List<Medication> medications;
  final List<EmergencyContact> emergencyContacts;
  final String? profilePictureUrl; // Added field for profile picture URL

  UserProfile({
    required this.fullName,
    required this.dob,
    required this.gender,
    required this.phoneNumber,
    required this.medicalId,
    required this.bloodGroup,
    required this.height,
    required this.weight,
    this.address = '',
    required this.allergies,
    required this.medications,
    required this.emergencyContacts,
    this.profilePictureUrl,
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
    String? address,
    List<String>? allergies,
    List<Medication>? medications,
    List<EmergencyContact>? emergencyContacts,
    String? profilePictureUrl,
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
      address: address ?? this.address,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
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

  // User Profile Notifier. Starts genuinely blank -- real values are filled
  // in by buildProfileFromAuth() right after register/login, and then by
  // MedicalProfileService.fetch() once the backend's /medical-id/ data
  // loads (see AppShell.initState in home_screen.dart). There is no mock
  // "Sarah Jenkins" placeholder anymore since the API is fully wired up.
  late final ValueNotifier<UserProfile> userProfileNotifier = ValueNotifier<UserProfile>(
    UserProfile(
      fullName: '',
      dob: '',
      gender: '',
      phoneNumber: '',
      medicalId: '',
      bloodGroup: '',
      height: '',
      weight: '',
      address: '',
      allergies: const [],
      medications: const [],
      emergencyContacts: const [],
      profilePictureUrl: null,
    ),
  );

  /// Called right after register/login with whatever the auth response
  /// gives us (name, email, phone, dob, gender). Only overwrites a field
  /// when a non-empty value is actually provided, so this can be called
  /// multiple times (e.g. once from CreateAccountScreen, again from
  /// LoginScreen) without clobbering data the other call already set.
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
    String? profilePictureUrl,
  }) {
    final currentProfile = userProfileNotifier.value;

    final rawFullName = fullName?.trim();
    final rawEmail = email?.trim();
    final fallbackName = rawEmail != null && rawEmail.isNotEmpty
        ? (rawEmail.contains('@') ? rawEmail.split('@').first : rawEmail)
        : currentProfile.fullName;
    final resolvedName = (rawFullName != null && rawFullName.isNotEmpty)
        ? rawFullName
        : (currentProfile.fullName.isNotEmpty ? currentProfile.fullName : fallbackName);

    final medicalIdSeed = rawEmail?.isNotEmpty == true ? rawEmail! : resolvedName;
    final digest = medicalIdSeed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final generatedMedicalId = digest.isEmpty
        ? currentProfile.medicalId
        : 'MA-${digest.substring(0, digest.length > 6 ? 6 : digest.length)}';

    return currentProfile.copyWith(
      fullName: resolvedName,
      dob: (dob != null && dob.isNotEmpty) ? dob : currentProfile.dob,
      gender: (gender != null && gender.isNotEmpty) ? gender : currentProfile.gender,
      phoneNumber: (phoneNumber != null && phoneNumber.isNotEmpty)
          ? phoneNumber
          : currentProfile.phoneNumber,
      medicalId: (medicalId != null && medicalId.trim().isNotEmpty)
          ? medicalId.trim()
          : (currentProfile.medicalId.isNotEmpty ? currentProfile.medicalId : generatedMedicalId),
      bloodGroup: (bloodGroup != null && bloodGroup.isNotEmpty) ? bloodGroup : currentProfile.bloodGroup,
      height: (height != null && height.isNotEmpty) ? height : currentProfile.height,
      weight: (weight != null && weight.isNotEmpty) ? weight : currentProfile.weight,
      profilePictureUrl: profilePictureUrl ?? currentProfile.profilePictureUrl,
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

  /// Clears the in-memory profile back to blank. Call this on logout so a
  /// different user signing in on the same device/session doesn't briefly
  /// see the previous user's medical data before the new fetch completes.
  void resetProfile() {
    userProfileNotifier.value = UserProfile(
      fullName: '',
      dob: '',
      gender: '',
      phoneNumber: '',
      medicalId: '',
      bloodGroup: '',
      height: '',
      weight: '',
      address: '',
      allergies: const [],
      medications: const [],
      emergencyContacts: const [],
      profilePictureUrl: null,
    );
  }
}
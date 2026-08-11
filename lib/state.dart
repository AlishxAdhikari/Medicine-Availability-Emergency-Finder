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
  final int id; // backend pharmacy id -- needed for ws/stock/<id>/ live updates
  final String name;
  final String distance;
  final String address;
  final bool isOpen;
  /// One entry per stocked medicine, shaped by PharmacyService._toPharmacy:
  /// `{'name': 'Insulin', 'quantity': 12, 'lowThreshold': 5, 'inStock': true}`.
  ///
  /// Mutable maps on purpose: [applyStockLevel] rewrites entries in place when
  /// a live `stock_level` push arrives, so the card updates without refetching
  /// the whole search.
  final List<Map<String, dynamic>> items;
  // Real coordinates straight off Pharmacy.latitude/longitude (non-null in the
  // Django model), used to place the map marker and to build the Directions
  // intent. Nullable here rather than required because these come from JSON
  // and a serializer change shouldn't be able to crash the search screen --
  // the map skips a pin it can't place, and Directions reports "no location".
  final double? latitude;
  final double? longitude;
  // `blank=True` on the model, so a real row can genuinely have no number.
  final String phone;

  Pharmacy({
    required this.id,
    required this.name,
    required this.distance,
    required this.address,
    required this.isOpen,
    required this.items,
    this.latitude,
    this.longitude,
    this.phone = '',
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Applies a live quantity for [medicineName], returning true when this
  /// pharmacy actually stocks it (and so the caller should rebuild).
  ///
  /// Writes `quantity` and `inStock` together. They are two views of one fact,
  /// and updating only the boolean is exactly the bug that made a sale from 50
  /// to 49 invisible: the chip kept saying "In Stock" because the boolean had
  /// not changed, while the number behind it had.
  ///
  /// [lowThreshold] is optional because only the `stock_level` push carries
  /// one; a `stock_alert` does not, and leaving the previous threshold in
  /// place is more accurate than overwriting it with a guess.
  bool applyStockLevel(String medicineName, int quantity, {int? lowThreshold}) {
    final index = items.indexWhere((i) => i['name'] == medicineName);
    if (index == -1) return false;
    items[index]['quantity'] = quantity;
    items[index]['inStock'] = quantity > 0;
    if (lowThreshold != null) items[index]['lowThreshold'] = lowThreshold;
    return true;
  }
}

/// How the search results render a medicine's availability.
///
/// Offered as a user choice rather than picked for them: the exact count is
/// what makes a live sale visible ("12" ticking to "11" while you watch), but
/// a customer deciding where to walk usually only cares whether the medicine
/// is there at all, and some pharmacies would rather not publish their exact
/// holdings on a stranger's screen.
enum StockDisplayMode {
  /// "Paracetamol (In Stock)" -- the original boolean chip.
  availability,

  /// "Paracetamol (12 left)" -- the exact committed quantity.
  quantity,
}

class Ambulance {
  final String name;
  final String location;
  final String distance;
  final bool isAvailable;
  // AmbulanceProvider has no lat/lng in the backend -- these are matched by
  // district, not coordinates -- so there is deliberately no position here and
  // ambulances never appear on a map. `phone` is required on that model, so
  // unlike the others this one should always be dialable.
  final String phone;

  Ambulance({
    required this.name,
    required this.location,
    required this.distance,
    required this.isAvailable,
    this.phone = '',
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
  // Same shape and same reasoning as Pharmacy's -- see the note there.
  final double? latitude;
  final double? longitude;
  final String phone;

  BloodBank({
    required this.name,
    required this.location,
    required this.distance,
    required this.availability,
    this.latitude,
    this.longitude,
    this.phone = '',
  });

  bool get hasCoordinates => latitude != null && longitude != null;
}

class AppStateManager {
  static final AppStateManager instance = AppStateManager._internal();

  AppStateManager._internal();

  // Mode Notifier
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

  // Authentication State
  final ValueNotifier<bool> isLoggedInNotifier = ValueNotifier<bool>(false);

  /// Whether the signed-in account is linked to a pharmacy. Set from the
  /// `role` field on the login response (see core/serializers.py's
  /// UserSerializer), and from the saved snapshot on the biometric path.
  final ValueNotifier<bool> isPharmacyOwnerNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int?> ownedPharmacyIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String> ownedPharmacyNameNotifier = ValueNotifier<String>('');

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

  void setOwnerRole({required bool isOwner, int? pharmacyId, String pharmacyName = ''}) {
    isPharmacyOwnerNotifier.value = isOwner;
    ownedPharmacyIdNotifier.value = isOwner ? pharmacyId : null;
    ownedPharmacyNameNotifier.value = isOwner ? pharmacyName : '';
  }

  /// Call on logout as well as before a fresh login, so one account's
  /// pharmacy can't leak into the next session on a shared device.
  void clearOwnerRole() {
    setOwnerRole(isOwner: false);
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
Map<String, dynamic> profileToSnapshot(UserProfile p) {
  return {
    'fullName': p.fullName,
    'dob': p.dob,
    'gender': p.gender,
    'phoneNumber': p.phoneNumber,
    'medicalId': p.medicalId,
    'bloodGroup': p.bloodGroup,
    'height': p.height,
    'weight': p.weight,
    'address': p.address,
    'allergies': p.allergies,
    'medications': p.medications
        .map((m) => {
              'name': m.name,
              'dosage': m.dosage,
              'frequency': m.frequency,
            })
        .toList(),
    'emergencyContacts': p.emergencyContacts
        .map((c) => {
              'name': c.name,
              'relationship': c.relationship,
              'phoneNumber': c.phoneNumber,
              'initials': c.initials,
            })
        .toList(),
    'profilePictureUrl': p.profilePictureUrl,
    'isPharmacyOwner': AppStateManager.instance.isPharmacyOwnerNotifier.value,
    'ownedPharmacyId': AppStateManager.instance.ownedPharmacyIdNotifier.value,
    'ownedPharmacyName': AppStateManager.instance.ownedPharmacyNameNotifier.value,
  };
}

/// Restores the owner role from a biometric snapshot. Kept separate from
/// profileFromSnapshot because that builds a UserProfile, while the role
/// lives on AppStateManager rather than on the profile object.
void applyOwnerRoleFromSnapshot(Map<String, dynamic> s) {
  AppStateManager.instance.setOwnerRole(
    isOwner: s['isPharmacyOwner'] as bool? ?? false,
    // `as num?` rather than `as int?`: a snapshot that round-tripped through
    // JSON can hand back a double for a whole number, and a hard int cast
    // would throw where every sibling field degrades to a default.
    pharmacyId: (s['ownedPharmacyId'] as num?)?.toInt(),
    pharmacyName: s['ownedPharmacyName'] as String? ?? '',
  );
}

UserProfile profileFromSnapshot(Map<String, dynamic> s) {
  final meds = (s['medications'] as List? ?? [])
      .map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        return Medication(
          name: map['name'] as String? ?? '',
          dosage: map['dosage'] as String? ?? '',
          frequency: map['frequency'] as String? ?? '',
        );
      })
      .toList();

  final contacts = (s['emergencyContacts'] as List? ?? [])
      .map((c) {
        final map = Map<String, dynamic>.from(c as Map);
        return EmergencyContact(
          name: map['name'] as String? ?? '',
          relationship: map['relationship'] as String? ?? '',
          phoneNumber: map['phoneNumber'] as String? ?? '',
          initials: map['initials'] as String?,
        );
      })
      .toList();

  return UserProfile(
    fullName: s['fullName'] as String? ?? '',
    dob: s['dob'] as String? ?? '',
    gender: s['gender'] as String? ?? '',
    phoneNumber: s['phoneNumber'] as String? ?? '',
    medicalId: s['medicalId'] as String? ?? '',
    bloodGroup: s['bloodGroup'] as String? ?? '',
    height: s['height'] as String? ?? '',
    weight: s['weight'] as String? ?? '',
    address: s['address'] as String? ?? '',
    allergies: (s['allergies'] as List? ?? []).map((e) => e.toString()).toList(),
    medications: meds,
    emergencyContacts: contacts,
    profilePictureUrl: s['profilePictureUrl'] as String?,
  );
}
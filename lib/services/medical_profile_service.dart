import '../state.dart';
import 'api_client.dart';

/// Wraps GET/PUT/PATCH /api/v1/auth/medical-id/ (MedicalProfileView in
/// core/views.py) and maps the response onto the app's existing
/// UserProfile model (state.dart).
///
/// Backend stores identity + medical fields. Allergies / medications are
/// free-text on the server and lists in the UI; this service converts.
/// Only the *first* emergency contact round-trips to the server.
class MedicalProfileService {
  MedicalProfileService._internal();
  static final MedicalProfileService instance = MedicalProfileService._internal();

  final _client = ApiClient.instance;

  /// GET /auth/medical-id/ and merge into the current in-memory profile.
  Future<UserProfile> fetch() async {
    final json =
        await _client.get('/auth/medical-id/', auth: true) as Map<String, dynamic>;
    final current = AppStateManager.instance.userProfileNotifier.value;
    final merged = _applyApiJson(current, json);
    AppStateManager.instance.updateProfile(merged);
    return merged;
  }

  /// PATCH /auth/medical-id/ with the full editable profile.
  /// Returns the server's copy merged back into app state.
  Future<UserProfile> save(UserProfile profile) async {
    final body = <String, dynamic>{
      'full_name': profile.fullName.trim(),
      'date_of_birth': profile.dob.trim(),
      'gender': profile.gender.trim(),
      'address': profile.address.trim(),
      'blood_group': profile.bloodGroup.trim(),
      'allergies': profile.allergies.join(', '),
      'current_medications': _medicationsToText(profile.medications),
      ..._toApiContact(profile.emergencyContacts),
    };

    // Only send numeric fields when parseable — sending null on a full PUT
    // used to wipe previously saved values on some DRF configs.
    final height = double.tryParse(profile.height.trim());
    if (height != null) {
      body['height_cm'] = height;
    }
    final weight = double.tryParse(profile.weight.trim());
    if (weight != null) {
      body['weight_kg'] = weight;
    }

    // Empty phone → clear on server (serializer maps '' to null).
    // Non-empty is validated unique excluding this user.
    body['phone_number'] = profile.phoneNumber.trim();

    // Prefer PATCH so we never accidentally blank fields the client omitted.
    final json = await _client.patch('/auth/medical-id/', body, auth: true)
        as Map<String, dynamic>;

    final merged = _applyApiJson(profile, json);
    AppStateManager.instance.updateProfile(merged);
    return merged;
  }

  UserProfile _applyApiJson(UserProfile base, Map<String, dynamic> json) {
    final heightCm = json['height_cm'];
    final weightKg = json['weight_kg'];
    final allergiesText = (json['allergies'] as String? ?? '').trim();
    final medsText = (json['current_medications'] as String? ?? '').trim();
    final contactName = (json['emergency_contact_name'] as String? ?? '').trim();
    final contactPhone = (json['emergency_contact_phone'] as String? ?? '').trim();
    final phone = (json['phone_number'] as String? ?? '').trim();

    final fullName = (json['full_name'] as String? ?? '').trim();
    final dob = (json['date_of_birth'] as String? ?? '').trim();
    final gender = (json['gender'] as String? ?? '').trim();
    final address = (json['address'] as String? ?? '').trim();

    // Backend stores a single emergency contact (name + phone). Relationship
    // is UI-only and is kept from the local list when present.
    final mergedContacts = List<EmergencyContact>.from(base.emergencyContacts);
    if (json.containsKey('emergency_contact_name')) {
      if (contactName.isNotEmpty) {
        final primary = EmergencyContact(
          name: contactName,
          relationship: mergedContacts.isNotEmpty
              ? mergedContacts.first.relationship
              : 'Contact',
          phoneNumber: contactPhone,
          initials: contactName
              .substring(0, contactName.length > 2 ? 2 : contactName.length)
              .toUpperCase(),
        );
        if (mergedContacts.isEmpty) {
          mergedContacts.add(primary);
        } else {
          mergedContacts[0] = primary;
        }
      } else if (mergedContacts.isNotEmpty &&
          contactName.isEmpty &&
          contactPhone.isEmpty) {
        // Server cleared the contact — drop the primary only.
        mergedContacts.removeAt(0);
      }
    }

    return base.copyWith(
      fullName: fullName.isNotEmpty ? fullName : base.fullName,
      dob: dob.isNotEmpty ? dob : base.dob,
      gender: gender.isNotEmpty ? gender : base.gender,
      address: json.containsKey('address') ? address : base.address,
      bloodGroup: (json['blood_group'] as String? ?? base.bloodGroup),
      height: heightCm != null ? _formatNumber(heightCm) : base.height,
      weight: weightKg != null ? _formatNumber(weightKg) : base.weight,
      allergies: json.containsKey('allergies')
          ? allergiesText
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : base.allergies,
      medications: json.containsKey('current_medications')
          ? (medsText.isNotEmpty ? _medicationsFromText(medsText) : const [])
          : base.medications,
      emergencyContacts: mergedContacts,
      phoneNumber: phone.isNotEmpty ? phone : base.phoneNumber,
    );
  }

  Map<String, dynamic> _toApiContact(List<EmergencyContact> contacts) {
    if (contacts.isEmpty) {
      return {
        'emergency_contact_name': '',
        'emergency_contact_phone': '',
      };
    }
    final primary = contacts.first;
    return {
      'emergency_contact_name': primary.name,
      'emergency_contact_phone': primary.phoneNumber,
    };
  }

  String _medicationsToText(List<Medication> meds) {
    return meds
        .map((m) => '${m.name} ${m.dosage} (${m.frequency})')
        .join('; ');
  }

  List<Medication> _medicationsFromText(String text) {
    final entryPattern = RegExp(r'^(.*?)\s*\(([^)]*)\)\s*$');
    return text
        .split(';')
        .map((raw) {
          final entry = raw.trim();
          if (entry.isEmpty) return null;

          String namePart = entry;
          String frequency = 'As directed';
          final match = entryPattern.firstMatch(entry);
          if (match != null) {
            namePart = match.group(1)!.trim();
            frequency = match.group(2)!.trim();
          }

          final words = namePart.split(RegExp(r'\s+'));
          final name = words.isNotEmpty ? words.first : namePart;
          final dosage = words.length > 1 ? words.sublist(1).join(' ') : '';

          return Medication(name: name, dosage: dosage, frequency: frequency);
        })
        .whereType<Medication>()
        .toList();
  }

  String _formatNumber(dynamic value) {
    final n = value is num ? value : num.tryParse(value.toString());
    if (n == null) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }
}

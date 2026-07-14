import '../state.dart';
import 'api_client.dart';

/// Wraps GET/PUT /api/v1/auth/medical-id/ (MedicalProfileView in
/// core/views.py) and maps the response onto the app's existing
/// UserProfile model (state.dart), same pattern as PharmacyService and
/// EmergencyService.
///
/// The backend's MedicalProfile model is intentionally simpler than the
/// UI's UserProfile:
///   - allergies / current_medications are free-text fields, not lists.
///   - there is exactly one emergency_contact_name/phone pair, not a list.
/// This service converts between the two shapes. Only the *first*
/// emergency contact round-trips to the server; any additional contacts
/// the user adds stay local-only until the backend model supports more
/// than one (see note on _toApiContacts below).
class MedicalProfileService {
  MedicalProfileService._internal();
  static final MedicalProfileService instance = MedicalProfileService._internal();

  final _client = ApiClient.instance;

  /// GET /medical-id/ and merge the result into the current in-memory
  /// profile, keeping fullName/dob/gender/phoneNumber (which come from
  /// auth, not this endpoint) untouched.
  Future<UserProfile> fetch() async {
    final json = await _client.get('/medical-id/', auth: true) as Map<String, dynamic>;
    final current = AppStateManager.instance.userProfileNotifier.value;
    final merged = _applyApiJson(current, json);
    AppStateManager.instance.updateProfile(merged);
    return merged;
  }

  /// PUT /medical-id/ with the medically-relevant subset of [profile].
  /// Returns the server's copy (in case it normalizes anything) merged
  /// back into the profile, and updates app state on success.
  Future<UserProfile> save(UserProfile profile) async {
    final body = {
      'blood_group': profile.bloodGroup,
      'height_cm': double.tryParse(profile.height.trim()),
      'weight_kg': double.tryParse(profile.weight.trim()),
      'allergies': profile.allergies.join(', '),
      'current_medications': _medicationsToText(profile.medications),
      'phone_number': profile.phoneNumber,
      ..._toApiContact(profile.emergencyContacts),
    };

    final json = await _client.put('/medical-id/', body, auth: true) as Map<String, dynamic>;
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

    // Preserve any contacts beyond the first (backend only knows about
    // one), just refresh/replace the first one from the server's copy.
    final mergedContacts = List<EmergencyContact>.from(base.emergencyContacts);
    if (contactName.isNotEmpty) {
      final primary = EmergencyContact(
        name: contactName,
        relationship: mergedContacts.isNotEmpty ? mergedContacts.first.relationship : 'Contact',
        phoneNumber: contactPhone,
        initials: contactName.substring(0, contactName.length > 2 ? 2 : contactName.length).toUpperCase(),
      );
      if (mergedContacts.isEmpty) {
        mergedContacts.add(primary);
      } else {
        mergedContacts[0] = primary;
      }
    }

    return base.copyWith(
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
      return {'emergency_contact_name': '', 'emergency_contact_phone': ''};
    }
    final primary = contacts.first;
    return {
      'emergency_contact_name': primary.name,
      'emergency_contact_phone': primary.phoneNumber,
    };
  }

  String _medicationsToText(List<Medication> meds) {
    return meds.map((m) => '${m.name} ${m.dosage} (${m.frequency})').join('; ');
  }

  List<Medication> _medicationsFromText(String text) {
    final entryPattern = RegExp(r'^(.*?)\s*\(([^)]*)\)\s*$');
    return text.split(';').map((raw) {
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
    }).whereType<Medication>().toList();
  }

  String _formatNumber(dynamic value) {
    final n = value is num ? value : num.tryParse(value.toString());
    if (n == null) return '';
    // Drop a trailing ".0" so "170.0" shows as "170" while "170.5" stays.
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }
}
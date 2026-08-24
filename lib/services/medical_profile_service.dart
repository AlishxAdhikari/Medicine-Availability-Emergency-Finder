import '../state.dart';
import 'api_client.dart';

/// Wraps GET/PUT/PATCH /api/v1/auth/medical-id/ (MedicalProfileView in
/// core/views.py) and maps the response onto the app's existing
/// UserProfile model (state.dart).
///
/// Backend stores identity + medical fields. Allergies / medications are
/// free-text on the server and lists in the UI; this service converts.
/// Emergency contacts round-trip as a list (`emergency_contacts`). The
/// server also returns the legacy `emergency_contact_name`/`_phone` pair
/// as a mirror of the first entry; this service ignores it on read and
/// never writes it, since the list is now the single source of truth.
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
    final phone = (json['phone_number'] as String? ?? '').trim();

    final fullName = (json['full_name'] as String? ?? '').trim();
    final dob = (json['date_of_birth'] as String? ?? '').trim();
    final gender = (json['gender'] as String? ?? '').trim();
    final address = (json['address'] as String? ?? '').trim();

    // The server's list replaces the local one outright when present. It is
    // authoritative: merging index-by-index (what this used to do for the
    // single legacy contact) reattached the wrong relationship to the wrong
    // person as soon as one was deleted from the middle of the list.
    final mergedContacts = json.containsKey('emergency_contacts')
        ? [
            for (final raw in (json['emergency_contacts'] as List? ?? []))
              _contactFromApi(Map<String, dynamic>.from(raw as Map)),
          ]
        : List<EmergencyContact>.from(base.emergencyContacts);

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

  /// Sends every contact, in order. An empty list is sent as an empty list
  /// rather than omitted, so deleting your last contact actually clears it
  /// server-side -- the serializer treats "absent" as "leave alone".
  EmergencyContact _contactFromApi(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? '').trim();
    return EmergencyContact(
      name: name,
      // Relationship is optional server-side; the cards read better with a
      // neutral word than with an empty line under the name.
      relationship: (json['relationship'] as String? ?? '').trim().isEmpty
          ? 'Contact'
          : (json['relationship'] as String).trim(),
      phoneNumber: (json['phone_number'] as String? ?? '').trim(),
      initials: name.isEmpty
          ? null
          : name.substring(0, name.length > 2 ? 2 : name.length).toUpperCase(),
    );
  }

  Map<String, dynamic> _toApiContact(List<EmergencyContact> contacts) {
    return {
      'emergency_contacts': [
        for (final contact in contacts)
          {
            'name': contact.name,
            'relationship': contact.relationship,
            'phone_number': contact.phoneNumber,
          },
      ],
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/emergency_contact.dart';

class EmergencyContactsNotifier extends StateNotifier<List<EmergencyContact>> {
  late final Box _box;
  final _uuid = const Uuid();

  EmergencyContactsNotifier() : super([]) {
    _initHiveAndLoad();
  }

  Future<void> _initHiveAndLoad() async {
    _box = await Hive.openBox('emergency_contacts');
    final stored = _box.get('contacts');
    
    if (stored == null || (stored as List).isEmpty) {
      // Prepopulate defaults
      final defaults = [
        EmergencyContact(id: _uuid.v4(), label: '24/7 Ambulance Service', phoneNumber: '102', icon: 'local_hospital'),
        EmergencyContact(id: _uuid.v4(), label: 'Nepal Police ER', phoneNumber: '100', icon: 'local_police'),
        EmergencyContact(id: _uuid.v4(), label: 'Fire Brigade Dispatch', phoneNumber: '101', icon: 'fire_truck'),
        EmergencyContact(id: _uuid.v4(), label: 'Nepal Red Cross Blood Bank', phoneNumber: '+977-1-4270650', icon: 'bloodtype'),
      ];
      await _saveToHive(defaults);
      state = defaults;
    } else {
      final list = List.from(stored);
      state = list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return EmergencyContact.fromJson(map);
      }).toList();
    }
  }

  Future<void> _saveToHive(List<EmergencyContact> contacts) async {
    final list = contacts.map((c) => c.toJson()).toList();
    await _box.put('contacts', list);
  }

  Future<void> addContact(String label, String phoneNumber, String icon) async {
    final newContact = EmergencyContact(
      id: _uuid.v4(),
      label: label,
      phoneNumber: phoneNumber,
      icon: icon,
    );
    final updated = [...state, newContact];
    state = updated;
    await _saveToHive(updated);
  }

  Future<void> editContact(String id, String label, String phoneNumber, String icon) async {
    final updated = state.map((c) {
      if (c.id == id) {
        return EmergencyContact(id: id, label: label, phoneNumber: phoneNumber, icon: icon);
      }
      return c;
    }).toList();
    state = updated;
    await _saveToHive(updated);
  }

  Future<void> deleteContact(String id) async {
    final updated = state.where((c) => c.id != id).toList();
    state = updated;
    await _saveToHive(updated);
  }
}

final emergencyContactsProvider = StateNotifierProvider<EmergencyContactsNotifier, List<EmergencyContact>>((ref) {
  return EmergencyContactsNotifier();
});

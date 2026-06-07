import 'package:flutter/material.dart';

import '../models/emergency_contact.dart';
import '../models/medical_profile.dart';
import '../widgets/emergency_contact_tile.dart';
import '../widgets/medical_id_card.dart';
import '../widgets/profile_field.dart';
import '../widgets/section_header.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  MedicalProfile _profile = MedicalProfile(
    bloodGroup: 'O+',
    heightCm: 171,
    weightKg: 68,
    allergies: 'Penicillin',
    chronicConditions: 'Asthma',
    currentMedications: 'Salbutamol inhaler',
    emergencyContactName: 'Sita Shrestha',
    emergencyContactPhone: '+977-9841000000',
    emergencyContactRelation: 'Mother',
  );

  final _contacts = [
    EmergencyContact(id: '1', label: 'Sita Shrestha', phoneNumber: '+977-9841000000', icon: 'phone'),
    EmergencyContact(id: '2', label: 'City Hospital ER', phoneNumber: '+977-1-5550101', icon: 'hospital'),
  ];

  void _showProfileEditor() {
    final bloodController = TextEditingController(text: _profile.bloodGroup);
    final heightController = TextEditingController(text: _profile.heightCm?.toString() ?? '');
    final weightController = TextEditingController(text: _profile.weightKg?.toString() ?? '');
    final allergiesController = TextEditingController(text: _profile.allergies);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Update Medical ID', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ProfileField(controller: bloodController, label: 'Blood group'),
              const SizedBox(height: 12),
              ProfileField(controller: heightController, label: 'Height cm'),
              const SizedBox(height: 12),
              ProfileField(controller: weightController, label: 'Weight kg'),
              const SizedBox(height: 12),
              ProfileField(controller: allergiesController, label: 'Allergies'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _profile = MedicalProfile(
                        bloodGroup: bloodController.text.trim(),
                        heightCm: int.tryParse(heightController.text.trim()),
                        weightKg: double.tryParse(weightController.text.trim()),
                        allergies: allergiesController.text.trim(),
                        chronicConditions: _profile.chronicConditions,
                        currentMedications: _profile.currentMedications,
                        emergencyContactName: _profile.emergencyContactName,
                        emergencyContactPhone: _profile.emergencyContactPhone,
                        emergencyContactRelation: _profile.emergencyContactRelation,
                      );
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save medical ID'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          MedicalIdCard(profile: _profile, onEdit: _showProfileEditor),
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Emergency Contacts',
            subtitle: 'Saved locally for quick calling.',
            icon: Icons.contact_phone_outlined,
          ),
          const SizedBox(height: 12),
          ..._contacts.map(
            (contact) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EmergencyContactTile(contact: contact),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              subtitle: const Text('Sync, offline cache, and API options'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/emergency_contact.dart';
import '../models/medical_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/medical_profile_provider.dart';
import '../providers/emergency_contacts_provider.dart';
import '../widgets/emergency_contact_tile.dart';
import '../widgets/medical_id_card.dart';
import '../widgets/profile_field.dart';
import '../widgets/section_header.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  void _showContactEditor([EmergencyContact? contact]) {
    final labelController = TextEditingController(text: contact?.label ?? '');
    final phoneController = TextEditingController(text: contact?.phoneNumber ?? '');
    EmergencyContactIcon selectedIcon = contact?.icon ?? EmergencyContactIcon.phone;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact == null ? 'Add Emergency Contact' : 'Edit Emergency Contact', 
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  ProfileField(controller: labelController, label: 'Name'),
                  const SizedBox(height: 12),
                  ProfileField(controller: phoneController, label: 'Phone Number'),
                  const SizedBox(height: 12),
                  const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: EmergencyContactIcon.values.map((icon) {
                      return FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon.iconData, size: 16),
                            const SizedBox(width: 4),
                            Text(icon.name),
                          ],
                        ),
                        selected: selectedIcon == icon,
                        onSelected: (selected) {
                          setModalState(() {
                            selectedIcon = icon;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (contact == null) {
                              ref.read(emergencyContactsProvider.notifier).addContact(
                                labelController.text.trim(),
                                phoneController.text.trim(),
                                selectedIcon,
                              );
                            } else {
                              ref.read(emergencyContactsProvider.notifier).editContact(
                                contact.id,
                                labelController.text.trim(),
                                phoneController.text.trim(),
                                selectedIcon,
                              );
                            }
                            Navigator.of(context).pop();
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileEditor(MedicalProfile profile) {
    final heightController = TextEditingController(text: profile.heightCm?.toString() ?? '');
    final weightController = TextEditingController(text: profile.weightKg?.toString() ?? '');
    final allergiesController = TextEditingController(text: profile.allergies);
    String selectedBloodGroup = profile.bloodGroup.isEmpty ? 'O+' : profile.bloodGroup;
    final bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Update Medical ID', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  const Text('Blood Group', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: bloodGroups.map((group) {
                      return FilterChip(
                        label: Text(group),
                        selected: selectedBloodGroup == group,
                        onSelected: (selected) {
                          setModalState(() {
                            selectedBloodGroup = group;
                          });
                        },
                      );
                    }).toList(),
                  ),
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
                        final updatedProfile = MedicalProfile(
                          bloodGroup: selectedBloodGroup,
                          heightCm: int.tryParse(heightController.text.trim()),
                          weightKg: double.tryParse(weightController.text.trim()),
                          allergies: allergiesController.text.trim(),
                          chronicConditions: profile.chronicConditions,
                          currentMedications: profile.currentMedications,
                          emergencyContactName: profile.emergencyContactName,
                          emergencyContactPhone: profile.emergencyContactPhone,
                          emergencyContactRelation: profile.emergencyContactRelation,
                        );
                        ref.read(medicalProfileProvider.notifier).updateLocalProfile(updatedProfile);
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
      },
    );
  }

  void _showQRCode(MedicalProfile profile) {
    if (profile.shareToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share token not available. Please save your profile first.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Medical ID QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scan this QR code to access emergency medical information'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: profile.shareToken!,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Token: ${profile.shareToken}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(medicalProfileProvider);
    final contacts = ref.watch(emergencyContactsProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error loading profile: $error')),
        data: (profile) {
          if (profile.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No medical profile yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Add your medical information for emergencies'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => _showProfileEditor(profile),
                    child: const Text('Create Medical ID'),
                  ),
                ],
              ),
            );
          }
          
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              MedicalIdCard(profile: profile, onEdit: () => _showProfileEditor(profile)),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Emergency QR Code'),
                  subtitle: const Text('Share your medical ID with emergency responders'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showQRCode(profile),
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Emergency Contacts',
                subtitle: 'Saved locally for quick calling.',
                icon: Icons.contact_phone_outlined,
                action: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showContactEditor(),
                ),
              ),
              const SizedBox(height: 12),
              ...contacts.map(
                (contact) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EmergencyContactTile(
                    contact: contact,
                    onTap: () => _showContactEditor(contact),
                    onDelete: () {
                      ref.read(emergencyContactsProvider.notifier).deleteContact(contact.id);
                    },
                  ),
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
          );
        },
      ),
    );
  }
}

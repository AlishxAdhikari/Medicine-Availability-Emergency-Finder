import 'package:flutter/material.dart';
import '../state.dart';
import '../services/api_client.dart';
import '../services/medical_profile_service.dart';
import '../widgets/initials_avatar.dart';

class EditMedicalIdScreen extends StatefulWidget {
  const EditMedicalIdScreen({super.key});

  @override
  State<EditMedicalIdScreen> createState() => _EditMedicalIdScreenState();
}

class _EditMedicalIdScreenState extends State<EditMedicalIdScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _fullNameController;
  late TextEditingController _dobController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  final TextEditingController _newAllergyController = TextEditingController();
  final TextEditingController _newMedicationController = TextEditingController();

  List<String> _allergies = [];
  List<Medication> _medications = [];
  List<EmergencyContact> _contacts = [];
  String _selectedGender = 'Female';
  String _selectedBloodGroup = 'O+';
  bool _isSaving = false;

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    final profile = AppStateManager.instance.userProfileNotifier.value;
    
    _fullNameController = TextEditingController(text: profile.fullName);
    _dobController = TextEditingController(text: profile.dob);
    _phoneController = TextEditingController(text: profile.phoneNumber);
    _addressController = TextEditingController(text: profile.address);
    _heightController = TextEditingController(text: profile.height);
    _weightController = TextEditingController(text: profile.weight);
    _selectedGender = profile.gender.isNotEmpty ? profile.gender : 'Female';
    _selectedBloodGroup = _bloodGroups.contains(profile.bloodGroup) ? profile.bloodGroup : 'O+';

    _allergies = List.from(profile.allergies);
    _medications = List.from(profile.medications);
    _contacts = List.from(profile.emergencyContacts);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _newAllergyController.dispose();
    _newMedicationController.dispose();
    super.dispose();
  }

  void _addAllergy() {
    final text = _newAllergyController.text.trim();
    if (text.isNotEmpty && !_allergies.contains(text)) {
      setState(() {
        _allergies.add(text);
        _newAllergyController.clear();
      });
    }
  }

  void _removeAllergy(String allergy) {
    setState(() {
      _allergies.remove(allergy);
    });
  }

  void _addMedication() {
    final text = _newMedicationController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        // Simple parsing: separate name and dosage if possible, or just default dosage
        final parts = text.split(' ');
        final name = parts[0];
        final dosage = parts.length > 1 ? parts.sublist(1).join(' ') : 'as directed';
        _medications.add(Medication(
          name: name,
          dosage: dosage,
          frequency: 'Once Daily',
        ));
        _newMedicationController.clear();
      });
    }
  }

  void _removeMedication(int index) {
    setState(() {
      _medications.removeAt(index);
    });
  }

  void _addNewContact() {
    setState(() {
      _contacts.add(EmergencyContact(
        name: '',
        relationship: 'Friend',
        phoneNumber: '',
        initials: 'New',
      ));
    });
  }

  void _removeContact(int index) {
    setState(() {
      _contacts.removeAt(index);
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    setState(() => _isSaving = true);

    final currentProfile = AppStateManager.instance.userProfileNotifier.value;
    final updatedProfile = currentProfile.copyWith(
      fullName: _fullNameController.text,
      dob: _dobController.text,
      gender: _selectedGender,
      phoneNumber: _phoneController.text,
      address: _addressController.text,
      bloodGroup: _selectedBloodGroup,
      height: _heightController.text.trim(),
      weight: _weightController.text.trim(),
      allergies: _allergies,
      medications: _medications,
      emergencyContacts: _contacts,
    );

    try {
      // Persists blood group/height/weight/allergies/medications/phone and
      // the first emergency contact to the backend (PUT /medical-id/);
      // full name/dob/gender/address stay local-only since the backend's
      // MedicalProfile model doesn't have those fields.
      await MedicalProfileService.instance.save(updatedProfile);
      AppStateManager.instance.updateProfile(updatedProfile);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medical ID updated successfully'),
          backgroundColor: Color(0xFF00897B),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not save changes. Check your connection and try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF191C20) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: const Text('MedAlert'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {},
            color: theme.colorScheme.onSurfaceVariant,
          ),
          ValueListenableBuilder<UserProfile>(
            valueListenable: AppStateManager.instance.userProfileNotifier,
            builder: (context, profile, _) => InitialsAvatar(
              name: profile.fullName,
              imageUrl: profile.profilePictureUrl,
              radius: 16,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'Edit Medical ID',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Update your critical health information and emergency contacts.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Section 1: Personal Information
              _buildSectionCard(
                context,
                title: 'Personal Information',
                icon: Icons.person,
                children: [
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Full name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dobController,
                    decoration: const InputDecoration(
                      labelText: 'Date of Birth (YYYY-MM-DD)',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Date of birth is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Phone number is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      hintText: 'Used on your emergency QR code',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedBloodGroup,
                    decoration: const InputDecoration(
                      labelText: 'Blood Group',
                    ),
                    items: _bloodGroups
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedBloodGroup = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _heightController,
                          decoration: const InputDecoration(
                            labelText: 'Height (cm)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return null;
                            return double.tryParse(value.trim()) == null ? 'Enter a number' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          decoration: const InputDecoration(
                            labelText: 'Weight (kg)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return null;
                            return double.tryParse(value.trim()) == null ? 'Enter a number' : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedGender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                      DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedGender = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Section 2: Medical History
              _buildSectionCard(
                context,
                title: 'Medical History',
                icon: Icons.medical_information,
                children: [
                  // Allergies
                  Text(
                    'Allergies',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allergies.map((allergy) {
                      return Chip(
                        label: Text(allergy),
                        backgroundColor: const Color(0xFFFFDAD6).withValues(alpha: 0.4),
                        labelStyle: const TextStyle(color: Color(0xFFBA1A1A), fontWeight: FontWeight.bold),
                        deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFFBA1A1A)),
                        onDeleted: () => _removeAllergy(allergy),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newAllergyController,
                          decoration: const InputDecoration(
                            hintText: 'Add an allergy...',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addAllergy,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Medications
                  Text(
                    'Current Medications',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(_medications.length, (index) {
                      final med = _medications[index];
                      return Chip(
                        label: Text('${med.name} ${med.dosage}'),
                        backgroundColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
                        labelStyle: TextStyle(color: theme.colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold),
                        deleteIcon: Icon(Icons.close, size: 14, color: theme.colorScheme.onSecondaryContainer),
                        onDeleted: () => _removeMedication(index),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newMedicationController,
                          decoration: const InputDecoration(
                            hintText: 'Add medication (e.g. Metformin 500mg)...',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addMedication,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Section 3: Emergency Contacts
              _buildSectionCard(
                context,
                title: 'Emergency Contacts',
                icon: Icons.contacts,
                trailing: TextButton.icon(
                  onPressed: _addNewContact,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add New', style: TextStyle(fontSize: 12)),
                ),
                children: [
                  Column(
                    children: List.generate(_contacts.length, (index) {
                      final contact = _contacts[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF15181C) : const Color(0xFFF9F9FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Contact #${index + 1}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20, color: Color(0xFFBA1A1A)),
                                  onPressed: () => _removeContact(index),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: contact.name,
                              decoration: const InputDecoration(labelText: 'Name'),
                              onChanged: (val) {
                                _contacts[index] = contact.copyWith(name: val, initials: val.isNotEmpty ? val.substring(0, val.length > 2 ? 2 : val.length).toUpperCase() : '');
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Name is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: ['Spouse', 'Parent', 'Sibling', 'Friend'].contains(contact.relationship) ? contact.relationship : 'Friend',
                              decoration: const InputDecoration(labelText: 'Relationship'),
                              items: const [
                                DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
                                DropdownMenuItem(value: 'Parent', child: Text('Parent')),
                                DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                                DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  _contacts[index] = contact.copyWith(relationship: val);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: contact.phoneNumber,
                              decoration: const InputDecoration(labelText: 'Phone Number'),
                              keyboardType: TextInputType.phone,
                              onChanged: (val) {
                                _contacts[index] = contact.copyWith(phoneNumber: val);
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Phone number is required';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isDark ? Colors.black : Colors.white,
                              ),
                            )
                          : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D2024) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              ?trailing,
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }
}
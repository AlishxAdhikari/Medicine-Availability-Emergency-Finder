import 'package:flutter/material.dart';
import '../state.dart';

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
  final TextEditingController _newAllergyController = TextEditingController();
  final TextEditingController _newMedicationController = TextEditingController();

  List<String> _allergies = [];
  List<Medication> _medications = [];
  List<EmergencyContact> _contacts = [];
  String _selectedGender = 'Female';

  @override
  void initState() {
    super.initState();
    final profile = AppStateManager.instance.userProfileNotifier.value;
    
    _fullNameController = TextEditingController(text: profile.fullName);
    _dobController = TextEditingController(text: profile.dob);
    _phoneController = TextEditingController(text: profile.phoneNumber);
    _selectedGender = profile.gender;
    
    _allergies = List.from(profile.allergies);
    _medications = List.from(profile.medications);
    _contacts = List.from(profile.emergencyContacts);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
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

  void _saveChanges() {
    if (_formKey.currentState!.validate()) {
      final currentProfile = AppStateManager.instance.userProfileNotifier.value;
      final updatedProfile = currentProfile.copyWith(
        fullName: _fullNameController.text,
        dob: _dobController.text,
        gender: _selectedGender,
        phoneNumber: _phoneController.text,
        allergies: _allergies,
        medications: _medications,
        emergencyContacts: _contacts,
      );
      
      AppStateManager.instance.updateProfile(updatedProfile);
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medical ID updated successfully'),
          backgroundColor: Color(0xFF00897B),
        ),
      );
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
          const CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuBscqWBCgTBCJQkde59nPVfutHGh9P47nmalT5zHHIJy75_hN0xrGt3_FJ7Sngx_jm9bOOGe7csaFWGmDq2wZ2h2YynH3qZokHtTV952WhzVqCQlYMFl1OVwvydOO6FjYZb8oB3tmW6ykSHrS9SXxfJPSVi9Py-4SOZ_b4h7GollXk0oLAdBDn4HvAW4rNPWLfbQ6GcPFyJy_B3i0FAXs7N7XMT1BtvN3CdYeeAMhtQFNinRUf941n6WPt9ptKtQGTI5IYrqP8Q74H5',
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
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
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

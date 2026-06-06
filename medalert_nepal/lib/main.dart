import 'package:flutter/material.dart';
import 'package:medalert_nepal/widgets/identity_workspace_card.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MedAlert Nepal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _medicineSearchController = TextEditingController();
  final TextEditingController _bloodBankSearchController = TextEditingController();

  final List<Map<String, String>> _medicineInventory = [
    {'name': 'Paracetamol 500mg', 'purpose': 'Fever & pain relief', 'status': 'Available'},
    {'name': 'Amoxicillin 250mg', 'purpose': 'Common antibiotic', 'status': 'Low Stock'},
    {'name': 'Salbutamol Inhaler', 'purpose': 'Asthma support', 'status': 'Out of Stock'},
    {'name': 'ORS Sachet', 'purpose': 'Hydration support', 'status': 'Available'},
  ];

  final List<Map<String, String>> _emergencyContacts = [
    {'label': '24/7 Ambulance', 'value': '102'},
    {'label': 'City Hospital ER', 'value': '+977-1-5550101'},
    {'label': 'Night Pharmacy', 'value': '+977-1-5550144'},
    {'label': 'Nearby Trauma Center', 'value': '+977-1-5550199'},
  ];

  final List<Map<String, String>> _bloodBanks = [
    {'name': 'Nepal Red Cross Blood Bank', 'area': 'Central', 'blood': 'A+, O+, B+'},
    {'name': 'Maharajgunj Blood Center', 'area': 'North', 'blood': 'O+, O-, AB+'},
    {'name': 'Lalitpur Community Blood Bank', 'area': 'South', 'blood': 'A+, B-, O-'},
    {'name': 'Bhaktapur Blood Depot', 'area': 'East', 'blood': 'B+, AB-, O+'},
  ];

  final Map<String, String> _medicalId = {
    'name': 'Aarav Shrestha',
    'bloodGroup': 'O+',
    'height': '171 cm',
    'weight': '68 kg',
    'allergies': 'Penicillin',
    'condition': 'Needs quick access to inhaler during asthma episodes',
  };

  final List<String> _statusOrder = const ['Available', 'Low Stock', 'Out of Stock'];

  String _selectedArea = 'All';

  @override
  void dispose() {
    _medicineSearchController.dispose();
    _bloodBankSearchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filteredMedicines {
    final query = _medicineSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _medicineInventory;
    }
    return _medicineInventory.where((medicine) {
      return medicine['name']!.toLowerCase().contains(query) ||
          medicine['purpose']!.toLowerCase().contains(query);
    }).toList();
  }

  List<Map<String, String>> get _filteredBloodBanks {
    final query = _bloodBankSearchController.text.trim().toLowerCase();
    return _bloodBanks.where((bank) {
      final matchesQuery = query.isEmpty ||
          bank['name']!.toLowerCase().contains(query) ||
          bank['blood']!.toLowerCase().contains(query);
      final matchesArea = _selectedArea == 'All' || bank['area'] == _selectedArea;
      return matchesQuery && matchesArea;
    }).toList();
  }

  void _updateMedicineStatus(String medicineName, String status) {
    setState(() {
      final index = _medicineInventory.indexWhere((medicine) => medicine['name'] == medicineName);
      if (index != -1) {
        _medicineInventory[index] = {
          ..._medicineInventory[index],
          'status': status,
        };
      }
    });
  }

  void _showProfileEditor() {
    final bloodController = TextEditingController(text: _medicalId['bloodGroup']);
    final heightController = TextEditingController(text: _medicalId['height']);
    final weightController = TextEditingController(text: _medicalId['weight']);
    final allergiesController = TextEditingController(text: _medicalId['allergies']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Update Medical ID', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _ProfileField(controller: bloodController, label: 'Blood group'),
              const SizedBox(height: 12),
              _ProfileField(controller: heightController, label: 'Height'),
              const SizedBox(height: 12),
              _ProfileField(controller: weightController, label: 'Weight'),
              const SizedBox(height: 12),
              _ProfileField(controller: allergiesController, label: 'Allergies'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _medicalId['bloodGroup'] = bloodController.text.trim();
                      _medicalId['height'] = heightController.text.trim();
                      _medicalId['weight'] = weightController.text.trim();
                      _medicalId['allergies'] = allergiesController.text.trim();
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

  Widget _sectionHeader(String title, String subtitle, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Available':
        return const Color(0xFF0F766E);
      case 'Low Stock':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFB91C1C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8FAFC), Color(0xFFE0F2F1)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MedAlert Nepal',
                                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Offline-ready medicine, emergency and blood bank access.',
                                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Local demo data',
                              style: theme.textTheme.labelLarge?.copyWith(color: colors.onPrimary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _StatTile(label: 'Medicines tracked', value: '4'),
                          _StatTile(label: 'Emergency contacts', value: '4'),
                          _StatTile(label: 'Blood banks', value: '4'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: const IdentityWorkspaceCard(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Card(
                    elevation: 0,
                    color: colors.surface.withOpacity(0.94),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(
                            'Medicine Availability Tracker',
                            'Critical medicines with simple availability toggles for partner pharmacy demos.',
                            Icons.medication_outlined,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('medicine-search-field'),
                            controller: _medicineSearchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Search medicine or use case',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._filteredMedicines.map((medicine) {
                            final status = medicine['status']!;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                medicine['name']!,
                                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                medicine['purpose']!,
                                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status).withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            status,
                                            style: theme.textTheme.labelLarge?.copyWith(color: _statusColor(status)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _statusOrder.map((option) {
                                        final selected = option == status;
                                        return ChoiceChip(
                                          label: Text(option),
                                          selected: selected,
                                          onSelected: (_) => _updateMedicineStatus(medicine['name']!, option),
                                          selectedColor: _statusColor(option).withOpacity(0.18),
                                          labelStyle: theme.textTheme.labelLarge?.copyWith(
                                            color: selected ? _statusColor(option) : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          side: BorderSide(color: selected ? _statusColor(option) : const Color(0xFFD1D5DB)),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (_filteredMedicines.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No medicines match your search.'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Card(
                    elevation: 0,
                    color: colors.surface.withOpacity(0.94),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(
                            'Medical ID & Emergency Contacts',
                            'The profile doubles as a digital medical ID and keeps local contacts ready offline.',
                            Icons.badge_outlined,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _medicalId['name']!,
                                  style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _MedicalBadge(label: 'Blood', value: _medicalId['bloodGroup']!),
                                    _MedicalBadge(label: 'Height', value: _medicalId['height']!),
                                    _MedicalBadge(label: 'Weight', value: _medicalId['weight']!),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Allergies: ${_medicalId['allergies']!}',
                                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _medicalId['condition']!,
                                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _showProfileEditor,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white70),
                                    ),
                                    child: const Text('Edit medical ID'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._emergencyContacts.map((contact) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: colors.primaryContainer,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(Icons.contact_phone_outlined, color: colors.onPrimaryContainer),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            contact['label']!,
                                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            contact['value']!,
                                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {},
                                      icon: const Icon(Icons.call_outlined),
                                      tooltip: 'Call contact',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Card(
                    elevation: 0,
                    color: colors.surface.withOpacity(0.94),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(
                            'Blood Bank Finder',
                            'Search blood group availability using the same location logic as the pharmacy module.',
                            Icons.water_drop_outlined,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _bloodBankSearchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Search blood group or bank',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: ['All', 'North', 'Central', 'South', 'East'].map((area) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(area),
                                    selected: _selectedArea == area,
                                    onSelected: (_) => setState(() => _selectedArea = area),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._filteredBloodBanks.map((bank) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDBEAFE),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Icon(Icons.local_hospital_outlined, color: Color(0xFF1D4ED8)),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            bank['name']!,
                                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Area: ${bank['area']!}',
                                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Blood groups: ${bank['blood']!}',
                                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black87),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (_filteredBloodBanks.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No blood banks match this search or area filter.'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _MedicalBadge extends StatelessWidget {
  const _MedicalBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/medicine_card.dart';
import '../widgets/search_bar_widget.dart';

class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'All';

  final _medicines = [
    Medicine(
      id: 1,
      name: 'Paracetamol',
      genericName: 'Acetaminophen',
      brandName: 'Niko',
      dosageForm: 'Tablet',
      strength: '500mg',
      description: 'Fever and pain relief.',
      isEssential: true,
      requiresPrescription: false,
    ),
    Medicine(
      id: 2,
      name: 'Amoxicillin',
      genericName: 'Amoxicillin',
      brandName: 'Mox',
      category: 2,
      dosageForm: 'Capsule',
      strength: '250mg',
      description: 'Common antibiotic.',
      isEssential: true,
      requiresPrescription: true,
    ),
    Medicine(
      id: 3,
      name: 'Salbutamol',
      genericName: 'Albuterol',
      brandName: 'Asthalin',
      category: 3,
      dosageForm: 'Inhaler',
      strength: '100mcg',
      description: 'Asthma rescue inhaler.',
      isEssential: true,
      requiresPrescription: true,
    ),
    Medicine(
      id: 4,
      name: 'ORS Sachet',
      genericName: 'Oral rehydration salts',
      brandName: 'Jeevan Jal',
      category: 4,
      dosageForm: 'Powder',
      strength: '20.5g',
      description: 'Hydration support.',
      isEssential: true,
      requiresPrescription: false,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Medicine> get _filteredMedicines {
    final query = _searchController.text.trim().toLowerCase();
    return _medicines.where((medicine) {
      final category = medicine.dosageForm;
      final matchesCategory = _selectedCategory == 'All' || category == _selectedCategory;
      final matchesQuery = query.isEmpty ||
          medicine.name.toLowerCase().contains(query) ||
          medicine.genericName.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medicines')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          SearchBarWidget(
            key: const Key('medicine-search-field'),
            controller: _searchController,
            hintText: 'Search medicine or generic name',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          FilterChipBar<String>(
            items: const ['All', 'Tablet', 'Capsule', 'Inhaler', 'Powder'],
            selectedItem: _selectedCategory,
            labelBuilder: (item) => item,
            onSelected: (item) => setState(() => _selectedCategory = item),
          ),
          const SizedBox(height: 12),
          if (_filteredMedicines.isEmpty)
            const _EmptyMessage(message: 'No medicines match this search.')
          else
            ..._filteredMedicines.map(
              (medicine) => MedicineCard(
                medicine: medicine,
                availability: medicine.id == 3 ? 'out_of_stock' : medicine.id == 2 ? 'low_stock' : 'available',
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
      ),
    );
  }
}

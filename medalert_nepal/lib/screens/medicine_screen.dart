import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../providers/medicine_provider.dart';
import '../services/api_client.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/medicine_card.dart';
import '../widgets/search_bar_widget.dart';
import 'pharmacy_stock_screen.dart';

class MedicineScreen extends ConsumerStatefulWidget {
  const MedicineScreen({super.key});

  @override
  ConsumerState<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends ConsumerState<MedicineScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(medicineSearchQueryProvider.notifier).state = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Medicine> get _filteredMedicines {
    final medicinesAsync = ref.watch(medicinesProvider);
    final query = _searchController.text.trim().toLowerCase();
    
    if (medicinesAsync.isLoading || !medicinesAsync.hasValue) {
      return [];
    }

    return medicinesAsync.value!.where((medicine) {
      final categoryDetail = medicine.categoryDetail?.name ?? '';
      final matchesCategory = _selectedCategory == 'All' || categoryDetail == _selectedCategory;
      final matchesQuery = query.isEmpty ||
          medicine.name.toLowerCase().contains(query) ||
          medicine.genericName.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final medicinesAsync = ref.watch(medicinesProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    
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
          categoriesAsync.when(
            loading: () => const SizedBox(height: 40),
            error: (_, __) => const SizedBox.shrink(),
            data: (categories) {
              final categoryNames = ['All', ...categories.map((c) => c.name)];
              return FilterChipBar<String>(
                items: categoryNames,
                selectedItem: _selectedCategory,
                labelBuilder: (item) => item,
                onSelected: (item) => setState(() => _selectedCategory = item),
              );
            },
          ),
          const SizedBox(height: 12),
          if (medicinesAsync.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (medicinesAsync.hasError)
            _EmptyMessage(
              message: medicinesAsync.error is ApiException 
                ? (medicinesAsync.error as ApiException).message 
                : 'Error loading medicines',
            )
          else if (_filteredMedicines.isEmpty)
            const _EmptyMessage(message: 'No medicines match this search.')
          else
            ..._filteredMedicines.map(
              (medicine) => MedicineCard(
                medicine: medicine,
                availability: medicine.id == 3 ? 'out_of_stock' : medicine.id == 2 ? 'low_stock' : 'available',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PharmacyStockScreen(medicine: medicine),
                    ),
                  );
                },
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ambulance.dart';
import '../providers/ambulance_provider.dart';
import '../services/api_client.dart';
import '../widgets/ambulance_card.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/search_bar_widget.dart';

class AmbulanceScreen extends ConsumerStatefulWidget {
  const AmbulanceScreen({super.key});

  @override
  ConsumerState<AmbulanceScreen> createState() => _AmbulanceScreenState();
}

class _AmbulanceScreenState extends ConsumerState<AmbulanceScreen> {
  final _searchController = TextEditingController();
  String _selectedType = 'All';
  bool _icuOnly = false;
  bool _oxygenOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(ambulanceSearchQueryProvider.notifier).state = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AmbulanceProvider> get _filteredProviders {
    final ambulancesAsync = ref.watch(ambulancesProvider);
    final query = _searchController.text.trim().toLowerCase();
    
    if (ambulancesAsync.isLoading || !ambulancesAsync.hasValue) {
      return [];
    }

    return ambulancesAsync.value!.where((provider) {
      final matchesQuery = query.isEmpty ||
          provider.hospitalName.toLowerCase().contains(query) ||
          provider.address.toLowerCase().contains(query);
      final matchesType = _selectedType == 'All' || provider.serviceType == _selectedType.toLowerCase();
      final matchesIcu = !_icuOnly || provider.hasIcu;
      final matchesOxygen = !_oxygenOnly || provider.hasOxygen;
      return matchesQuery && matchesType && matchesIcu && matchesOxygen;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ambulancesAsync = ref.watch(ambulancesProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Ambulances')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          SearchBarWidget(
            controller: _searchController,
            hintText: 'Search provider or area',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          FilterChipBar<String>(
            items: const ['All', 'Government', 'Private', 'NGO'],
            selectedItem: _selectedType,
            labelBuilder: (item) => item,
            onSelected: (item) => setState(() => _selectedType = item),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('ICU'),
                selected: _icuOnly,
                onSelected: (selected) => setState(() => _icuOnly = selected),
              ),
              FilterChip(
                label: const Text('Oxygen'),
                selected: _oxygenOnly,
                onSelected: (selected) => setState(() => _oxygenOnly = selected),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (ambulancesAsync.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (ambulancesAsync.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  ambulancesAsync.error is ApiException 
                    ? (ambulancesAsync.error as ApiException).message 
                    : 'Error loading ambulances',
                ),
              ),
            )
          else if (_filteredProviders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No ambulance providers match this filter.')),
            )
          else
            ..._filteredProviders.map((provider) => AmbulanceCard(ambulance: provider)),
        ],
      ),
    );
  }
}

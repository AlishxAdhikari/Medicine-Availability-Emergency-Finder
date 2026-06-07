import 'package:flutter/material.dart';

import '../models/ambulance.dart';
import '../widgets/ambulance_card.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/search_bar_widget.dart';

class AmbulanceScreen extends StatefulWidget {
  const AmbulanceScreen({super.key});

  @override
  State<AmbulanceScreen> createState() => _AmbulanceScreenState();
}

class _AmbulanceScreenState extends State<AmbulanceScreen> {
  final _searchController = TextEditingController();
  String _selectedType = 'All';
  bool _icuOnly = false;
  bool _oxygenOnly = false;

  final _providers = [
    AmbulanceProvider(
      id: 1,
      hospitalName: 'Bir Hospital',
      serviceType: 'government',
      contactNumber: '102',
      address: 'Mahaboudha, Kathmandu',
      district: 'Kathmandu',
      isActive: true,
      is24h: true,
      hasIcu: true,
      hasOxygen: true,
      notes: 'Central emergency response desk.',
    ),
    AmbulanceProvider(
      id: 2,
      hospitalName: 'Patan Hospital',
      serviceType: 'government',
      contactNumber: '+977-1-5522278',
      address: 'Lagankhel, Lalitpur',
      district: 'Lalitpur',
      isActive: true,
      is24h: true,
      hasIcu: false,
      hasOxygen: true,
      notes: 'Oxygen support available.',
    ),
    AmbulanceProvider(
      id: 3,
      hospitalName: 'Helping Hands Clinic',
      serviceType: 'ngo',
      contactNumber: '+977-1-5550199',
      address: 'Chabahil, Kathmandu',
      district: 'Kathmandu',
      isActive: true,
      is24h: false,
      hasIcu: false,
      hasOxygen: false,
      notes: 'Daytime community service.',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AmbulanceProvider> get _filteredProviders {
    final query = _searchController.text.trim().toLowerCase();
    return _providers.where((provider) {
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
          ..._filteredProviders.map((provider) => AmbulanceCard(ambulance: provider)),
          if (_filteredProviders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No ambulance providers match this filter.')),
            ),
        ],
      ),
    );
  }
}

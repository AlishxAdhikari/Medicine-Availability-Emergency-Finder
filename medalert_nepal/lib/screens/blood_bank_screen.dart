import 'package:flutter/material.dart';

import '../models/blood_bank.dart';
import '../widgets/blood_bank_card.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/search_bar_widget.dart';

class BloodBankScreen extends StatefulWidget {
  const BloodBankScreen({super.key});

  @override
  State<BloodBankScreen> createState() => _BloodBankScreenState();
}

class _BloodBankScreenState extends State<BloodBankScreen> {
  final _searchController = TextEditingController();
  String _selectedGroup = 'All';

  final _bloodBanks = [
    BloodBank(
      id: 1,
      name: 'Nepal Red Cross Blood Bank',
      address: 'Kalimati, Kathmandu',
      district: 'Kathmandu',
      phone: '+977-1-4270650',
      isActive: true,
      is24h: true,
      bloodStocks: [
        BloodStock(id: 1, bloodGroup: 'A+', stockLevel: 'adequate', unitsAvailable: 18, notes: ''),
        BloodStock(id: 2, bloodGroup: 'O+', stockLevel: 'low', unitsAvailable: 4, notes: ''),
        BloodStock(id: 3, bloodGroup: 'AB-', stockLevel: 'critical', unitsAvailable: 1, notes: ''),
      ],
    ),
    BloodBank(
      id: 2,
      name: 'Maharajgunj Blood Center',
      address: 'Maharajgunj, Kathmandu',
      district: 'Kathmandu',
      phone: '+977-1-4412303',
      isActive: true,
      is24h: false,
      bloodStocks: [
        BloodStock(id: 4, bloodGroup: 'B+', stockLevel: 'adequate', unitsAvailable: 12, notes: ''),
        BloodStock(id: 5, bloodGroup: 'O-', stockLevel: 'low', unitsAvailable: 3, notes: ''),
      ],
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BloodBank> get _filteredBanks {
    final query = _searchController.text.trim().toLowerCase();
    return _bloodBanks.where((bank) {
      final matchesQuery = query.isEmpty ||
          bank.name.toLowerCase().contains(query) ||
          bank.address.toLowerCase().contains(query);
      final matchesGroup = _selectedGroup == 'All' ||
          bank.bloodStocks.any((stock) => stock.bloodGroup == _selectedGroup);
      return matchesQuery && matchesGroup;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blood Banks')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          SearchBarWidget(
            controller: _searchController,
            hintText: 'Search bank or area',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          FilterChipBar<String>(
            items: const ['All', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
            selectedItem: _selectedGroup,
            labelBuilder: (item) => item,
            onSelected: (item) => setState(() => _selectedGroup = item),
          ),
          const SizedBox(height: 12),
          ..._filteredBanks.map((bank) => BloodBankCard(bloodBank: bank)),
          if (_filteredBanks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No blood banks match this filter.')),
            ),
        ],
      ),
    );
  }
}

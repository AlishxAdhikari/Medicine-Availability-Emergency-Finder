import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/blood_bank.dart';
import '../providers/blood_bank_provider.dart';
import '../services/api_client.dart';
import '../widgets/blood_bank_card.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/search_bar_widget.dart';

class BloodBankScreen extends ConsumerStatefulWidget {
  const BloodBankScreen({super.key});

  @override
  ConsumerState<BloodBankScreen> createState() => _BloodBankScreenState();
}

class _BloodBankScreenState extends ConsumerState<BloodBankScreen> {
  final _searchController = TextEditingController();
  String _selectedGroup = 'All';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(bloodBankSearchQueryProvider.notifier).state = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BloodBank> get _filteredBanks {
    final bloodBanksAsync = ref.watch(bloodBanksProvider);
    final query = _searchController.text.trim().toLowerCase();
    
    if (bloodBanksAsync.isLoading || !bloodBanksAsync.hasValue) {
      return [];
    }

    return bloodBanksAsync.value!.where((bank) {
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
    final bloodBanksAsync = ref.watch(bloodBanksProvider);
    
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
          if (bloodBanksAsync.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (bloodBanksAsync.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  bloodBanksAsync.error is ApiException 
                    ? (bloodBanksAsync.error as ApiException).message 
                    : 'Error loading blood banks',
                ),
              ),
            )
          else if (_filteredBanks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No blood banks match this filter.')),
            )
          else
            ..._filteredBanks.map((bank) => BloodBankCard(bloodBank: bank)),
        ],
      ),
    );
  }
}

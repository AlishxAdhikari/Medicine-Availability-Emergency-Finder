import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/medicine.dart';
import '../providers/medicine_provider.dart';
import '../services/api_client.dart';

class PharmacyStockScreen extends ConsumerWidget {
  final Medicine medicine;

  const PharmacyStockScreen({
    super.key,
    required this.medicine,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(medicineAvailabilityProvider(medicine.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('${medicine.name} Stock'),
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          final errorMessage = error is ApiException ? error.message : 'Error loading stock';
          return Center(child: Text(errorMessage));
        },
        data: (stocks) {
          if (stocks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No pharmacies stocking this medicine',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: stocks.length,
            itemBuilder: (context, index) {
              final stock = stocks[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: _buildAvailabilityIcon(stock.availability),
                  title: Text(stock.pharmacyDetail?.name ?? 'Unknown Pharmacy'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stock.pharmacyDetail?.address ?? ''),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (stock.priceNpr != null)
                            Text('Rs. ${stock.priceNpr?.toStringAsFixed(2)}', 
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (stock.quantityOnHand != null) ...[
                            const SizedBox(width: 8),
                            Text('${stock.quantityOnHand} in stock'),
                          ],
                        ],
                      ),
                    ],
                  ),
                  trailing: _buildAvailabilityChip(stock.availability),
                  onTap: () {
                    // TODO: Navigate to pharmacy details or call
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAvailabilityIcon(String availability) {
    switch (availability) {
      case 'available':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'low_stock':
        return const Icon(Icons.warning, color: Colors.orange);
      case 'out_of_stock':
        return const Icon(Icons.cancel, color: Colors.red);
      default:
        return const Icon(Icons.help_outline, color: Colors.grey);
    }
  }

  Widget _buildAvailabilityChip(String availability) {
    String label;
    Color color;

    switch (availability) {
      case 'available':
        label = 'Available';
        color = Colors.green;
        break;
      case 'low_stock':
        label = 'Low Stock';
        color = Colors.orange;
        break;
      case 'out_of_stock':
        label = 'Out of Stock';
        color = Colors.red;
        break;
      default:
        label = 'Unknown';
        color = Colors.grey;
    }

    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(color: color),
    );
  }
}

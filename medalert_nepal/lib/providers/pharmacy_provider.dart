import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/pharmacy_service.dart';
import '../models/pharmacy.dart';
import '../models/medicine.dart';

final pharmacyServiceProvider = Provider<PharmacyService>((ref) => PharmacyService());

final pharmacySearchQueryProvider = StateProvider<String>((ref) => '');
final pharmacyDistrictProvider = StateProvider<String>((ref) => 'All');

final pharmaciesProvider = FutureProvider<List<Pharmacy>>((ref) async {
  final service = ref.watch(pharmacyServiceProvider);
  final query = ref.watch(pharmacySearchQueryProvider);
  final district = ref.watch(pharmacyDistrictProvider);
  
  return service.getPharmacies(
    search: query,
    district: district == 'All' ? null : district,
  );
});

final pharmacyDetailProvider = FutureProvider.family<Pharmacy, int>((ref, id) async {
  final service = ref.watch(pharmacyServiceProvider);
  return service.getPharmacy(id);
});

final pharmacyStockProvider = FutureProvider.family<List<PharmacyMedicineStock>, int>((ref, id) async {
  final service = ref.watch(pharmacyServiceProvider);
  return service.getPharmacyStock(id);
});

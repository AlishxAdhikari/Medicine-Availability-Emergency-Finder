import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/medicine_service.dart';
import '../models/medicine.dart';
import 'location_provider.dart';

final medicineServiceProvider = Provider<MedicineService>((ref) => MedicineService());

final medicineSearchQueryProvider = StateProvider<String>((ref) => '');
final medicineCategoryProvider = StateProvider<int?>((ref) => null);

final medicinesProvider = FutureProvider<List<Medicine>>((ref) async {
  final service = ref.watch(medicineServiceProvider);
  final query = ref.watch(medicineSearchQueryProvider);
  final categoryId = ref.watch(medicineCategoryProvider);
  final locationState = ref.watch(locationProvider);

  return service.getMedicines(
    search: query,
    categoryId: categoryId,
    lat: locationState.position?.latitude,
    lon: locationState.position?.longitude,
  );
});

final categoriesProvider = FutureProvider<List<MedicineCategory>>((ref) async {
  final service = ref.watch(medicineServiceProvider);
  return service.getCategories();
});

final medicineAvailabilityProvider = FutureProvider.family<List<PharmacyMedicineStock>, int>((ref, medicineId) async {
  final service = ref.watch(medicineServiceProvider);
  return service.getMedicineAvailability(medicineId);
});

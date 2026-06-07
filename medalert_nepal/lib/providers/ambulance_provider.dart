import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ambulance_service.dart';
import '../models/ambulance.dart';

final ambulanceServiceProvider = Provider<AmbulanceService>((ref) => AmbulanceService());

final ambulanceSearchQueryProvider = StateProvider<String>((ref) => '');
final ambulanceServiceTypeProvider = StateProvider<String>((ref) => 'All');
final ambulanceDistrictProvider = StateProvider<String>((ref) => 'All');
final ambulanceHasIcuProvider = StateProvider<bool>((ref) => false);
final ambulanceHasOxygenProvider = StateProvider<bool>((ref) => false);

final ambulancesProvider = FutureProvider<List<AmbulanceProvider>>((ref) async {
  final service = ref.watch(ambulanceServiceProvider);
  final query = ref.watch(ambulanceSearchQueryProvider);
  final serviceType = ref.watch(ambulanceServiceTypeProvider);
  final district = ref.watch(ambulanceDistrictProvider);
  final hasIcu = ref.watch(ambulanceHasIcuProvider);
  final hasOxygen = ref.watch(ambulanceHasOxygenProvider);

  return service.getAmbulanceProviders(
    search: query,
    serviceType: serviceType == 'All' ? null : serviceType,
    district: district == 'All' ? null : district,
    hasIcu: hasIcu,
    hasOxygen: hasOxygen,
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/blood_bank_service.dart';
import '../models/blood_bank.dart';

final bloodBankServiceProvider = Provider<BloodBankService>((ref) => BloodBankService());

final bloodBankSearchQueryProvider = StateProvider<String>((ref) => '');
final bloodBankDistrictProvider = StateProvider<String>((ref) => 'All');
final bloodBankGroupProvider = StateProvider<String>((ref) => 'All');

final bloodBanksProvider = FutureProvider<List<BloodBank>>((ref) async {
  final service = ref.watch(bloodBankServiceProvider);
  final query = ref.watch(bloodBankSearchQueryProvider);
  final district = ref.watch(bloodBankDistrictProvider);
  final bloodGroup = ref.watch(bloodBankGroupProvider);

  return service.getBloodBanks(
    search: query,
    district: district == 'All' ? null : district,
    bloodGroup: bloodGroup == 'All' ? null : bloodGroup,
  );
});

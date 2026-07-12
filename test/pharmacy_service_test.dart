import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/pharmacy_service.dart';

const _runBackendTests = bool.fromEnvironment('RUN_BACKEND_TESTS', defaultValue: false);

void main() {
  test('pharmacy search returns results from the backend', () async {
    final results = await PharmacyService.instance.search(query: 'Kathmandu');

    expect(results, isNotEmpty);
    expect(results.any((pharmacy) => pharmacy.name.isNotEmpty), isTrue);
  }, skip: !_runBackendTests);
}

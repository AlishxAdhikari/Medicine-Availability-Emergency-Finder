import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/pharmacy_service.dart';

void main() {
  test('pharmacy search returns results from the backend', () async {
    final results = await PharmacyService.instance.search(query: 'Kathmandu');

    expect(results, isNotEmpty);
    expect(results.any((pharmacy) => pharmacy.name.isNotEmpty), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/screens/owner_dashboard_screen.dart';

// Pure-helper tests only. The screen itself can't be pumped in a widget test:
// OwnerStockService/PharmacyService both hang off ApiClient.instance, an
// uninjectable singleton, which is the same reason pharmacy_service_test.dart
// is gated behind RUN_BACKEND_TESTS.
void main() {
  group('priceHasChanged', () {
    test('reports no change when the same number is spelled differently', () {
      // The phantom-write case: DRF sends "10.50", the owner types "10.5".
      expect(priceHasChanged('10.50', '10.5'), isFalse);
      expect(priceHasChanged('10.5', '10.50'), isFalse);
      expect(priceHasChanged('10', '10.00'), isFalse);
      expect(priceHasChanged('0.00', '0'), isFalse);
    });

    test('ignores surrounding whitespace', () {
      expect(priceHasChanged('10.50', '  10.50  '), isFalse);
    });

    test('reports a change when the value really differs', () {
      expect(priceHasChanged('10.50', '10.55'), isTrue);
      expect(priceHasChanged('10.50', '9.50'), isTrue);
      // The inverse of the phantom write: a real edit that a string compare
      // would also catch, kept so the numeric path can't over-collapse.
      expect(priceHasChanged('0.00', '0.01'), isTrue);
    });

    test('falls back to a string compare when a side will not parse', () {
      // Neither side is dropped silently -- an unparseable edit still goes to
      // the server, which is the only thing that can rule on it.
      expect(priceHasChanged('10.50', 'abc'), isTrue);
      expect(priceHasChanged('abc', 'abc'), isFalse);
      expect(priceHasChanged('', '10.50'), isTrue);
    });
  });

  group('validateQuantity', () {
    test('accepts a whole number', () {
      expect(validateQuantity('0'), isNull);
      expect(validateQuantity('12'), isNull);
      expect(validateQuantity(' 12 '), isNull);
    });

    test('rejects text rather than silently treating it as 0', () {
      // The bug this replaces: `int.tryParse('abc') ?? 0` wrote a real stock
      // quantity of zero, and `if (quantity != null)` wrote nothing at all
      // with no message either way.
      expect(validateQuantity('abc'), isNotNull);
      expect(validateQuantity('1.5'), isNotNull);
      expect(validateQuantity(''), isNotNull);
      expect(validateQuantity(null), isNotNull);
    });

    test('rejects a negative count', () {
      expect(validateQuantity('-1'), isNotNull);
    });
  });

  group('validatePrice', () {
    test('accepts a decimal amount', () {
      expect(validatePrice('0'), isNull);
      expect(validatePrice('10.50'), isNull);
      expect(validatePrice(' 10.5 '), isNull);
    });

    test('rejects text and negatives', () {
      expect(validatePrice('abc'), isNotNull);
      expect(validatePrice(''), isNotNull);
      expect(validatePrice(null), isNotNull);
      expect(validatePrice('-0.01'), isNotNull);
    });
  });
}

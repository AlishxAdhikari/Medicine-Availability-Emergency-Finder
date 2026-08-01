import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/screens/owner_dashboard_screen.dart';
import 'package:medalert/services/api_client.dart';

// Pure-helper tests only. The screen itself can't be pumped in a widget test:
// OwnerStockService/PharmacyService both hang off ApiClient.instance, an
// uninjectable singleton, which is the same reason pharmacy_service_test.dart
// is gated behind RUN_BACKEND_TESTS.
void main() {
  group('validateLowThreshold', () {
    test('accepts a whole number, including zero', () {
      expect(validateLowThreshold('25'), isNull);
      // "Only tell me when it runs out" is a legitimate setting, not an error.
      expect(validateLowThreshold('0'), isNull);
      expect(validateLowThreshold('  7 '), isNull);
    });

    test('accepts blank, which means leave the threshold alone', () {
      // The add dialog sends no low_threshold at all when this is empty, so
      // the server default stands; the edit dialog treats it as unchanged.
      expect(validateLowThreshold(''), isNull);
      expect(validateLowThreshold(null), isNull);
      expect(validateLowThreshold('   '), isNull);
    });

    test('rejects text and negatives rather than silently sending them', () {
      expect(validateLowThreshold('ten'), isNotNull);
      expect(validateLowThreshold('2.5'), isNotNull);
      expect(validateLowThreshold('-1'), isNotNull);
    });
  });

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

  group('isOwnershipRevoked', () {
    test('is true only for a 403 ApiException', () {
      // IsPharmacyOwner denies every method on OwnerStockViewSet, so any of
      // _editRow / _removeRow / addMedicine can see this, not just the
      // initial load.
      expect(isOwnershipRevoked(ApiException(403, 'no permission')), isTrue);
    });

    test('is false for every other status', () {
      // 400 is a rejected edit, 404 a double-tapped remove, 500 a server
      // fault -- all of them stay row errors on a dashboard that still works.
      expect(isOwnershipRevoked(ApiException(400, 'bad')), isFalse);
      expect(isOwnershipRevoked(ApiException(401, 'unauthorized')), isFalse);
      expect(isOwnershipRevoked(ApiException(404, 'gone')), isFalse);
      expect(isOwnershipRevoked(ApiException(500, 'boom')), isFalse);
    });

    test('is false for a non-ApiException failure', () {
      // A dropped connection is not a revoked role; ejecting the owner for
      // one would be a far worse bug than the one this guards.
      expect(isOwnershipRevoked(Exception('socket')), isFalse);
      expect(isOwnershipRevoked(StateError('paginated payload')), isFalse);
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

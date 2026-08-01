import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/owner_stock_service.dart';

void main() {
  group('OwnerStock.fromJson', () {
    test('maps the nested medicine shape from OwnerStockSerializer', () {
      final stock = OwnerStock.fromJson({
        'id': 3,
        'medicine': {'id': 11, 'name': 'Paracetamol 500mg'},
        'quantity': 42,
        'price': '10.50',
        'low_threshold': 10,
      });

      expect(stock.id, 3);
      expect(stock.medicineId, 11);
      expect(stock.medicineName, 'Paracetamol 500mg');
      expect(stock.quantity, 42);
      expect(stock.price, '10.50');
      expect(stock.lowThreshold, 10);
    });

    test('reads low_threshold strictly rather than assuming the default', () {
      // Unlike price, this one is editable: the edit dialog pre-fills it and
      // PATCHes back what it holds. Defaulting an absent key to 10 would mean
      // an owner who runs a 500-box threshold could silently overwrite it with
      // a number this client made up.
      final stock = OwnerStock.fromJson({
        'id': 6,
        'medicine': {'id': 14, 'name': 'Metformin 500mg'},
        'quantity': 900,
        'price': '3.00',
        'low_threshold': 500,
      });

      expect(stock.lowThreshold, 500);
      expect(
        () => OwnerStock.fromJson({
          'id': 7,
          'medicine': {'id': 15, 'name': 'Losartan 50mg'},
          'quantity': 12,
          'price': '4.00',
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('defensively defaults an absent price the server cannot omit', () {
      // Not a shape today's backend can produce: price is a non-nullable
      // DecimalField and apply_stock_change() creates rows with
      // defaults={'price': 0.0}, which serialises as "0.00". This pins the
      // fallback's behaviour purely so a future serializer change degrades to
      // a placeholder instead of blanking the screen.
      final stock = OwnerStock.fromJson({
        'id': 4,
        'medicine': {'id': 12, 'name': 'Amoxicillin 250mg'},
        'quantity': 0,
        'low_threshold': 10,
      });

      expect(stock.price, '0');
    });
  });

  group('parseStockPayload', () {
    test('reads a bare list, the shape the endpoint returns today', () {
      final stock = parseStockPayload([
        {
          'id': 3,
          'medicine': {'id': 11, 'name': 'Paracetamol 500mg'},
          'quantity': 42,
          'price': '10.50',
          'low_threshold': 10,
        },
      ]);

      expect(stock, hasLength(1));
      expect(stock.single.medicineName, 'Paracetamol 500mg');
    });

    test('reads a single-page DRF pagination wrapper instead of cast-crashing', () {
      // OwnerStockViewSet is a bare viewsets.ViewSet, which has no pagination
      // machinery at all -- DEFAULT_PAGINATION_CLASS is honoured only by
      // GenericAPIView subclasses. This shape can therefore only appear if
      // someone promotes the view to a generic view / ModelViewSet, at which
      // point `data as List` would throw a cast error in the user's face.
      final stock = parseStockPayload({
        'count': 1,
        'next': null,
        'previous': null,
        'results': [
          {
            'id': 5,
            'medicine': {'id': 13, 'name': 'Ibuprofen 400mg'},
            'quantity': 7,
            'price': '25.00',
            'low_threshold': 4,
          },
        ],
      });

      expect(stock, hasLength(1));
      expect(stock.single.id, 5);
      expect(stock.single.medicineName, 'Ibuprofen 400mg');
    });

    test('throws rather than truncate when the wrapper reports a next page', () {
      // 25 rows behind PAGE_SIZE 20: returning the first 20 would hide a
      // medicine the owner stocks, and re-adding it earns a contradictory 400
      // "This pharmacy already stocks that medicine." Silent truncation is the
      // bug b30fd41 fixed elsewhere; this client refuses to reproduce it.
      expect(
        () => parseStockPayload({
          'count': 25,
          'next': 'http://localhost:8000/api/v1/my-pharmacy/stock/?page=2',
          'previous': null,
          'results': [
            {
              'id': 5,
              'medicine': {'id': 13, 'name': 'Ibuprofen 400mg'},
              'quantity': 7,
              'price': '25.00',
              'low_threshold': 4,
            },
          ],
        }),
        throwsStateError,
      );
    });

    test('rejects an unrecognised payload loudly', () {
      expect(() => parseStockPayload('nope'), throwsFormatException);
    });
  });
}

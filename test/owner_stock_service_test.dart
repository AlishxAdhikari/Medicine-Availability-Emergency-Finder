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
      });

      expect(stock.id, 3);
      expect(stock.medicineId, 11);
      expect(stock.medicineName, 'Paracetamol 500mg');
      expect(stock.quantity, 42);
      expect(stock.price, '10.50');
    });

    test('tolerates a missing price rather than throwing', () {
      // DRF renders DecimalField as a string, but a row created by the POS
      // sync defaults to 0.0 -- don't let a shape surprise blank the screen.
      final stock = OwnerStock.fromJson({
        'id': 4,
        'medicine': {'id': 12, 'name': 'Amoxicillin 250mg'},
        'quantity': 0,
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
        },
      ]);

      expect(stock, hasLength(1));
      expect(stock.single.medicineName, 'Paracetamol 500mg');
    });

    test('reads a DRF pagination wrapper instead of cast-crashing', () {
      // The project default is PageNumberPagination; if anyone ever drops
      // pagination_class = None from OwnerStockView this shape appears and
      // `data as List` would throw.
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
          },
        ],
      });

      expect(stock, hasLength(1));
      expect(stock.single.id, 5);
      expect(stock.single.medicineName, 'Ibuprofen 400mg');
    });

    test('rejects an unrecognised payload loudly', () {
      expect(() => parseStockPayload('nope'), throwsFormatException);
    });
  });
}

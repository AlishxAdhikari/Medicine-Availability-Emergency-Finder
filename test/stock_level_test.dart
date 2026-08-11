import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/stock_alert_service.dart';
import 'package:medalert/state.dart';

/// Covers the `stock_level` message kind added so customers see EVERY sale,
/// not just the ones that push a medicine below its low threshold.
///
/// Same testing boundary as owner_transaction_test.dart: the routing decision
/// and the payload decoding are pure functions, so they are worth pinning down
/// without a server. The socket plumbing around them is not.
void main() {
  group('socket message routing', () {
    test('tags a stock_level payload as a level, not an alert', () {
      final payload = {
        'event': 'stock_level',
        'medicine_id': 3,
        'medicine_name': 'Paracetamol 500mg',
        'quantity': 49,
        'low_threshold': 10,
      };
      expect(isStockLevelMessage(payload), isTrue);
      expect(isTransactionMessage(payload), isFalse);
    });

    test('an alert is not mistaken for a level', () {
      expect(
        isStockLevelMessage({
          'event': 'stock_alert',
          'medicine_id': 3,
          'medicine_name': 'Paracetamol 500mg',
          'quantity': 2,
          'level': 'low',
        }),
        isFalse,
      );
    });

    test('an untagged payload is still treated as an alert', () {
      // The pre-`event` server could only ever have sent an alert. Routing it
      // to StockLevel.fromJson would throw on the missing tag rather than
      // degrading, so the default must stay where it is.
      final legacy = {
        'medicine_id': 3,
        'medicine_name': 'Paracetamol 500mg',
        'quantity': 2,
        'level': 'low',
      };
      expect(isStockLevelMessage(legacy), isFalse);
      expect(isTransactionMessage(legacy), isFalse);
    });
  });

  group('StockLevel.fromJson', () {
    test('decodes a full payload', () {
      final level = StockLevel.fromJson({
        'event': 'stock_level',
        'medicine_id': 7,
        'medicine_name': 'Amoxicillin 250mg',
        'quantity': 12,
        'low_threshold': 5,
      });

      expect(level.medicineId, 7);
      expect(level.medicineName, 'Amoxicillin 250mg');
      expect(level.quantity, 12);
      expect(level.lowThreshold, 5);
    });

    test('tolerates a missing low_threshold', () {
      // A phone can be running a newer build than the server it is pointed at
      // during a demo. The quantity is the part that must survive that.
      final level = StockLevel.fromJson({
        'event': 'stock_level',
        'medicine_id': 7,
        'medicine_name': 'Amoxicillin 250mg',
        'quantity': 12,
      });

      expect(level.quantity, 12);
      expect(level.lowThreshold, 0);
    });

    test('accepts a quantity that arrived as a double', () {
      // JSON round-tripping can hand back 12.0 for a whole number; a hard int
      // cast would throw and kill the message.
      final level = StockLevel.fromJson({
        'event': 'stock_level',
        'medicine_id': 7,
        'medicine_name': 'Amoxicillin 250mg',
        'quantity': 12.0,
        'low_threshold': 5.0,
      });

      expect(level.quantity, 12);
      expect(level.lowThreshold, 5);
    });
  });

  group('Pharmacy.applyStockLevel', () {
    Pharmacy build() => Pharmacy(
          id: 1,
          name: 'Demo Pharmacy',
          distance: '1km',
          address: 'Addr',
          isOpen: true,
          items: [
            {
              'name': 'Paracetamol 500mg',
              'quantity': 50,
              'lowThreshold': 10,
              'inStock': true,
            },
          ],
        );

    test('a routine sale updates the quantity, not just the boolean', () {
      // This is the regression the whole stock_level path exists for: the old
      // handler wrote only `inStock`, so 50 -> 49 changed nothing on screen
      // and live sync looked broken for everything but near-empty stock.
      final pharmacy = build();
      expect(pharmacy.applyStockLevel('Paracetamol 500mg', 49), isTrue);

      expect(pharmacy.items[0]['quantity'], 49);
      expect(pharmacy.items[0]['inStock'], isTrue);
    });

    test('reaching zero flips inStock as well as the quantity', () {
      final pharmacy = build();
      pharmacy.applyStockLevel('Paracetamol 500mg', 0);

      expect(pharmacy.items[0]['quantity'], 0);
      expect(pharmacy.items[0]['inStock'], isFalse);
    });

    test('restocking from zero flips inStock back', () {
      final pharmacy = build();
      pharmacy.applyStockLevel('Paracetamol 500mg', 0);
      pharmacy.applyStockLevel('Paracetamol 500mg', 20);

      expect(pharmacy.items[0]['quantity'], 20);
      expect(pharmacy.items[0]['inStock'], isTrue);
    });

    test('an omitted threshold leaves the previous one alone', () {
      // stock_alert carries no low_threshold. Overwriting the known one with a
      // default would mislabel the chip on the very message that matters most.
      final pharmacy = build();
      pharmacy.applyStockLevel('Paracetamol 500mg', 8);

      expect(pharmacy.items[0]['lowThreshold'], 10);
    });

    test('a supplied threshold is applied', () {
      final pharmacy = build();
      pharmacy.applyStockLevel('Paracetamol 500mg', 8, lowThreshold: 15);

      expect(pharmacy.items[0]['lowThreshold'], 15);
    });

    test('returns false for a medicine this pharmacy does not stock', () {
      // Every watched pharmacy pushes to one merged stream, so a screen gets
      // messages about medicines a given card has never listed.
      final pharmacy = build();
      expect(pharmacy.applyStockLevel('Insulin', 5), isFalse);
      expect(pharmacy.items.length, 1);
      expect(pharmacy.items[0]['quantity'], 50);
    });
  });
}

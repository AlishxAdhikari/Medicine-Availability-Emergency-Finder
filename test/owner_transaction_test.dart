import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/owner_stock_service.dart';
import 'package:medalert/services/stock_alert_service.dart';

/// Covers the decoding half of the owner activity feed. The payloads below
/// mirror what sync/serializers.py's OwnerTransactionSerializer emits.
void main() {
  Map<String, dynamic> row({
    int id = 1,
    String medicineName = 'Paracetamol',
    int quantityDelta = -2,
    String transactionType = 'DISPENSED',
    String source = 'POS_SYNC',
    String? changedBy,
    String serverTimestamp = '2026-08-11T10:00:00Z',
  }) {
    return {
      'id': id,
      'medicine': 7,
      'medicine_name': medicineName,
      'quantity_delta': quantityDelta,
      'transaction_type': transactionType,
      'source': source,
      'changed_by_username': changedBy,
      'client_timestamp': serverTimestamp,
      'server_timestamp': serverTimestamp,
    };
  }

  group('StockTransactionEntry.fromJson', () {
    test('reads every field off a dispense row', () {
      final entry = StockTransactionEntry.fromJson(row());

      expect(entry.id, 1);
      expect(entry.medicineName, 'Paracetamol');
      expect(entry.quantityDelta, -2);
      expect(entry.transactionType, 'DISPENSED');
      expect(entry.source, 'POS_SYNC');
      expect(entry.changedByUsername, isNull);
    });

    test('treats a negative delta as a dispense and positive as a restock', () {
      // The sign drives the icon and the colour, so it is worth pinning.
      expect(StockTransactionEntry.fromJson(row(quantityDelta: -2)).isDispense, isTrue);
      expect(StockTransactionEntry.fromJson(row(quantityDelta: 5)).isDispense, isFalse);
    });

    test('keeps a null changed_by rather than inventing a name', () {
      // POS_SYNC rows authenticate with a pharmacy-wide key and genuinely have
      // no user behind them; the UI names the source instead.
      final entry = StockTransactionEntry.fromJson(row(changedBy: null));
      expect(entry.changedByUsername, isNull);
    });

    test('reads a username on a manual row', () {
      final entry = StockTransactionEntry.fromJson(
        row(source: 'MANUAL', transactionType: 'ADJUSTED', changedBy: 'ramesh'),
      );
      expect(entry.changedByUsername, 'ramesh');
      expect(entry.source, 'MANUAL');
    });

    test('converts the server timestamp to local time', () {
      final entry = StockTransactionEntry.fromJson(row());
      // Django sends UTC (USE_TZ = True). Rendering it without converting
      // would show every event 5h45m off local time in Nepal.
      expect(entry.serverTimestamp.isUtc, isFalse);
      expect(
        entry.serverTimestamp.toUtc(),
        DateTime.utc(2026, 8, 11, 10),
      );
    });

    test('falls back when medicine_name is absent', () {
      final payload = row()..remove('medicine_name');
      expect(
        StockTransactionEntry.fromJson(payload).medicineName,
        'Unknown medicine',
      );
    });
  });

  group('parseTransactionPayload', () {
    test('reads the paginated shape the ModelViewSet returns', () {
      // OwnerTransactionViewSet is a ModelViewSet, so DEFAULT_PAGINATION_CLASS
      // applies and this wrapper is the real production shape.
      final entries = parseTransactionPayload({
        'count': 2,
        'next': null,
        'previous': null,
        'results': [row(id: 1), row(id: 2)],
      });
      expect(entries.map((e) => e.id), [1, 2]);
    });

    test('accepts a bare list too', () {
      final entries = parseTransactionPayload([row(id: 3)]);
      expect(entries.single.id, 3);
    });

    test('returns the first page even when more pages exist', () {
      // Deliberately unlike parseStockPayload, which throws on a truncated
      // list. The ledger is newest-first, so page one IS the recent activity
      // being asked for; there is no row on page two that the owner is
      // missing from "what just happened".
      final entries = parseTransactionPayload({
        'count': 100,
        'next': 'http://example.test/api/v1/my-pharmacy/transactions/?page=2',
        'previous': null,
        'results': [row(id: 9)],
      });
      expect(entries.single.id, 9);
    });

    test('throws on an unrecognised payload rather than showing nothing', () {
      expect(
        () => parseTransactionPayload('not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('handles an empty feed', () {
      expect(parseTransactionPayload({'count': 0, 'results': []}), isEmpty);
    });
  });

  group('socket message routing', () {
    // Both message kinds arrive on one socket, so isTransactionMessage is what
    // keeps a sale from being decoded as an alert (and silently vanishing from
    // the feed) or vice versa.
    test('routes a tagged transaction to the transaction stream', () {
      final payload = row()..['event'] = 'stock_transaction';
      expect(isTransactionMessage(payload), isTrue);
      // And it must decode with the same code path as a fetched row.
      expect(StockTransactionEntry.fromJson(payload).quantityDelta, -2);
    });

    test('routes a tagged alert to the alert stream', () {
      expect(
        isTransactionMessage({
          'event': 'stock_alert',
          'medicine_id': 1,
          'medicine_name': 'Paracetamol',
          'quantity': 0,
          'level': 'critical',
        }),
        isFalse,
      );
    });

    test('treats an untagged message as an alert', () {
      // A server predating the `event` key could only have sent alerts.
      // Guessing "transaction" instead would throw on every message.
      expect(
        isTransactionMessage({
          'medicine_id': 1,
          'medicine_name': 'Paracetamol',
          'quantity': 0,
          'level': 'critical',
        }),
        isFalse,
      );
    });

    test('does not mistake an unrelated event value for a transaction', () {
      expect(isTransactionMessage({'event': 'something_else'}), isFalse);
    });
  });
}

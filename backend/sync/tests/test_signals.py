"""
C3: tests for sync/signals.py -- the post_save signal on StockTransaction
that checks whether stock dropped to/below low_threshold and, if so,
broadcasts a stock_alert to the pharmacy's WebSocket group.

These don't open a real WebSocket connection (see test_consumer.py for
that) -- they mock the channel layer's group_send and assert it was called
(or wasn't) with the right arguments. That's the correct unit-test
boundary: it proves the signal's *decision logic* is right without needing
a live consumer or Redis for every test run.

IMPORTANT: the signal reads PharmacyMedicineStock.quantity fresh from the
DB, and does so ON COMMIT rather than inline with the .create() that fires
post_save -- an uncommitted quantity is one that may still be rolled back, and
a broadcast cannot be taken back. The real view (sync/views.py) updates the
stock row's quantity FIRST, then creates the StockTransaction, both inside the
same atomic block -- so these tests use a helper that mirrors that exact order,
and wraps it in captureOnCommitCallbacks so the deferred send actually runs.
"""
from unittest.mock import patch

from django.test import TestCase
from django.utils import timezone

from pharmacy.models import Medicine, Pharmacy, PharmacyMedicineStock
from sync.models import StockTransaction
from sync.testing import sent_events


class ThresholdSignalTests(TestCase):
    def setUp(self):
        self.pharmacy = Pharmacy.objects.create(
            name='Signal Test Pharmacy', address='Addr', district='Kathmandu',
            latitude=27.7, longitude=85.3,
        )
        self.medicine = Medicine.objects.create(
            name='Ibuprofen 400mg', category='Analgesic',
            dosage_form='Tablet', strength='400mg',
        )

    def _make_stock(self, quantity, low_threshold=10):
        return PharmacyMedicineStock.objects.create(
            pharmacy=self.pharmacy, medicine=self.medicine,
            quantity=quantity, low_threshold=low_threshold, price=5,
        )

    def _dispense(self, stock, delta, transaction_type='DISPENSED', source='POS_SYNC'):
        """Mirrors exactly what StockSyncView.post() does: update the stock
        row's quantity first, THEN create the StockTransaction -- since
        that creation is what triggers the signal, and the signal reads
        whatever quantity is in the DB at that instant.
        """
        # captureOnCommitCallbacks because the alert is now raised via
        # transaction.on_commit (sync/signals.py) -- inside a TestCase, which
        # never commits, the callback would otherwise be registered and
        # discarded, and every assertion below would pass or fail for the wrong
        # reason. execute=True runs it at the end of this block, which is the
        # commit point the real request has.
        with self.captureOnCommitCallbacks(execute=True):
            stock.quantity = max(0, stock.quantity + delta)
            stock.save()
            txn = StockTransaction.objects.create(
                pharmacy=self.pharmacy, medicine=self.medicine,
                quantity_delta=delta, transaction_type=transaction_type, source=source,
                client_timestamp=timezone.now(),
            )
        return txn

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_transaction_dropping_below_threshold_fires_alert(
        self, mock_async_to_sync, mock_get_layer
    ):
        """Stock at 12 (above threshold of 10), a dispense drops it to 8
        (below threshold) -- signal should fire.
        """
        stock = self._make_stock(quantity=12, low_threshold=10)
        self._dispense(stock, -4)

        mock_async_to_sync.assert_called()

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_alert_payload_and_group_name_are_correct(self, mock_async_to_sync, mock_get_layer):
        """Assert the exact group name and payload shape the consumer
        depends on.
        """
        stock = self._make_stock(quantity=3, low_threshold=10)  # already low
        self._dispense(stock, -2)

        alerts = sent_events(mock_async_to_sync, 'stock_alert')
        self.assertEqual(len(alerts), 1)
        group_name, event = alerts[0]

        self.assertEqual(group_name, f'pharmacy_{self.pharmacy.id}')
        self.assertEqual(event['data']['event'], 'stock_alert')
        self.assertEqual(event['data']['medicine_id'], self.medicine.id)
        self.assertEqual(event['data']['medicine_name'], self.medicine.name)
        self.assertEqual(event['data']['quantity'], 1)  # 3 - 2
        self.assertEqual(event['data']['level'], 'low')  # >0, so 'low' not 'critical'

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_critical_level_when_quantity_reaches_zero(self, mock_async_to_sync, mock_get_layer):
        stock = self._make_stock(quantity=2, low_threshold=10)
        self._dispense(stock, -2)

        _, event = sent_events(mock_async_to_sync, 'stock_alert')[0]
        self.assertEqual(event['data']['quantity'], 0)
        self.assertEqual(event['data']['level'], 'critical')

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_transaction_well_above_threshold_pushes_level_but_no_alert(
        self, mock_async_to_sync, mock_get_layer
    ):
        """Plenty of stock, well above low_threshold.

        This used to assert the signal did nothing at all. That was the bug
        behind "live sync only works when stock is nearly empty": a sale from
        95 to 90 is exactly the movement a customer watching this pharmacy
        needs to see, and it reached nobody. The routine level update must go
        out; only the *warning* is withheld.
        """
        stock = self._make_stock(quantity=95, low_threshold=10)
        self._dispense(stock, -5)  # still 90, well above threshold

        levels = sent_events(mock_async_to_sync, 'stock_level')
        self.assertEqual(len(levels), 1)
        group_name, event = levels[0]
        self.assertEqual(group_name, f'pharmacy_{self.pharmacy.id}')
        self.assertEqual(event['data']['event'], 'stock_level')
        self.assertEqual(event['data']['medicine_id'], self.medicine.id)
        self.assertEqual(event['data']['medicine_name'], self.medicine.name)
        self.assertEqual(event['data']['quantity'], 90)
        self.assertEqual(event['data']['low_threshold'], 10)

        self.assertEqual(sent_events(mock_async_to_sync, 'stock_alert'), [])

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_level_precedes_alert_when_both_are_sent(
        self, mock_async_to_sync, mock_get_layer
    ):
        """A client applying messages in arrival order must end on the alert,
        not overwrite it with the level that triggered it.
        """
        stock = self._make_stock(quantity=12, low_threshold=10)
        self._dispense(stock, -4)  # -> 8, at/below threshold

        public = [
            event['type']
            for group, event in sent_events(mock_async_to_sync)
            if group == f'pharmacy_{self.pharmacy.id}'
        ]
        self.assertEqual(public, ['stock_level', 'stock_alert'])

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_skip_low_stock_alert_suppresses_alert_but_not_level(
        self, mock_async_to_sync, mock_get_layer
    ):
        """apply_stock_change(alert=False) means "don't warn about this", not
        "hide this movement". The owner's ledger push and the public level
        update both still go out -- otherwise an opening quantity the owner
        typed would never appear on a customer's screen until they re-searched.
        """
        stock = self._make_stock(quantity=3, low_threshold=10)  # already low
        with self.captureOnCommitCallbacks(execute=True):
            stock.quantity = 2
            stock.save()
            txn = StockTransaction(
                pharmacy=self.pharmacy, medicine=self.medicine,
                quantity_delta=-1, transaction_type='ADJUSTED', source='MANUAL',
                client_timestamp=timezone.now(),
            )
            txn.skip_low_stock_alert = True
            txn.save()

        self.assertEqual(len(sent_events(mock_async_to_sync, 'stock_level')), 1)
        self.assertEqual(len(sent_events(mock_async_to_sync, 'stock_transaction')), 1)
        self.assertEqual(sent_events(mock_async_to_sync, 'stock_alert'), [])

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_quantity_exactly_at_threshold_fires_alert(
        self, mock_async_to_sync, mock_get_layer
    ):
        """Boundary case: quantity == low_threshold exactly. The signal
        uses `if stock.quantity > stock.low_threshold: return`, so being
        AT the threshold (not just below it) should still alert.
        """
        stock = self._make_stock(quantity=10, low_threshold=10)
        self._dispense(stock, 0, transaction_type='ADJUSTED', source='MANUAL')

        mock_async_to_sync.assert_called()

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_no_matching_stock_row_does_not_crash(
        self, mock_async_to_sync, mock_get_layer
    ):
        """If a StockTransaction somehow exists for a pharmacy-medicine pair
        with no PharmacyMedicineStock row (shouldn't normally happen since
        the view always get_or_creates one first), the signal should just
        return quietly instead of raising DoesNotExist.

        The owner ledger push still happens -- it reads only the transaction
        row, which does exist. What must not happen is a level or an alert
        describing a stock row that isn't there.
        """
        other_medicine = Medicine.objects.create(
            name='Amoxicillin 250mg', category='Antibiotic',
            dosage_form='Capsule', strength='250mg',
        )
        # Deliberately no PharmacyMedicineStock row for this pair -- create
        # the StockTransaction directly (can't use _dispense(), which
        # requires an existing stock row).
        with self.captureOnCommitCallbacks(execute=True):
            StockTransaction.objects.create(
                pharmacy=self.pharmacy, medicine=other_medicine,
                quantity_delta=-1, transaction_type='DISPENSED', source='POS_SYNC',
                client_timestamp=timezone.now(),
            )
        self.assertEqual(sent_events(mock_async_to_sync, 'stock_level'), [])
        self.assertEqual(sent_events(mock_async_to_sync, 'stock_alert'), [])
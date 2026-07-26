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
DB at the moment StockTransaction.objects.create() runs (post_save fires
synchronously, inline with .create()). The real view (sync/views.py)
updates the stock row's quantity FIRST, then creates the StockTransaction,
both inside the same atomic block -- so these tests use a helper that
mirrors that exact order, rather than creating the transaction against a
stock row that was never actually updated.
"""
from unittest.mock import patch

from django.test import TestCase
from django.utils import timezone

from pharmacy.models import Medicine, Pharmacy, PharmacyMedicineStock
from sync.models import StockTransaction


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
        stock.quantity = max(0, stock.quantity + delta)
        stock.save()
        return StockTransaction.objects.create(
            pharmacy=self.pharmacy, medicine=self.medicine,
            quantity_delta=delta, transaction_type=transaction_type, source=source,
            client_timestamp=timezone.now(),
        )

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

        self.assertTrue(mock_async_to_sync.called)
        # async_to_sync(fn) returns a callable; that callable is what
        # actually got invoked with (group_name, event_dict).
        wrapped_call = mock_async_to_sync.return_value
        self.assertTrue(wrapped_call.called)
        args, _ = wrapped_call.call_args
        group_name, event = args

        self.assertEqual(group_name, f'pharmacy_{self.pharmacy.id}')
        self.assertEqual(event['type'], 'stock_alert')
        self.assertEqual(event['data']['medicine_id'], self.medicine.id)
        self.assertEqual(event['data']['medicine_name'], self.medicine.name)
        self.assertEqual(event['data']['quantity'], 1)  # 3 - 2
        self.assertEqual(event['data']['level'], 'low')  # >0, so 'low' not 'critical'

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_critical_level_when_quantity_reaches_zero(self, mock_async_to_sync, mock_get_layer):
        stock = self._make_stock(quantity=2, low_threshold=10)
        self._dispense(stock, -2)

        wrapped_call = mock_async_to_sync.return_value
        _, event = wrapped_call.call_args[0]
        self.assertEqual(event['data']['quantity'], 0)
        self.assertEqual(event['data']['level'], 'critical')

    @patch('sync.signals.get_channel_layer')
    @patch('sync.signals.async_to_sync')
    def test_transaction_that_does_not_cross_threshold_does_nothing(
        self, mock_async_to_sync, mock_get_layer
    ):
        """Plenty of stock, well above low_threshold -- the signal should
        do nothing at all: no channel layer lookup, no group_send.
        """
        stock = self._make_stock(quantity=95, low_threshold=10)
        self._dispense(stock, -5)  # still 90, well above threshold

        mock_get_layer.assert_not_called()
        mock_async_to_sync.assert_not_called()

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
        """
        other_medicine = Medicine.objects.create(
            name='Amoxicillin 250mg', category='Antibiotic',
            dosage_form='Capsule', strength='250mg',
        )
        # Deliberately no PharmacyMedicineStock row for this pair -- create
        # the StockTransaction directly (can't use _dispense(), which
        # requires an existing stock row).
        StockTransaction.objects.create(
            pharmacy=self.pharmacy, medicine=other_medicine,
            quantity_delta=-1, transaction_type='DISPENSED', source='POS_SYNC',
            client_timestamp=timezone.now(),
        )
        mock_async_to_sync.assert_not_called()
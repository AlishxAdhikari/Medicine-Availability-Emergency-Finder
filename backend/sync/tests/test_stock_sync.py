"""
Test suite for the POS stock-sync ingestion endpoint (C1) — POST /api/v1/stock/sync/.

Covers the cases listed under C3 in the project plan:
  - valid payload -> 201/200, transaction created, quantity updated correctly
  - invalid/missing API key -> 401
  - duplicate transaction (same client_timestamp) -> documents current behaviour
  - concurrent requests to same pharmacy-medicine pair -> no lost updates

NOTE (as of writing this suite): two of the tests below currently FAIL against
the checked-in view code. That's intentional — they encode what the spec
actually requires (a clean 401 on bad/missing auth) so the failures are
visible and trackable rather than silently accepted. See the docstrings on
test_missing_api_key_returns_401 and test_invalid_api_key_returns_401 for
what actually happens right now instead.
"""
import threading

from django.test import TransactionTestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from pharmacy.models import Medicine, Pharmacy, PharmacyMedicineStock
from sync.models import POSIntegrationKey, StockTransaction

SYNC_URL = '/api/v1/stock/sync/'


def make_pharmacy_and_key(name='Test Pharmacy', key=None):
    """Creates a Pharmacy + POSIntegrationKey pair for tests.

    NOTE: earlier versions of POSIntegrationKey had a bug where the auto-
    generated key was identical for every row (see git history / the
    mid-defense bug list), which meant tests needing more than one pharmacy
    had to pass an explicit unique `key`. That's now fixed -- auto-generated
    keys are unique per row -- but the optional `key` param is kept here
    since some tests still want a predictable, known key value.
    """
    pharmacy = Pharmacy.objects.create(
        name=name, address='Test Address', district='Kathmandu',
        latitude=27.7, longitude=85.3,
    )
    kwargs = {'pharmacy': pharmacy}
    if key is not None:
        kwargs['key'] = key
    integration = POSIntegrationKey.objects.create(**kwargs)
    return pharmacy, integration


class StockSyncIngestionTests(TransactionTestCase):
    """Core ingestion behaviour: POST /api/v1/stock/sync/"""

    def setUp(self):
        self.client = APIClient()
        self.pharmacy, self.pos_key = make_pharmacy_and_key(key='a' * 64)
        self.medicine = Medicine.objects.create(
            name='Paracetamol 500mg', category='Analgesic',
            dosage_form='Tablet', strength='500mg',
        )
        self.stock = PharmacyMedicineStock.objects.create(
            pharmacy=self.pharmacy, medicine=self.medicine,
            quantity=100, price=10,
        )

    def _post(self, payload, key=None):
        headers = {}
        if key is not None:
            headers['HTTP_X_POS_API_KEY'] = key
        return self.client.post(SYNC_URL, payload, format='json', **headers)

    def test_valid_payload_creates_transaction_and_updates_quantity(self):
        """A correctly authenticated, well-formed dispensing event should be
        accepted, log an immutable StockTransaction, and update the running
        quantity by exactly the delta sent."""
        payload = {
            'medicine_barcode_or_name': 'Paracetamol 500mg',
            'quantity_delta': -5,
            'transaction_type': 'DISPENSED',
            'timestamp': timezone.now().isoformat(),
        }
        response = self._post(payload, key=self.pos_key.key)

        self.assertIn(response.status_code, (200, 201))
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 95)
        self.assertEqual(StockTransaction.objects.count(), 1)
        txn = StockTransaction.objects.first()
        self.assertEqual(txn.quantity_delta, -5)
        self.assertEqual(txn.source, 'POS_SYNC')
        self.assertEqual(txn.pharmacy, self.pharmacy)
        self.assertEqual(txn.medicine, self.medicine)

    def test_restock_increases_quantity(self):
        payload = {
            'medicine_barcode_or_name': 'Paracetamol 500mg',
            'quantity_delta': 50,
            'transaction_type': 'RESTOCKED',
            'timestamp': timezone.now().isoformat(),
        }
        response = self._post(payload, key=self.pos_key.key)

        self.assertIn(response.status_code, (200, 201))
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 150)

    def test_missing_api_key_returns_401(self):
        """Spec: a request with no X-POS-API-Key header must be rejected
        with 401.

        CURRENT BEHAVIOUR (bug): POSKeyAuthentication.authenticate() returns
        None when the header is absent, so DRF falls through to an
        anonymous request. The view's own AnonymousUser guard doesn't
        actually catch this case (AnonymousUser is truthy and has a `.pk`
        attribute), so the request proceeds into the database layer and
        crashes with an unhandled 500 TypeError instead of a clean 401.
        This test asserts the SPEC behaviour and is expected to fail until
        that's fixed.
        """
        payload = {
            'medicine_barcode_or_name': 'Paracetamol 500mg',
            'quantity_delta': -1,
            'transaction_type': 'DISPENSED',
            'timestamp': timezone.now().isoformat(),
        }
        response = self._post(payload, key=None)
        self.assertEqual(
            response.status_code, 401,
            f"Expected 401 for a missing API key, got {response.status_code}. "
            "See docstring -- this currently 500s instead of rejecting cleanly."
        )

    def test_invalid_api_key_returns_401(self):
        """Spec: an unrecognised API key must be rejected with 401.

        CURRENT BEHAVIOUR: POSKeyAuthentication raises AuthenticationFailed
        correctly, but because it doesn't implement authenticate_header(),
        DRF's exception handler can't attach a WWW-Authenticate header and
        downgrades the response to 403 instead of 401. This test asserts
        the SPEC behaviour and is expected to fail until that's fixed.
        """
        payload = {
            'medicine_barcode_or_name': 'Paracetamol 500mg',
            'quantity_delta': -1,
            'transaction_type': 'DISPENSED',
            'timestamp': timezone.now().isoformat(),
        }
        response = self._post(payload, key='not-a-real-key')
        self.assertEqual(
            response.status_code, 401,
            f"Expected 401 for an invalid API key, got {response.status_code}."
        )

    def test_unknown_medicine_returns_400_not_500(self):
        """A barcode/name that doesn't match any Medicine should be a
        client error (400), not an unhandled exception."""
        payload = {
            'medicine_barcode_or_name': 'Definitely Not A Real Medicine',
            'quantity_delta': -1,
            'transaction_type': 'DISPENSED',
            'timestamp': timezone.now().isoformat(),
        }
        response = self._post(payload, key=self.pos_key.key)
        self.assertEqual(response.status_code, 400)

    def test_duplicate_transaction_same_timestamp(self):
        """Spec calls out that the team must decide: does the same POS event
        POSTed twice (e.g. a network retry) get deduped, or accepted as two
        separate ledger entries?

        CURRENT BEHAVIOUR: there is no dedupe check anywhere in
        StockSyncSerializer or StockSyncView, so identical payloads (same
        client_timestamp, same medicine, same pharmacy) are accepted as two
        independent StockTransaction rows, and the quantity is decremented
        twice. This test documents that actual behaviour rather than
        asserting a decision that hasn't been made yet -- flip the
        assertions below once the team picks a dedupe strategy.
        """
        shared_timestamp = timezone.now().isoformat()
        payload = {
            'medicine_barcode_or_name': 'Paracetamol 500mg',
            'quantity_delta': -3,
            'transaction_type': 'DISPENSED',
            'timestamp': shared_timestamp,
        }

        first = self._post(payload, key=self.pos_key.key)
        second = self._post(payload, key=self.pos_key.key)

        self.assertIn(first.status_code, (200, 201))
        self.assertIn(second.status_code, (200, 201))
        self.assertEqual(
            StockTransaction.objects.filter(client_timestamp=shared_timestamp).count(),
            2,
            "Documents current no-dedupe behaviour -- update this test once "
            "the team agrees on a dedupe strategy for retried POS events."
        )
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 94)  # 100 - 3 - 3, both applied

    def test_concurrent_requests_do_not_lose_updates(self):
        """The non-functional requirement this exercises: two POS writes to
        the SAME pharmacy-medicine pair, fired at the same time, must not
        clobber each other. This is what select_for_update() in the view is
        supposed to guarantee.

        CURRENT BEHAVIOUR (bug, consistently reproducible -- 4/4 runs
        failed in local testing): this fails. select_for_update() locks
        rows at the database level, but SQLite -- the database this project
        currently runs on (see medalert_api/settings.py, DATABASES) --
        does not support row-level locking at all; Django silently no-ops
        select_for_update() on SQLite rather than erroring, so the "lock"
        the view relies on isn't actually happening. The result is a
        classic lost-update race: two threads read the same starting
        quantity before either writes back, and one thread's update
        overwrites the other's instead of both being applied.

        This is NOT a code logic bug in the view -- the locking code is
        written correctly -- it's a database-choice limitation. The
        proposal's target architecture (Section 2.5 / Table 4.1) specifies
        PostgreSQL for production, and PostgreSQL DOES support row-level
        locking, so this should pass once the project moves off SQLite.
        Documenting it here so it's tracked rather than silently masked by
        the dev database's behaviour.
        """
        num_threads = 10
        delta_per_request = -1
        results = []

        def fire_request():
            payload = {
                'medicine_barcode_or_name': 'Paracetamol 500mg',
                'quantity_delta': delta_per_request,
                'transaction_type': 'DISPENSED',
                'timestamp': timezone.now().isoformat(),
            }
            client = APIClient()
            response = client.post(
                SYNC_URL, payload, format='json',
                HTTP_X_POS_API_KEY=self.pos_key.key,
            )
            results.append(response.status_code)

        threads = [threading.Thread(target=fire_request) for _ in range(num_threads)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertTrue(all(code in (200, 201) for code in results), results)
        self.stock.refresh_from_db()
        expected = 100 + (delta_per_request * num_threads)
        self.assertEqual(
            self.stock.quantity, expected,
            "Final quantity doesn't match 100 + (delta * threads) -- "
            "this means a concurrent update was lost."
        )
        self.assertEqual(StockTransaction.objects.count(), num_threads)


class POSIntegrationKeyTests(TransactionTestCase):
    """Covers the key-collision bug found while testing C1 manually.

    See make_pharmacy_and_key()'s docstring above for the workaround other
    tests use. This test exists specifically to pin down and demonstrate
    the bug itself so it shows up in the test run rather than only in
    manual curl testing.
    """

    def test_two_auto_generated_keys_are_unique(self):
        """Spec: each pharmacy's POS key must be unique (key = ... unique=True
        on the model).

        UPDATE: this used to fail (see git history / mid-defense bug list) --
        POSIntegrationKey.key's default was `secrets.token_hex(32)`, called
        once at class-definition time, so every auto-generated key was
        identical and a second POSIntegrationKey.objects.create() without
        an explicit key crashed with an IntegrityError. That's now fixed by
        using a `generate_pos_key()` function reference as the default
        instead (evaluated per-instance), so this test now asserts the
        actual required behaviour: two auto-generated keys differ.
        """
        pharmacy_a = Pharmacy.objects.create(
            name='Pharmacy A', address='A', district='Kathmandu',
            latitude=27.7, longitude=85.3,
        )
        pharmacy_b = Pharmacy.objects.create(
            name='Pharmacy B', address='B', district='Kathmandu',
            latitude=27.7, longitude=85.3,
        )

        key_a = POSIntegrationKey.objects.create(pharmacy=pharmacy_a)
        key_b = POSIntegrationKey.objects.create(pharmacy=pharmacy_b)

        self.assertNotEqual(key_a.key, key_b.key)
        self.assertEqual(len(key_a.key), 64)
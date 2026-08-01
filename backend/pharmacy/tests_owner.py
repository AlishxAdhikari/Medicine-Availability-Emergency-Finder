import threading

from django.contrib.auth import get_user_model
from django.db import IntegrityError, connection
from django.test import TestCase, TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient

from pharmacy.models import Medicine, Pharmacy, PharmacyMedicineStock, PharmacyOwner
from pharmacy.services import apply_stock_change
from sync.models import StockTransaction

User = get_user_model()


def make_pharmacy(name='Test Pharmacy'):
    return Pharmacy.objects.create(
        name=name, address='Test Address', district='Kathmandu',
        latitude=27.7, longitude=85.3,
    )


class PharmacyOwnerModelTests(TestCase):

    def test_owner_link_exposes_pharmacy_and_marks_role(self):
        """The role is derived from the link, not stored -- this is the
        check every permission and serializer in this feature relies on."""
        user = User.objects.create_user(username='owner1', password='pw123456!')
        pharmacy = make_pharmacy()
        PharmacyOwner.objects.create(user=user, pharmacy=pharmacy)

        user.refresh_from_db()
        self.assertTrue(hasattr(user, 'pharmacy_owner'))
        self.assertEqual(user.pharmacy_owner.pharmacy, pharmacy)

    def test_plain_user_has_no_owner_link(self):
        user = User.objects.create_user(username='plain', password='pw123456!')
        self.assertFalse(hasattr(user, 'pharmacy_owner'))

    def test_a_user_can_own_only_one_pharmacy(self):
        """OneToOneField on user -- a second link for the same user must fail
        rather than silently making 'which pharmacy?' ambiguous."""
        user = User.objects.create_user(username='owner2', password='pw123456!')
        PharmacyOwner.objects.create(user=user, pharmacy=make_pharmacy('A'))

        with self.assertRaises(IntegrityError):
            PharmacyOwner.objects.create(user=user, pharmacy=make_pharmacy('B'))

    def test_a_pharmacy_can_have_several_owners(self):
        pharmacy = make_pharmacy()
        for name in ('owner3', 'owner4'):
            user = User.objects.create_user(username=name, password='pw123456!')
            PharmacyOwner.objects.create(user=user, pharmacy=pharmacy)

        self.assertEqual(pharmacy.owners.count(), 2)


class ApplyStockChangeTests(TestCase):
    """One locked write path for both callers. The owner API sends an
    absolute count (what's on the shelf); the POS sends a delta (what
    moved). Both resolve to a final quantity inside the lock so neither
    caller does arithmetic on a value it read earlier."""

    def setUp(self):
        self.pharmacy = make_pharmacy()
        self.medicine = Medicine.objects.create(
            name='Paracetamol 500mg', category='Analgesic',
            dosage_form='Tablet', strength='500mg',
        )
        self.stock = PharmacyMedicineStock.objects.create(
            pharmacy=self.pharmacy, medicine=self.medicine, quantity=100, price=10,
        )
        self.user = User.objects.create_user(username='owner5', password='pw123456!')

    def test_absolute_write_records_the_derived_delta(self):
        stock, txn, clamped = apply_stock_change(
            self.pharmacy, self.medicine, absolute=80,
            source='MANUAL', transaction_type='ADJUSTED', user=self.user,
        )

        self.assertEqual(stock.quantity, 80)
        self.assertEqual(txn.quantity_delta, -20)
        self.assertEqual(txn.source, 'MANUAL')
        self.assertEqual(txn.transaction_type, 'ADJUSTED')
        self.assertEqual(txn.changed_by, self.user)
        self.assertFalse(clamped)

    def test_delta_write_applies_the_delta(self):
        stock, txn, clamped = apply_stock_change(
            self.pharmacy, self.medicine, delta=-5,
            source='POS_SYNC', transaction_type='DISPENSED',
        )

        self.assertEqual(stock.quantity, 95)
        self.assertEqual(txn.quantity_delta, -5)
        self.assertIsNone(txn.changed_by)

    def test_delta_below_zero_clamps_quantity_but_logs_requested_delta(self):
        """Pre-existing POS behaviour that must survive this refactor: the
        shelf can't go negative, but the ledger records what was actually
        asked for, so the discrepancy stays visible."""
        stock, txn, clamped = apply_stock_change(
            self.pharmacy, self.medicine, delta=-150,
            source='POS_SYNC', transaction_type='DISPENSED',
        )

        self.assertEqual(stock.quantity, 0)
        self.assertEqual(txn.quantity_delta, -150)
        self.assertTrue(clamped)

    def test_creates_the_stock_row_when_absent(self):
        other = Medicine.objects.create(
            name='Amoxicillin 250mg', category='Antibiotic',
            dosage_form='Capsule', strength='250mg',
        )

        stock, txn, _ = apply_stock_change(
            self.pharmacy, other, absolute=30,
            source='MANUAL', transaction_type='ADJUSTED', user=self.user,
        )

        self.assertEqual(stock.quantity, 30)
        self.assertEqual(txn.quantity_delta, 30)
        self.assertEqual(PharmacyMedicineStock.objects.filter(medicine=other).count(), 1)

    def test_requires_exactly_one_of_absolute_or_delta(self):
        with self.assertRaises(ValueError):
            apply_stock_change(
                self.pharmacy, self.medicine,
                source='MANUAL', transaction_type='ADJUSTED',
            )
        with self.assertRaises(ValueError):
            apply_stock_change(
                self.pharmacy, self.medicine, absolute=10, delta=5,
                source='MANUAL', transaction_type='ADJUSTED',
            )


class OwnerStockApiTests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.password = 'pw123456!'
        self.owner = User.objects.create_user(username='owner6', password=self.password)
        self.pharmacy = make_pharmacy('My Pharmacy')
        PharmacyOwner.objects.create(user=self.owner, pharmacy=self.pharmacy)

        self.medicine = Medicine.objects.create(
            name='Paracetamol 500mg', category='Analgesic',
            dosage_form='Tablet', strength='500mg',
        )
        self.stock = PharmacyMedicineStock.objects.create(
            pharmacy=self.pharmacy, medicine=self.medicine, quantity=100, price=10,
        )

    def _auth(self, user):
        self.client.force_authenticate(user=user)

    def test_owner_lists_only_their_own_stock(self):
        other_pharmacy = make_pharmacy('Someone Elses')
        PharmacyMedicineStock.objects.create(
            pharmacy=other_pharmacy, medicine=self.medicine, quantity=7, price=5,
        )
        self._auth(self.owner)

        response = self.client.get('/api/v1/my-pharmacy/stock/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['quantity'], 100)
        self.assertEqual(response.data[0]['medicine']['name'], 'Paracetamol 500mg')

    def test_plain_user_is_forbidden(self):
        plain = User.objects.create_user(username='plain6', password=self.password)
        self._auth(plain)

        self.assertEqual(self.client.get('/api/v1/my-pharmacy/stock/').status_code, 403)

    def test_anonymous_is_rejected(self):
        self.assertIn(self.client.get('/api/v1/my-pharmacy/stock/').status_code, (401, 403))

    def test_patch_sets_absolute_quantity_and_logs_manual_transaction(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'quantity': 60}, format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 60)
        txn = StockTransaction.objects.get()
        self.assertEqual(txn.quantity_delta, -40)
        self.assertEqual(txn.source, 'MANUAL')
        self.assertEqual(txn.changed_by, self.owner)

    def test_patch_can_change_price_without_touching_quantity(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'price': '12.50'}, format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.stock.refresh_from_db()
        self.assertEqual(str(self.stock.price), '12.50')
        self.assertEqual(self.stock.quantity, 100)
        self.assertEqual(StockTransaction.objects.count(), 0)

    def test_owner_cannot_touch_another_pharmacys_row(self):
        """404 rather than 403 on purpose -- a 403 would confirm the row
        exists, which is itself a leak."""
        other_pharmacy = make_pharmacy('Someone Elses')
        foreign = PharmacyMedicineStock.objects.create(
            pharmacy=other_pharmacy, medicine=self.medicine, quantity=7, price=5,
        )
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{foreign.id}/', {'quantity': 0}, format='json',
        )

        self.assertEqual(response.status_code, 404)
        foreign.refresh_from_db()
        self.assertEqual(foreign.quantity, 7)

    def test_post_adds_a_medicine(self):
        new_medicine = Medicine.objects.create(
            name='Amoxicillin 250mg', category='Antibiotic',
            dosage_form='Capsule', strength='250mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 25, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 201)
        created = PharmacyMedicineStock.objects.get(pharmacy=self.pharmacy, medicine=new_medicine)
        self.assertEqual(created.quantity, 25)
        self.assertEqual(StockTransaction.objects.filter(medicine=new_medicine).count(), 1)

    def test_post_rejects_a_medicine_already_stocked(self):
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': self.medicine.id, 'quantity': 5, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 400)

    def test_delete_zeroes_then_removes_the_row(self):
        """Removing a medicine is 'we no longer carry this', which is not the
        same as a quantity of zero -- so the removal still lands in the
        ledger before the row goes."""
        self._auth(self.owner)

        response = self.client.delete(f'/api/v1/my-pharmacy/stock/{self.stock.id}/')

        self.assertEqual(response.status_code, 204)
        self.assertFalse(PharmacyMedicineStock.objects.filter(id=self.stock.id).exists())
        txn = StockTransaction.objects.get()
        self.assertEqual(txn.quantity_delta, -100)
        self.assertEqual(txn.source, 'MANUAL')

    def test_manual_edit_below_threshold_fires_the_low_stock_alert(self):
        """Routing owner edits through StockTransaction is what makes the
        existing sync/signals.py alert fire on them -- this is the test that
        proves it, since the signal hooks the transaction, not the row."""
        from unittest.mock import patch as mock_patch

        self.stock.low_threshold = 10
        self.stock.save()
        self._auth(self.owner)

        with mock_patch('sync.signals.async_to_sync') as mocked,                 self.captureOnCommitCallbacks(execute=True):
            self.client.patch(
                f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'quantity': 3}, format='json',
            )

        self.assertTrue(mocked.called, 'Low-stock alert did not fire on a manual edit')

    # -- Fix round 1: price validation --------------------------------

    def test_patch_rejects_malformed_price_with_400_not_500(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'price': 'abc'}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(str(self.stock.price), '10.00')

    def test_patch_rejects_null_price_with_400_not_500(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'price': None}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(str(self.stock.price), '10.00')

    def test_patch_rejects_negative_price(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'price': -5}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(str(self.stock.price), '10.00')

    def test_post_rejects_malformed_price_with_400_not_500(self):
        new_medicine = Medicine.objects.create(
            name='Ibuprofen 200mg', category='Analgesic',
            dosage_form='Tablet', strength='200mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 5, 'price': 'abc',
        }, format='json')

        self.assertEqual(response.status_code, 400)

    def test_post_rejects_negative_price(self):
        new_medicine = Medicine.objects.create(
            name='Cetirizine 10mg', category='Antihistamine',
            dosage_form='Tablet', strength='10mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 5, 'price': -1,
        }, format='json')

        self.assertEqual(response.status_code, 400)

    # -- Fix round 1: create/PATCH atomicity across quantity + price ---

    def test_post_with_bad_price_leaves_no_stock_row_or_transaction_behind(self):
        """A malformed price must not leave a half-applied write: no stock
        row, no ledger entry, even though apply_stock_change() already
        committed its own atomic block before the price step failed."""
        new_medicine = Medicine.objects.create(
            name='Domperidone 10mg', category='Antiemetic',
            dosage_form='Tablet', strength='10mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 5, 'price': 'abc',
        }, format='json')

        self.assertEqual(response.status_code, 400)
        self.assertFalse(
            PharmacyMedicineStock.objects.filter(pharmacy=self.pharmacy, medicine=new_medicine).exists()
        )
        self.assertEqual(StockTransaction.objects.filter(medicine=new_medicine).count(), 0)

    def test_patch_with_bad_price_does_not_apply_the_quantity_change(self):
        """When quantity and price are sent together and price is bad, the
        whole PATCH must fail cleanly -- no orphaned quantity change."""
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/',
            {'quantity': 60, 'price': 'abc'}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 100)
        self.assertEqual(StockTransaction.objects.count(), 0)

    # -- Fix round 1: malformed medicine id on POST ---------------------

    def test_post_rejects_non_integer_medicine_id_with_400_not_500(self):
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': 'abc', 'quantity': 5, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 400)

    def test_post_rejects_missing_medicine_id_with_400(self):
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'quantity': 5, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 400)

    # -- Fix round 1: authorization boundary + quantity coverage --------

    def test_owner_cannot_delete_another_pharmacys_row(self):
        """404 rather than 403 on purpose, same as the PATCH case -- a 403
        would confirm the row exists."""
        other_pharmacy = make_pharmacy('Someone Elses')
        foreign = PharmacyMedicineStock.objects.create(
            pharmacy=other_pharmacy, medicine=self.medicine, quantity=7, price=5,
        )
        self._auth(self.owner)

        response = self.client.delete(f'/api/v1/my-pharmacy/stock/{foreign.id}/')

        self.assertEqual(response.status_code, 404)
        foreign.refresh_from_db()
        self.assertEqual(foreign.quantity, 7)

    def test_patch_rejects_negative_quantity(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'quantity': -1}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 100)

    def test_patch_rejects_non_integer_quantity(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'quantity': 'abc'}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 100)

    def test_post_rejects_negative_quantity(self):
        new_medicine = Medicine.objects.create(
            name='Metformin 500mg', category='Antidiabetic',
            dosage_form='Tablet', strength='500mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': -3, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 400)

    def test_post_rejects_non_integer_quantity(self):
        new_medicine = Medicine.objects.create(
            name='Losartan 50mg', category='Antihypertensive',
            dosage_form='Tablet', strength='50mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 'abc', 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 400)

    # -- Fix round 2: alerts that were firing on non-shortages -----------

    def test_delete_does_not_broadcast_a_low_stock_alert(self):
        """Removing a medicine is 'we stopped carrying this', not 'we are
        nearly out'. The zeroing transaction still has to reach the ledger --
        test_delete_zeroes_then_removes_the_row covers that -- but pushing
        'critical, 0 left' about a row that ceases to exist a millisecond later
        points every watching client at the one thing this pharmacy just said
        it no longer stocks."""
        from unittest.mock import patch as mock_patch

        self._auth(self.owner)

        with mock_patch('sync.signals.async_to_sync') as mocked,                 self.captureOnCommitCallbacks(execute=True):
            response = self.client.delete(
                f'/api/v1/my-pharmacy/stock/{self.stock.id}/'
            )

        self.assertEqual(response.status_code, 204)
        self.assertFalse(mocked.called, 'Deleting a medicine raised a shortage alert')
        # The ledger entry is not what was suppressed -- only the broadcast.
        self.assertEqual(StockTransaction.objects.count(), 1)

    def test_adding_a_medicine_does_not_broadcast_a_low_stock_alert(self):
        """low_threshold defaults to 10, so an opening count of 5 -- an
        entirely ordinary thing to type -- used to alert on a number the owner
        was still looking at."""
        from unittest.mock import patch as mock_patch

        new_medicine = Medicine.objects.create(
            name='Omeprazole 20mg', category='Antacid',
            dosage_form='Capsule', strength='20mg',
        )
        self._auth(self.owner)

        with mock_patch('sync.signals.async_to_sync') as mocked,                 self.captureOnCommitCallbacks(execute=True):
            response = self.client.post('/api/v1/my-pharmacy/stock/', {
                'medicine': new_medicine.id, 'quantity': 5, 'price': '8.00',
            }, format='json')

        self.assertEqual(response.status_code, 201)
        self.assertFalse(mocked.called, 'Adding a medicine raised a shortage alert')

    def test_a_later_edit_still_alerts_after_a_suppressed_create(self):
        """The suppression is per-write, not sticky: the row that was added
        quietly must still alert the first time its quantity actually drops."""
        from unittest.mock import patch as mock_patch

        new_medicine = Medicine.objects.create(
            name='Ranitidine 150mg', category='Antacid',
            dosage_form='Tablet', strength='150mg',
        )
        self._auth(self.owner)
        created = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 50, 'price': '8.00',
        }, format='json')

        with mock_patch('sync.signals.async_to_sync') as mocked,                 self.captureOnCommitCallbacks(execute=True):
            self.client.patch(
                f'/api/v1/my-pharmacy/stock/{created.data["id"]}/',
                {'quantity': 2}, format='json',
            )

        self.assertTrue(mocked.called, 'Low-stock alert stopped firing on real edits')

    def test_pos_writes_still_alert(self):
        """alert=False is opt-in per call. Nothing about these fixes may
        quieten the POS path, which is where most real shortages come from."""
        from unittest.mock import patch as mock_patch

        self.stock.low_threshold = 10
        self.stock.save()

        with mock_patch('sync.signals.async_to_sync') as mocked,                 self.captureOnCommitCallbacks(execute=True):
            apply_stock_change(
                self.pharmacy, self.medicine, delta=-95,
                source='POS_SYNC', transaction_type='DISPENSED',
            )

        self.assertTrue(mocked.called)

    # -- Fix round 2: owner-settable low_threshold -----------------------

    def test_patch_sets_the_low_threshold(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/',
            {'low_threshold': 40}, format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['low_threshold'], 40)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.low_threshold, 40)

    def test_threshold_change_alone_writes_no_stock_transaction(self):
        """Retuning an alert is not stock movement, and logging it as an
        ADJUSTED delta-0 row would be noise in the ledger the audit trail
        exists to keep readable."""
        self._auth(self.owner)

        self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/',
            {'low_threshold': 40}, format='json',
        )

        self.assertEqual(StockTransaction.objects.count(), 0)

    def test_a_raised_threshold_applies_to_the_quantity_in_the_same_patch(self):
        """Ordering test. The signal reads low_threshold off the row when the
        transaction lands, so the threshold has to be written BEFORE
        apply_stock_change runs -- otherwise one PATCH carrying both is judged
        against the value the owner just replaced."""
        from unittest.mock import patch as mock_patch

        self.stock.low_threshold = 10
        self.stock.save()
        self._auth(self.owner)

        # 30 is comfortably above the old threshold of 10 and at/below the new
        # one, so this alerts only if the new threshold was applied first.
        with mock_patch('sync.signals.async_to_sync') as mocked,                 self.captureOnCommitCallbacks(execute=True):
            response = self.client.patch(
                f'/api/v1/my-pharmacy/stock/{self.stock.id}/',
                {'quantity': 30, 'low_threshold': 50}, format='json',
            )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(mocked.called, 'The alert was judged against the old threshold')

    def test_post_accepts_a_low_threshold(self):
        new_medicine = Medicine.objects.create(
            name='Salbutamol Inhaler', category='Bronchodilator',
            dosage_form='Inhaler', strength='100mcg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 200,
            'price': '8.00', 'low_threshold': 60,
        }, format='json')

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['low_threshold'], 60)

    def test_post_without_a_low_threshold_keeps_the_model_default(self):
        new_medicine = Medicine.objects.create(
            name='Azithromycin 500mg', category='Antibiotic',
            dosage_form='Tablet', strength='500mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 200, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['low_threshold'], 10)

    def test_patch_rejects_a_negative_low_threshold(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/',
            {'low_threshold': -1}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.low_threshold, 10)

    def test_patch_rejects_a_non_integer_low_threshold(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/',
            {'low_threshold': 'abc'}, format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_a_bad_threshold_does_not_apply_the_quantity_in_the_same_patch(self):
        """Same contract as the price validation round: one rejected field
        rejects the whole request, rather than half-applying it."""
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/',
            {'quantity': 3, 'low_threshold': 'abc'}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 100)
        self.assertEqual(StockTransaction.objects.count(), 0)

    # -- Fix round 3: the duplicate-add race -----------------------------

    def test_rejected_duplicate_leaves_the_existing_row_untouched(self):
        """The rejection must not be the only thing that happened -- the row
        the owner already had has to come out the other side unchanged, with no
        adjustment logged against it."""
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': self.medicine.id, 'quantity': 5, 'price': '999.00',
        }, format='json')

        self.assertEqual(response.status_code, 400)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 100)
        self.assertEqual(str(self.stock.price), '10.00')
        self.assertEqual(StockTransaction.objects.count(), 0)
        self.assertEqual(PharmacyMedicineStock.objects.count(), 1)


class ConcurrentAddTests(TransactionTestCase):
    """TransactionTestCase, not TestCase: these threads need real commits and
    their own connections, which the usual per-test transaction wrapper does
    not give them."""

    def setUp(self):
        self.owner = User.objects.create_user(username='owner7', password='pw123456!')
        self.pharmacy = make_pharmacy('Race Pharmacy')
        PharmacyOwner.objects.create(user=self.owner, pharmacy=self.pharmacy)
        self.medicine = Medicine.objects.create(
            name='Paracetamol 500mg', category='Analgesic',
            dosage_form='Tablet', strength='500mg',
        )

    def test_two_simultaneous_adds_of_the_same_medicine_produce_one_row(self):
        """The race the .exists() pre-check could not win.

        Both requests used to pass the check before either wrote, and
        get_or_create() then quietly handed the second one the first's row --
        so the loser overwrote the winner's quantity and still got a 201. Two
        owners of the same pharmacy adding the same medicine at once is exactly
        when that happens, and neither of them would have seen anything wrong.

        Exactly one 201, exactly one 400, exactly one row, and the surviving
        quantity has to belong to whichever request actually created it.
        """
        results = []
        barrier = threading.Barrier(2)

        def add(quantity):
            def run():
                try:
                    client = APIClient()
                    client.force_authenticate(user=self.owner)
                    barrier.wait()  # line both threads up on the same instant
                    response = client.post('/api/v1/my-pharmacy/stock/', {
                        'medicine': self.medicine.id,
                        'quantity': quantity,
                        'price': '10.00',
                    }, format='json')
                    results.append((quantity, response.status_code))
                finally:
                    connection.close()
            return run

        threads = [threading.Thread(target=add(q)) for q in (30, 70)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        statuses = sorted(code for _, code in results)
        self.assertEqual(statuses, [201, 400], results)
        self.assertEqual(
            PharmacyMedicineStock.objects.filter(pharmacy=self.pharmacy).count(), 1,
        )

        winner = next(q for q, code in results if code == 201)
        stock = PharmacyMedicineStock.objects.get(
            pharmacy=self.pharmacy, medicine=self.medicine,
        )
        self.assertEqual(
            stock.quantity, winner,
            'The rejected request still wrote its quantity over the winner\'s.',
        )
        # One create, one rejection: the rejected attempt must leave no ledger
        # entry behind either.
        self.assertEqual(StockTransaction.objects.count(), 1)

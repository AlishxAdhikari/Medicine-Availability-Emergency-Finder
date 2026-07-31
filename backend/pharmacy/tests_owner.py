from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase
from django.utils import timezone

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

from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase

from pharmacy.models import Pharmacy, PharmacyOwner

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

from django.test import TestCase

# Create your tests here.

from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from pharmacy.models import Pharmacy, PharmacyOwner

User = get_user_model()


class LoginRoleTests(TestCase):
    """The login response is the only thing telling the Flutter client which
    screen to open, so role and pharmacy have to be on it -- a second
    round trip would mean the app briefly doesn't know who it's talking to."""

    def setUp(self):
        self.client = APIClient()
        self.password = 'pw123456!'

    def _login(self, username):
        return self.client.post('/api/v1/auth/login-identifier/', {
            'identifier': username, 'password': self.password,
        }, format='json')

    def test_plain_user_login_reports_user_role(self):
        User.objects.create_user(username='plain', email='p@x.com', password=self.password)

        response = self._login('plain')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['role'], 'user')
        self.assertIsNone(response.data['user']['pharmacy'])

    def test_owner_login_reports_owner_role_and_pharmacy(self):
        user = User.objects.create_user(username='owner', email='o@x.com', password=self.password)
        pharmacy = Pharmacy.objects.create(
            name='Owned Pharmacy', address='A', district='Kathmandu',
            latitude=27.7, longitude=85.3,
        )
        PharmacyOwner.objects.create(user=user, pharmacy=pharmacy)

        response = self._login('owner')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['role'], 'pharmacy_owner')
        self.assertEqual(response.data['user']['pharmacy']['id'], pharmacy.id)
        self.assertEqual(response.data['user']['pharmacy']['name'], 'Owned Pharmacy')


class CurrentUserTests(TestCase):
    """GET /auth/me/ -- what a session resumed without a fresh login uses to
    find out whether it is still (or newly) an owner."""

    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username='resumer', email='r@x.com', password='pw123456!',
        )

    def _make_pharmacy(self):
        return Pharmacy.objects.create(
            name='Owned Pharmacy', address='A', district='Kathmandu',
            latitude=27.7, longitude=85.3,
        )

    def test_anonymous_is_rejected(self):
        self.assertIn(self.client.get('/api/v1/auth/me/').status_code, (401, 403))

    def test_reports_the_plain_user_role(self):
        self.client.force_authenticate(user=self.user)

        response = self.client.get('/api/v1/auth/me/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['username'], 'resumer')
        self.assertEqual(response.data['role'], 'user')
        self.assertIsNone(response.data['pharmacy'])

    def test_reports_ownership_granted_since_the_last_login(self):
        """The case a biometric login could not otherwise discover: staff link
        the pharmacy in admin, and nothing on the device knows."""
        pharmacy = self._make_pharmacy()
        PharmacyOwner.objects.create(user=self.user, pharmacy=pharmacy)
        self.client.force_authenticate(user=self.user)

        response = self.client.get('/api/v1/auth/me/')

        self.assertEqual(response.data['role'], 'pharmacy_owner')
        self.assertEqual(response.data['pharmacy']['id'], pharmacy.id)

    def test_reports_ownership_revoked_since_the_last_login(self):
        pharmacy = self._make_pharmacy()
        link = PharmacyOwner.objects.create(user=self.user, pharmacy=pharmacy)
        link.delete()
        # Authenticate with a freshly loaded instance. Creating the link
        # populated the reverse one-to-one cache on self.user, and deleting the
        # row does not clear it -- so passing that same object to
        # force_authenticate would test Python's cache, not the database. A
        # real request never has this problem: JWTAuthentication loads the user
        # from the DB on every call, which is exactly why the role can be
        # derived from the link rather than stored.
        self.client.force_authenticate(user=User.objects.get(pk=self.user.pk))

        response = self.client.get('/api/v1/auth/me/')

        self.assertEqual(response.data['role'], 'user')
        self.assertIsNone(response.data['pharmacy'])

    def test_never_exposes_another_user(self):
        """No id in the URL: it always resolves to the caller's own token."""
        other = User.objects.create_user(username='someone-else', password='pw123456!')
        self.client.force_authenticate(user=other)

        response = self.client.get('/api/v1/auth/me/')

        self.assertEqual(response.data['username'], 'someone-else')


class EmergencyContactTests(TestCase):
    """Multiple emergency contacts have to survive the round trip.

    The Flutter editor lets you add any number of them and "Alert my
    contacts" addresses the SMS to all of them, but the profile used to hold
    a single name/phone pair -- so everyone after the first was silently
    dropped on save and gone after the next cold start. The symptom was the
    text message only reaching one person, which is the worst possible place
    for this to fail.
    """

    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username='patient', email='p@x.com', password='pw123456!',
        )
        self.client.force_authenticate(self.user)

    def test_saves_and_returns_every_contact(self):
        response = self.client.patch('/api/v1/auth/medical-id/', {
            'emergency_contacts': [
                {'name': 'Aama', 'relationship': 'Mother', 'phone_number': '9841111111'},
                {'name': 'Buwa', 'relationship': 'Father', 'phone_number': '9842222222'},
                {'name': 'Didi', 'relationship': 'Sister', 'phone_number': '9843333333'},
            ],
        }, format='json')

        self.assertEqual(response.status_code, 200)
        contacts = response.data['emergency_contacts']
        self.assertEqual(len(contacts), 3)
        self.assertEqual(
            [c['phone_number'] for c in contacts],
            ['9841111111', '9842222222', '9843333333'],
        )

    def test_contacts_survive_a_refetch(self):
        self.client.patch('/api/v1/auth/medical-id/', {
            'emergency_contacts': [
                {'name': 'Aama', 'relationship': 'Mother', 'phone_number': '9841111111'},
                {'name': 'Buwa', 'relationship': 'Father', 'phone_number': '9842222222'},
            ],
        }, format='json')

        response = self.client.get('/api/v1/auth/medical-id/')

        self.assertEqual(len(response.data['emergency_contacts']), 2)

    def test_legacy_single_contact_fields_mirror_the_first(self):
        """The responder share endpoint and older clients still read these."""
        self.client.patch('/api/v1/auth/medical-id/', {
            'emergency_contacts': [
                {'name': 'Aama', 'relationship': 'Mother', 'phone_number': '9841111111'},
                {'name': 'Buwa', 'relationship': 'Father', 'phone_number': '9842222222'},
            ],
        }, format='json')

        response = self.client.get('/api/v1/auth/medical-id/')

        self.assertEqual(response.data['emergency_contact_name'], 'Aama')
        self.assertEqual(response.data['emergency_contact_phone'], '9841111111')

    def test_replacing_contacts_removes_the_old_ones(self):
        self.client.patch('/api/v1/auth/medical-id/', {
            'emergency_contacts': [
                {'name': 'Aama', 'relationship': 'Mother', 'phone_number': '9841111111'},
                {'name': 'Buwa', 'relationship': 'Father', 'phone_number': '9842222222'},
            ],
        }, format='json')
        self.client.patch('/api/v1/auth/medical-id/', {
            'emergency_contacts': [
                {'name': 'Didi', 'relationship': 'Sister', 'phone_number': '9843333333'},
            ],
        }, format='json')

        response = self.client.get('/api/v1/auth/medical-id/')

        self.assertEqual(len(response.data['emergency_contacts']), 1)
        self.assertEqual(response.data['emergency_contact_name'], 'Didi')

    def test_omitting_contacts_leaves_them_alone(self):
        """A PATCH that only touches blood group must not wipe the contacts."""
        self.client.patch('/api/v1/auth/medical-id/', {
            'emergency_contacts': [
                {'name': 'Aama', 'relationship': 'Mother', 'phone_number': '9841111111'},
            ],
        }, format='json')

        self.client.patch('/api/v1/auth/medical-id/', {'blood_group': 'O+'}, format='json')
        response = self.client.get('/api/v1/auth/medical-id/')

        self.assertEqual(len(response.data['emergency_contacts']), 1)

    def test_shared_responder_view_lists_every_contact(self):
        self.client.patch('/api/v1/auth/medical-id/', {
            'emergency_contacts': [
                {'name': 'Aama', 'relationship': 'Mother', 'phone_number': '9841111111'},
                {'name': 'Buwa', 'relationship': 'Father', 'phone_number': '9842222222'},
            ],
        }, format='json')
        token = self.user.medical_profile.share_token

        anon = APIClient()
        response = anon.get(f'/api/v1/auth/medical-id/share/{token}/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['emergency_contacts']), 2)

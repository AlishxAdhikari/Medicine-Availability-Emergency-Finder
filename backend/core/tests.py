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

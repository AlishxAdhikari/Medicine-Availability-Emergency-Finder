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

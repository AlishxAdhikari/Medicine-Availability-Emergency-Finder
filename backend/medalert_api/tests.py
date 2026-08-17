from unittest.mock import patch

from django.db.utils import OperationalError
from django.urls import reverse
from rest_framework.test import APITestCase


class HealthCheckTests(APITestCase):
    def setUp(self):
        self.url = reverse('health-check')

    def test_reports_ok_when_database_reachable(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['status'], 'ok')
        self.assertEqual(response.data['database'], 'ok')

    def test_reports_503_when_database_unreachable(self):
        # Patches the cursor context manager to raise, so the view's except
        # branch runs without needing to actually take the DB down.
        with patch('medalert_api.views.connection.cursor', side_effect=OperationalError):
            response = self.client.get(self.url)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['status'], 'error')

    def test_requires_no_authentication(self):
        # No credentials attached -- an uptime monitor has none to give.
        response = self.client.get(self.url)
        self.assertNotEqual(response.status_code, 401)
        self.assertNotEqual(response.status_code, 403)
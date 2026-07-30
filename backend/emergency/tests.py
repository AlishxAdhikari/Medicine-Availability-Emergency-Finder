from rest_framework.test import APITestCase

from .models import AmbulanceProvider, BloodBank


class DistrictsEndpointTests(APITestCase):
    """The app's district filter chips are built from these endpoints, so a
    district with rows must never be missing from the response."""

    def setUp(self):
        for district in ['Kathmandu', 'Kathmandu', 'Pokhara', 'Chitwan']:
            AmbulanceProvider.objects.create(
                name=f'{district} Ambulance {AmbulanceProvider.objects.count()}',
                service_type='private',
                district=district,
                phone='9800000000',
            )
        for district in ['Lalitpur', 'Lalitpur']:
            BloodBank.objects.create(
                name=f'{district} Blood Bank {BloodBank.objects.count()}',
                district=district,
                latitude=27.6,
                longitude=85.3,
                operating_hours='24/7',
            )

    def test_ambulance_districts_are_distinct_and_sorted(self):
        response = self.client.get('/api/v1/ambulances/districts/')
        self.assertEqual(response.status_code, 200)
        # Kathmandu has two providers but must appear once -- the view clears
        # order_by('name') so DISTINCT applies to the district alone.
        self.assertEqual(response.data, ['Chitwan', 'Kathmandu', 'Pokhara'])

    def test_blood_bank_districts_are_distinct(self):
        response = self.client.get('/api/v1/blood-banks/districts/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, ['Lalitpur'])


class AmbulancePaginationTests(APITestCase):
    """Regression test for districts disappearing from the app once the
    dataset outgrew one page: the client filtered a single fetched page
    client-side, so rows past PAGE_SIZE were unreachable."""

    def setUp(self):
        # 'Zzz' sorts last by name, so these land on page 2 of 25 rows.
        for i in range(22):
            AmbulanceProvider.objects.create(
                name=f'Aaa Ambulance {i:02d}',
                service_type='private',
                district='Kathmandu',
                phone='9800000000',
            )
        for i in range(3):
            AmbulanceProvider.objects.create(
                name=f'Zzz Ambulance {i:02d}',
                service_type='private',
                district='Pokhara',
                phone='9800000000',
            )

    def test_last_district_is_absent_from_the_first_page(self):
        response = self.client.get('/api/v1/ambulances/')
        names = [row['district'] for row in response.data['results']]
        self.assertNotIn('Pokhara', names)
        self.assertIsNotNone(response.data['next'])

    def test_district_filter_returns_rows_that_fall_past_the_first_page(self):
        response = self.client.get('/api/v1/ambulances/', {'district': 'Pokhara'})
        self.assertEqual(response.data['count'], 3)
        self.assertEqual(len(response.data['results']), 3)

    def test_second_page_is_reachable_by_page_number(self):
        response = self.client.get('/api/v1/ambulances/', {'page': 2})
        self.assertEqual(len(response.data['results']), 5)
        self.assertIsNone(response.data['next'])

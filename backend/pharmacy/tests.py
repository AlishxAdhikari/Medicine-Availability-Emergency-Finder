"""Tests for the public (unauthenticated) pharmacy API and the geo helpers.

The owner-facing write API is covered separately and thoroughly in
tests_owner.py. This file covers what a logged-out user hits -- search,
filtering and proximity sorting -- which had no tests at all.
"""
from django.urls import reverse
from rest_framework.test import APITestCase

from .filters import MedicineFilter, PharmacyFilter
from .models import Medicine, Pharmacy
from .services import haversine_km, sort_by_proximity


# Real coordinates, so the distance assertions below mean something. The
# Kathmandu/Pokhara pair is roughly 140 km apart along the great circle.
KATHMANDU = (27.7172, 85.3240)
PATAN = (27.6766, 85.3188)          # ~4.5 km from Kathmandu
BHAKTAPUR = (27.6710, 85.4298)      # ~11 km from Kathmandu
POKHARA = (28.2096, 83.9856)        # ~140 km from Kathmandu


def make_pharmacy(name, lat, lng, **kwargs):
    defaults = {
        'address': f'{name} Road',
        'district': 'Kathmandu',
        'latitude': lat,
        'longitude': lng,
    }
    defaults.update(kwargs)
    return Pharmacy.objects.create(name=name, **defaults)


class HaversineTests(APITestCase):
    def test_zero_distance_to_itself(self):
        self.assertAlmostEqual(haversine_km(*KATHMANDU, *KATHMANDU), 0, places=6)

    def test_known_distance_kathmandu_to_pokhara(self):
        # ~140 km. Loose tolerance because the exact figure depends on the
        # earth radius constant; the point is to catch a formula that is wrong
        # by a factor (degrees vs radians, or a missing sqrt), not to pin the
        # last kilometre.
        distance = haversine_km(*KATHMANDU, *POKHARA)
        self.assertAlmostEqual(distance, 140, delta=10)

    def test_short_distance_kathmandu_to_patan(self):
        distance = haversine_km(*KATHMANDU, *PATAN)
        self.assertAlmostEqual(distance, 4.5, delta=1.5)

    def test_is_symmetric(self):
        self.assertAlmostEqual(
            haversine_km(*KATHMANDU, *POKHARA),
            haversine_km(*POKHARA, *KATHMANDU),
            places=6,
        )


class SortByProximityTests(APITestCase):
    def setUp(self):
        # Deliberately created furthest-first, so a passing ordering assertion
        # cannot be an accident of insertion order.
        self.pokhara = make_pharmacy('Pokhara Pharmacy', *POKHARA, district='Kaski')
        self.bhaktapur = make_pharmacy('Bhaktapur Pharmacy', *BHAKTAPUR)
        self.patan = make_pharmacy('Patan Pharmacy', *PATAN)

    def test_orders_nearest_first(self):
        results = sort_by_proximity(Pharmacy.objects.all(), *KATHMANDU)
        self.assertEqual(
            [p.name for p in results],
            ['Patan Pharmacy', 'Bhaktapur Pharmacy', 'Pokhara Pharmacy'],
        )

    def test_annotates_distance_km(self):
        results = sort_by_proximity(Pharmacy.objects.all(), *KATHMANDU)
        for pharmacy in results:
            self.assertIsNotNone(getattr(pharmacy, 'distance_km', None))
        # Rounded to 2dp by the helper, which is what the serializer exposes.
        self.assertEqual(results[0].distance_km, round(results[0].distance_km, 2))

    def test_radius_excludes_further_rows(self):
        results = sort_by_proximity(Pharmacy.objects.all(), *KATHMANDU, radius_km=20)
        names = [p.name for p in results]
        self.assertIn('Patan Pharmacy', names)
        self.assertIn('Bhaktapur Pharmacy', names)
        self.assertNotIn('Pokhara Pharmacy', names)

    def test_radius_of_zero_excludes_everything(self):
        # Guards the `if radius_km is not None` check specifically: a falsy-but
        # -meaningful 0 must not be treated as "no radius given".
        results = sort_by_proximity(Pharmacy.objects.all(), *KATHMANDU, radius_km=0)
        self.assertEqual(results, [])

    def test_empty_queryset_returns_empty_list(self):
        results = sort_by_proximity(Pharmacy.objects.none(), *KATHMANDU)
        self.assertEqual(results, [])


class PharmacyListProximityTests(APITestCase):
    """Covers ProximityListMixin as reached through the pharmacy endpoint."""

    def setUp(self):
        self.url = reverse('pharmacy-list')
        self.patan = make_pharmacy('Patan Pharmacy', *PATAN)
        self.pokhara = make_pharmacy('Pokhara Pharmacy', *POKHARA, district='Kaski')

    def test_lists_without_coordinates(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['count'], 2)

    def test_sorts_by_distance_when_coordinates_given(self):
        response = self.client.get(
            self.url, {'lat': KATHMANDU[0], 'lng': KATHMANDU[1]}
        )
        self.assertEqual(response.status_code, 200)
        names = [row['name'] for row in response.data['results']]
        self.assertEqual(names[0], 'Patan Pharmacy')

    def test_radius_filters_results(self):
        response = self.client.get(
            self.url,
            {'lat': KATHMANDU[0], 'lng': KATHMANDU[1], 'radius_km': 20},
        )
        self.assertEqual(response.status_code, 200)
        names = [row['name'] for row in response.data['results']]
        self.assertEqual(names, ['Patan Pharmacy'])

    def test_non_numeric_lat_is_400_not_500(self):
        response = self.client.get(self.url, {'lat': 'here', 'lng': '85.3'})
        self.assertEqual(response.status_code, 400)

    def test_non_numeric_radius_is_400_not_500(self):
        response = self.client.get(
            self.url,
            {'lat': KATHMANDU[0], 'lng': KATHMANDU[1], 'radius_km': 'near'},
        )
        self.assertEqual(response.status_code, 400)

    def test_lat_without_lng_is_ignored_rather_than_erroring(self):
        # Half a coordinate pair cannot be used, but it is not worth a 400
        # either -- the documented behaviour is to fall back to normal listing.
        response = self.client.get(self.url, {'lat': KATHMANDU[0]})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['count'], 2)


class PharmacyFilterTests(APITestCase):
    def setUp(self):
        self.url = reverse('pharmacy-list')
        make_pharmacy('Everest Medical', *PATAN, district='Lalitpur', is_24_hour=True)
        make_pharmacy('Himalaya Drugs', *BHAKTAPUR, district='Bhaktapur', is_verified=True)

    def test_search_matches_name(self):
        response = self.client.get(self.url, {'search': 'Everest'})
        self.assertEqual(
            [row['name'] for row in response.data['results']], ['Everest Medical']
        )

    def test_search_matches_district(self):
        response = self.client.get(self.url, {'search': 'Bhaktapur'})
        self.assertEqual(
            [row['name'] for row in response.data['results']], ['Himalaya Drugs']
        )

    def test_search_is_case_insensitive(self):
        response = self.client.get(self.url, {'search': 'everest'})
        self.assertEqual(response.data['count'], 1)

    def test_filters_by_district(self):
        response = self.client.get(self.url, {'district': 'Lalitpur'})
        self.assertEqual(
            [row['name'] for row in response.data['results']], ['Everest Medical']
        )

    def test_filters_by_is_24_hour(self):
        queryset = PharmacyFilter(
            {'is_24_hour': 'true'}, queryset=Pharmacy.objects.all()
        ).qs
        self.assertEqual([p.name for p in queryset], ['Everest Medical'])

    def test_filters_by_is_verified(self):
        queryset = PharmacyFilter(
            {'is_verified': 'true'}, queryset=Pharmacy.objects.all()
        ).qs
        self.assertEqual([p.name for p in queryset], ['Himalaya Drugs'])


class MedicineFilterTests(APITestCase):
    def setUp(self):
        self.url = reverse('medicine-list')
        Medicine.objects.create(
            name='Paracetamol', generic_name='Acetaminophen', brand='Calpol',
            category='Analgesic', dosage_form='Tablet', strength='500mg',
            is_essential=True,
        )
        Medicine.objects.create(
            name='Amoxicillin', generic_name='Amoxycillin', brand='Amoxil',
            category='Antibiotic', dosage_form='Capsule', strength='250mg',
            requires_prescription=True,
        )

    def test_search_matches_name(self):
        response = self.client.get(self.url, {'search': 'Paracetamol'})
        self.assertEqual(
            [row['name'] for row in response.data['results']], ['Paracetamol']
        )

    def test_search_matches_generic_name(self):
        # The whole point of the combined `search` param: people look up the
        # generic name as readily as the brand.
        response = self.client.get(self.url, {'search': 'Acetaminophen'})
        self.assertEqual(
            [row['name'] for row in response.data['results']], ['Paracetamol']
        )

    def test_search_matches_brand(self):
        response = self.client.get(self.url, {'search': 'Amoxil'})
        self.assertEqual(
            [row['name'] for row in response.data['results']], ['Amoxicillin']
        )

    def test_filters_by_category(self):
        queryset = MedicineFilter(
            {'category': 'Antibiotic'}, queryset=Medicine.objects.all()
        ).qs
        self.assertEqual([m.name for m in queryset], ['Amoxicillin'])

    def test_filters_by_requires_prescription(self):
        queryset = MedicineFilter(
            {'requires_prescription': 'true'}, queryset=Medicine.objects.all()
        ).qs
        self.assertEqual([m.name for m in queryset], ['Amoxicillin'])

    def test_filters_by_is_essential(self):
        queryset = MedicineFilter(
            {'is_essential': 'true'}, queryset=Medicine.objects.all()
        ).qs
        self.assertEqual([m.name for m in queryset], ['Paracetamol'])

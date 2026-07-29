import random

from django.core.management.base import BaseCommand
from django.db import transaction
from faker import Faker

from emergency.models import AmbulanceProvider, BloodBank, BloodStock

fake = Faker()

# Same 6 districts + coordinates as pharmacy/management/commands/seed_pharmacies.py,
# kept identical on purpose so blood banks and pharmacies land in the same
# realistic geographic clusters for proximity-sort demos.
DISTRICTS = {
    'Kathmandu': (27.7172, 85.3240),
    'Lalitpur': (27.6644, 85.3188),
    'Bhaktapur': (27.6710, 85.4298),
    'Pokhara': (28.2096, 83.9856),
    'Chitwan': (27.5291, 84.3542),
    'Biratnagar': (26.4525, 87.2718),
}

BLOOD_BANK_NAME_TEMPLATES = [
    "{place} Blood Bank",
    "{place} Central Blood Transfusion Service",
    "Red Cross Blood Bank, {place}",
    "{place} Regional Blood Centre",
    "{place} Life Blood Bank",
]

BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']

# Weighted so most groups look reasonably stocked and a couple look low/
# critical -- gives the low-stock UI something realistic to render instead
# of everything being uniformly "adequate".
LEVEL_WEIGHTS = [
    ('adequate', 55),
    ('low', 25),
    ('critical', 15),
    ('unavailable', 5),
]

AMBULANCE_NAME_TEMPLATES = [
    "{place} Ambulance Service",
    "{place} Emergency Medical Service",
    "{place} Rescue & Ambulance",
    "Community Ambulance, {place}",
]

SERVICE_TYPES = ['government', 'private', 'ngo']

# Curated, real-sounding Kathmandu providers -- used instead of the generic
# templates above specifically for Kathmandu, since that's the district
# most likely to be shown in a live demo. Fields: (name, service_type,
# is_24_hour, has_icu, has_oxygen, phone).
KATHMANDU_AMBULANCES = [
    ('Nepal Ambulance Service', 'ngo', True, True, True, '9801000000'),
    ('Nepal Police Ambulance', 'government', True, False, True, '100'),
    ('Bir Hospital Ambulance', 'government', True, True, True, '01-4221119'),
    ('Om Hospital Ambulance Service', 'private', True, True, True, '01-4468711'),
    ('Norvic Hospital Ambulance', 'private', True, True, True, '01-4258554'),
    ('Nepal Red Cross Ambulance', 'ngo', False, False, True, '1130'),
    ('Grande International Hospital Ambulance', 'private', True, True, True, '01-5159266'),
    ('Kathmandu Model Hospital Ambulance', 'private', True, False, True, '01-4271119'),
]


class Command(BaseCommand):
    help = "Seeds demo blood banks, blood stock, and ambulance providers across 6 districts."

    def add_arguments(self, parser):
        parser.add_argument(
            '--banks-per-district', type=int, default=2,
            help='Blood banks to create per district (default: %(default)s)',
        )
        parser.add_argument(
            '--ambulances-per-district', type=int, default=3,
            help='Generic ambulances to create per NON-Kathmandu district (default: %(default)s). '
                 'Kathmandu always gets the full curated list below regardless of this number.',
        )
        parser.add_argument(
            '--clear', action='store_true',
            help='Delete all existing BloodBank/BloodStock/AmbulanceProvider rows first.',
        )

    @transaction.atomic
    def handle(self, *args, **options):
        if options['clear']:
            BloodStock.objects.all().delete()
            BloodBank.objects.all().delete()
            AmbulanceProvider.objects.all().delete()
            self.stdout.write(self.style.WARNING('Cleared existing emergency data.'))

        bank_count = 0
        stock_count = 0
        ambulance_count = 0

        for district, (lat, lng) in DISTRICTS.items():
            for _ in range(options['banks_per_district']):
                bank = self._create_blood_bank(district, lat, lng)
                bank_count += 1
                stock_count += self._create_stock_for_bank(bank)

            if district == 'Kathmandu':
                # Curated, recognizable names instead of generic templates --
                # get_or_create so re-running the command doesn't duplicate
                # these even without --clear.
                for name, service_type, is_24, has_icu, has_oxygen, phone in KATHMANDU_AMBULANCES:
                    _, created = AmbulanceProvider.objects.get_or_create(
                        name=name,
                        defaults=dict(
                            service_type=service_type, district=district,
                            is_24_hour=is_24, has_icu=has_icu, has_oxygen=has_oxygen,
                            phone=phone,
                        ),
                    )
                    if created:
                        ambulance_count += 1
            else:
                for _ in range(options['ambulances_per_district']):
                    self._create_ambulance(district)
                    ambulance_count += 1

        self.stdout.write(self.style.SUCCESS(
            f"Seeded {bank_count} blood banks ({stock_count} stock rows) and "
            f"{ambulance_count} new ambulance providers across {len(DISTRICTS)} districts "
            f"(Kathmandu uses curated real-sounding names)."
        ))

    def _create_blood_bank(self, district, lat, lng):
        name = random.choice(BLOOD_BANK_NAME_TEMPLATES).format(place=district)
        # Small jitter so multiple banks in the same district aren't stacked
        # on the exact same coordinate.
        jitter = lambda v: v + random.uniform(-0.03, 0.03)
        return BloodBank.objects.create(
            name=name,
            district=district,
            latitude=jitter(lat),
            longitude=jitter(lng),
            operating_hours=random.choice(['24 hours', '8:00 AM - 6:00 PM', '9:00 AM - 5:00 PM']),
            phone=fake.msisdn()[:10],
        )

    def _create_stock_for_bank(self, bank):
        levels = [lvl for lvl, _ in LEVEL_WEIGHTS]
        weights = [w for _, w in LEVEL_WEIGHTS]
        count = 0
        for group in BLOOD_GROUPS:
            BloodStock.objects.create(
                bank=bank,
                blood_group=group,
                level=random.choices(levels, weights=weights, k=1)[0],
            )
            count += 1
        return count

    def _create_ambulance(self, district):
        name = random.choice(AMBULANCE_NAME_TEMPLATES).format(place=district)
        AmbulanceProvider.objects.create(
            name=name,
            service_type=random.choice(SERVICE_TYPES),
            district=district,
            is_24_hour=random.random() < 0.6,
            has_icu=random.random() < 0.5,
            has_oxygen=random.random() < 0.75,
            phone=fake.msisdn()[:10],
        )
import random
from django.core.management.base import BaseCommand
from django.db import transaction
from faker import Faker

from pharmacy.models import Pharmacy, Medicine, PharmacyMedicineStock

fake = Faker()

# 6 districts, each with an approximate lat/lng center so generated
# pharmacies land in a realistic-looking cluster instead of pure noise.
DISTRICTS = {
    'Kathmandu': (27.7172, 85.3240),
    'Lalitpur': (27.6644, 85.3188),
    'Bhaktapur': (27.6710, 85.4298),
    'Pokhara': (28.2096, 83.9856),
    'Chitwan': (27.5291, 84.3542),
    'Biratnagar': (26.4525, 87.2718),
}

PHARMACY_NAME_TEMPLATES = [
    "{place} Pharmacy",
    "{place} Medical Hall",
    "{place} Drug Store",
    "{place} Health Care Pharmacy",
    "New {place} Pharmacy",
    "{place} Sanjivani Pharmacy",
]

MEDICINES = [
    # (name, generic_name, category, dosage_form, strength, is_essential, requires_prescription)
    ("Paracetamol 500mg", "Paracetamol", "Analgesic", "Tablet", "500mg", True, False),
    ("Ibuprofen 400mg", "Ibuprofen", "NSAID", "Tablet", "400mg", True, False),
    ("Amoxicillin 500mg", "Amoxicillin", "Antibiotic", "Capsule", "500mg", True, True),
    ("Azithromycin 500mg", "Azithromycin", "Antibiotic", "Tablet", "500mg", True, True),
    ("Ciprofloxacin 500mg", "Ciprofloxacin", "Antibiotic", "Tablet", "500mg", False, True),
    ("Omeprazole 20mg", "Omeprazole", "Antacid / PPI", "Capsule", "20mg", True, False),
    ("Pantoprazole 40mg", "Pantoprazole", "Antacid / PPI", "Tablet", "40mg", False, False),
    ("Cetirizine 10mg", "Cetirizine", "Antihistamine", "Tablet", "10mg", True, False),
    ("Loratadine 10mg", "Loratadine", "Antihistamine", "Tablet", "10mg", False, False),
    ("Metformin 500mg", "Metformin", "Antidiabetic", "Tablet", "500mg", True, True),
    ("Glimepiride 2mg", "Glimepiride", "Antidiabetic", "Tablet", "2mg", False, True),
    ("Insulin Glargine", "Insulin Glargine", "Antidiabetic", "Injection", "100IU/ml", True, True),
    ("Amlodipine 5mg", "Amlodipine", "Antihypertensive", "Tablet", "5mg", True, True),
    ("Losartan 50mg", "Losartan", "Antihypertensive", "Tablet", "50mg", True, True),
    ("Atenolol 50mg", "Atenolol", "Antihypertensive", "Tablet", "50mg", False, True),
    ("Atorvastatin 20mg", "Atorvastatin", "Statin", "Tablet", "20mg", True, True),
    ("Aspirin 75mg", "Aspirin", "Antiplatelet", "Tablet", "75mg", True, False),
    ("Salbutamol Inhaler", "Salbutamol", "Bronchodilator", "Inhaler", "100mcg", True, False),
    ("Montelukast 10mg", "Montelukast", "Anti-asthmatic", "Tablet", "10mg", False, True),
    ("Prednisolone 5mg", "Prednisolone", "Corticosteroid", "Tablet", "5mg", False, True),
    ("Dexamethasone 0.5mg", "Dexamethasone", "Corticosteroid", "Tablet", "0.5mg", True, True),
    ("ORS Sachet", "Oral Rehydration Salts", "Rehydration", "Powder", "21g", True, False),
    ("Zinc Sulphate 20mg", "Zinc Sulphate", "Supplement", "Tablet", "20mg", True, False),
    ("Domperidone 10mg", "Domperidone", "Antiemetic", "Tablet", "10mg", False, False),
    ("Ondansetron 4mg", "Ondansetron", "Antiemetic", "Tablet", "4mg", False, True),
    ("Metronidazole 400mg", "Metronidazole", "Antiprotozoal", "Tablet", "400mg", True, True),
    ("Diclofenac Gel", "Diclofenac", "NSAID", "Gel", "1%", False, False),
    ("Tramadol 50mg", "Tramadol", "Analgesic", "Capsule", "50mg", False, True),
    ("Diazepam 5mg", "Diazepam", "Anxiolytic", "Tablet", "5mg", False, True),
    ("Sertraline 50mg", "Sertraline", "Antidepressant", "Tablet", "50mg", False, True),
    ("Vitamin D3 60000IU", "Cholecalciferol", "Supplement", "Capsule", "60000IU", False, False),
    ("Vitamin B Complex", "Vitamin B Complex", "Supplement", "Tablet", "-", False, False),
    ("Folic Acid 5mg", "Folic Acid", "Supplement", "Tablet", "5mg", True, False),
    ("Iron + Folic Acid", "Ferrous Sulphate", "Supplement", "Tablet", "200mg", True, False),
    ("Calcium Carbonate 500mg", "Calcium Carbonate", "Supplement", "Tablet", "500mg", False, False),
    ("Ranitidine 150mg", "Ranitidine", "Antacid", "Tablet", "150mg", False, False),
    ("Loperamide 2mg", "Loperamide", "Antidiarrheal", "Capsule", "2mg", True, False),
    ("Chlorpheniramine 4mg", "Chlorpheniramine", "Antihistamine", "Tablet", "4mg", False, False),
    ("Hydrocortisone Cream", "Hydrocortisone", "Corticosteroid", "Cream", "1%", False, False),
    ("Clotrimazole Cream", "Clotrimazole", "Antifungal", "Cream", "1%", False, False),
    ("Fluconazole 150mg", "Fluconazole", "Antifungal", "Capsule", "150mg", False, True),
    ("Doxycycline 100mg", "Doxycycline", "Antibiotic", "Capsule", "100mg", False, True),
    ("Cefixime 200mg", "Cefixime", "Antibiotic", "Tablet", "200mg", True, True),
    ("Levocetirizine 5mg", "Levocetirizine", "Antihistamine", "Tablet", "5mg", False, False),
    ("Multivitamin Syrup", "Multivitamin", "Supplement", "Syrup", "200ml", False, False),
    ("Paracetamol Syrup (Child)", "Paracetamol", "Analgesic", "Syrup", "120mg/5ml", True, False),
    ("Amoxicillin Syrup (Child)", "Amoxicillin", "Antibiotic", "Syrup", "125mg/5ml", True, True),
    ("Ibuprofen Syrup (Child)", "Ibuprofen", "NSAID", "Syrup", "100mg/5ml", False, False),
    ("Betadine Solution", "Povidone Iodine", "Antiseptic", "Solution", "10%", True, False),
    ("Normal Saline IV", "Sodium Chloride", "IV Fluid", "Injection", "0.9% 500ml", True, True),
]

BRANDS = ["Generic", "Nepa", "Deurali", "CDL", "Ohm Labs", "Time", "Shivam", "Lomus", ""]


class Command(BaseCommand):
    help = "Seeds the database with sample pharmacies, medicines, and stock rows for local development."

    def add_arguments(self, parser):
        parser.add_argument('--pharmacies', type=int, default=30, help='Number of pharmacies to create (default: 30)')
        parser.add_argument('--flush', action='store_true', help='Delete existing pharmacy data before seeding')

    @transaction.atomic
    def handle(self, *args, **options):
        pharmacy_count = options['pharmacies']
        if options['flush']:
            self.stdout.write('Flushing existing pharmacy data...')
            PharmacyMedicineStock.objects.all().delete()
            Pharmacy.objects.all().delete()
            Medicine.objects.all().delete()

        medicines = self._seed_medicines()
        pharmacies = self._seed_pharmacies(pharmacy_count)
        stock_count = self._seed_stock(pharmacies, medicines)

        self.stdout.write(self.style.SUCCESS(
            f"Seeded {len(pharmacies)} pharmacies, {len(medicines)} medicines, "
            f"{stock_count} stock rows across {len(DISTRICTS)} districts."
        ))

    def _seed_medicines(self):
        medicines = []
        for name, generic, category, form, strength, essential, rx in MEDICINES:
            medicine, _ = Medicine.objects.get_or_create(
                name=name,
                defaults=dict(
                    generic_name=generic,
                    brand=random.choice(BRANDS),
                    category=category,
                    dosage_form=form,
                    strength=strength,
                    is_essential=essential,
                    requires_prescription=rx,
                ),
            )
            medicines.append(medicine)
        return medicines

    def _seed_pharmacies(self, count):
        pharmacies = []
        districts = list(DISTRICTS.keys())
        for i in range(count):
            district = districts[i % len(districts)]
            base_lat, base_lng = DISTRICTS[district]
            place = fake.city_suffix().strip() or fake.street_name().split()[0]
            name_template = random.choice(PHARMACY_NAME_TEMPLATES)
            name = name_template.format(place=fake.last_name())

            pharmacy = Pharmacy.objects.create(
                name=name,
                address=f"{fake.street_address()}, {district}",
                district=district,
                # small jitter so pins don't stack exactly on the district center
                latitude=base_lat + random.uniform(-0.05, 0.05),
                longitude=base_lng + random.uniform(-0.05, 0.05),
                is_24_hour=random.random() < 0.2,
                is_verified=random.random() < 0.6,
                phone=fake.msisdn()[:10],
            )
            pharmacies.append(pharmacy)
        return pharmacies

    def _seed_stock(self, pharmacies, medicines):
        rows = []
        for pharmacy in pharmacies:
            # Each pharmacy stocks a random subset of medicines, not all of them
            stocked_medicines = random.sample(medicines, k=random.randint(15, len(medicines)))
            for medicine in stocked_medicines:
                rows.append(PharmacyMedicineStock(
                    pharmacy=pharmacy,
                    medicine=medicine,
                    quantity=random.choice([0, 0, 3, 5, 8, 15, 25, 50, 100, 200]),
                    price=round(random.uniform(5, 850), 2),
                    low_threshold=random.choice([5, 10, 15, 20]),
                ))
        PharmacyMedicineStock.objects.bulk_create(rows, ignore_conflicts=True)
        return len(rows)

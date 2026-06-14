from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from core.models import (
    Pharmacy,
    MedicineCategory,
    Medicine,
    PharmacyMedicineStock,
    BloodBank,
    BloodStock,
    AmbulanceProvider,
    MedicalProfile
)
import random

class Command(BaseCommand):
    help = 'Seeds the database with realistic Nepal medical data (pharmacies, blood banks, medicines, ambulances).'

    def handle(self, *args, **kwargs):
        self.stdout.write('Seeding data...')

        # 1. Superuser
        superuser, created = User.objects.get_or_create(
            username='admin',
            defaults={
                'email': 'admin@medalert.np',
                'is_staff': True,
                'is_superuser': True,
            }
        )
        if created:
            superuser.set_password('admin123')
            superuser.save()
            self.stdout.write('Created superuser (admin / admin123)')

        # 2. Medicine Categories
        categories_data = [
            ('Analgesics', 'medication'),
            ('Antibiotics', 'bug_report'),
            ('Respiratory', 'air'),
            ('Gastrointestinal', 'healing'),
            ('Cardiovascular', 'favorite'),
        ]
        categories = {}
        for name, icon in categories_data:
            cat, _ = MedicineCategory.objects.get_or_create(name=name, defaults={'icon': icon})
            categories[name] = cat

        self.stdout.write(f'Seeded {len(categories)} medicine categories.')

        # 3. Medicines
        medicines_data = [
            # Analgesics
            ('Paracetamol 500mg', 'Paracetamol', 'Napa', 'Analgesics', 'tablet', '500mg', 'Pain and fever relief', True, False),
            ('Ibuprofen 400mg', 'Ibuprofen', 'Brufen', 'Analgesics', 'tablet', '400mg', 'NSAID for pain & inflammation', False, False),
            # Antibiotics
            ('Amoxicillin 250mg', 'Amoxicillin', 'Amoxil', 'Antibiotics', 'capsule', '250mg', 'Broad-spectrum antibiotic', True, True),
            ('Azithromycin 500mg', 'Azithromycin', 'Azith', 'Antibiotics', 'tablet', '500mg', 'Macrolide antibiotic', False, True),
            # Respiratory
            ('Salbutamol Inhaler', 'Salbutamol', 'Asthalin', 'Respiratory', 'inhaler', '100mcg', 'Bronchodilator for asthma relief', True, False),
            ('Montelukast 10mg', 'Montelukast', 'Montair', 'Respiratory', 'tablet', '10mg', 'Leukotriene receptor antagonist', False, False),
            # Gastrointestinal
            ('Pantoprazole 400mg', 'Pantoprazole', 'Pan-40', 'Gastrointestinal', 'tablet', '40mg', 'Proton pump inhibitor', False, False),
            ('ORS Sachet', 'Oral Rehydration Salts', 'Jeevan Jal', 'Gastrointestinal', 'powder', '20.5g', 'Dehydration treatment/support', True, False),
            # Cardiovascular
            ('Amlodipine 5mg', 'Amlodipine', 'Amlodac', 'Cardiovascular', 'tablet', '5mg', 'Calcium channel blocker for BP', True, True),
            ('Atenolol 50mg', 'Atenolol', 'Aten', 'Cardiovascular', 'tablet', '50mg', 'Beta-blocker for hypertension', False, True),
        ]

        medicines_list = []
        for name, generic, brand, cat_name, form, strength, desc, essential, rx in medicines_data:
            med, _ = Medicine.objects.get_or_create(
                generic_name=generic,
                strength=strength,
                dosage_form=form,
                defaults={
                    'name': name,
                    'brand_name': brand,
                    'category': categories[cat_name],
                    'description': desc,
                    'is_essential': essential,
                    'requires_prescription': rx,
                }
            )
            medicines_list.append(med)

        self.stdout.write(f'Seeded {len(medicines_list)} medicines in catalogue.')

        # 4. Pharmacies
        pharmacies_data = [
            ('Kathmandu Clinic Pharmacy', 'kathmandu-clinic-pharmacy', 'Tripureshwor, Kathmandu', 'Kathmandu', '+97714260000', 85.315, 27.695, True, 'verified'),
            ('Patan Lalitpur Pharmacy', 'patan-lalitpur-pharmacy', 'Lagankhel, Patan', 'Lalitpur', '+97715520000', 85.322, 27.668, False, 'verified'),
            ('Bhaktapur Emergency Pharmacy', 'bhaktapur-emergency-pharmacy', 'Dudhpati, Bhaktapur', 'Bhaktapur', '+97716610000', 85.421, 27.672, True, 'verified'),
            ('Thamel 24/7 Meds', 'thamel-24-7-meds', 'Thamel, Kathmandu', 'Kathmandu', '+97714410000', 85.311, 27.715, True, 'verified'),
            ('Maharajgunj Medical Center', 'maharajgunj-medical-center', 'Maharajgunj, Kathmandu', 'Kathmandu', '+97714720000', 85.331, 27.735, False, 'pending'),
        ]

        pharmacies = []
        for name, slug, addr, dist, phone, lon, lat, is_24h, status in pharmacies_data:
            ph, _ = Pharmacy.objects.get_or_create(
                slug=slug,
                defaults={
                    'name': name,
                    'address': addr,
                    'district': dist,
                    'phone': phone,
                    'longitude': lon,
                    'latitude': lat,
                    'is_24h': is_24h,
                    'verification_status': status,
                    'is_active': True,
                    'managed_by': superuser,
                }
            )
            pharmacies.append(ph)

        self.stdout.write(f'Seeded {len(pharmacies)} pharmacies.')

        # 5. Pharmacy Stock Junctions
        availabilities = [
            PharmacyMedicineStock.Availability.AVAILABLE,
            PharmacyMedicineStock.Availability.LOW_STOCK,
            PharmacyMedicineStock.Availability.OUT_OF_STOCK
        ]

        stock_count = 0
        for ph in pharmacies:
            # Randomly link about 7 medicines to each pharmacy
            chosen_meds = random.sample(medicines_list, k=min(7, len(medicines_list)))
            for med in chosen_meds:
                avail = random.choice(availabilities)
                qty = random.randint(0, 100) if avail != PharmacyMedicineStock.Availability.OUT_OF_STOCK else 0
                price = round(random.uniform(10, 500), 2)
                
                PharmacyMedicineStock.objects.get_or_create(
                    pharmacy=ph,
                    medicine=med,
                    defaults={
                        'availability': avail,
                        'price_npr': price,
                        'quantity_on_hand': qty,
                        'notes': f'Fresh batch. Last verification: just now.',
                        'last_verified_by': superuser,
                    }
                )
                stock_count += 1

        self.stdout.write(f'Seeded {stock_count} medicine stock entries.')

        # 6. Blood Banks
        blood_banks_data = [
            ('Central Blood Bank (Red Cross)', 'Exhibition Road, Kathmandu', 'Kathmandu', '+97714225344', 85.320, 27.702, True, True),
            ('Lalitpur Blood Bank Depot', 'Lagankhel, Patan', 'Lalitpur', '+97715523000', 85.321, 27.669, True, False),
            ('Bhaktapur Red Cross Blood Depot', 'Dudhpati, Bhaktapur', 'Bhaktapur', '+97716611666', 85.420, 27.671, True, False),
            ('Kanti Hospital Blood Bank', 'Maharajgunj, Kathmandu', 'Kathmandu', '+97714411555', 85.330, 27.736, True, True),
        ]

        blood_banks = []
        for name, addr, dist, phone, lon, lat, active, is_24h in blood_banks_data:
            bb, _ = BloodBank.objects.get_or_create(
                name=name,
                defaults={
                    'address': addr,
                    'district': dist,
                    'phone': phone,
                    'longitude': lon,
                    'latitude': lat,
                    'is_active': active,
                    'is_24h': is_24h,
                }
            )
            blood_banks.append(bb)

        self.stdout.write(f'Seeded {len(blood_banks)} blood banks.')

        # 7. Blood Stock Levels
        groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
        stock_levels = [
            BloodStock.StockLevel.ADEQUATE,
            BloodStock.StockLevel.LOW,
            BloodStock.StockLevel.CRITICAL,
            BloodStock.StockLevel.UNAVAILABLE,
        ]

        blood_stock_count = 0
        for bb in blood_banks:
            for bg in groups:
                lvl = random.choice(stock_levels)
                units = random.randint(1, 50) if lvl in [BloodStock.StockLevel.ADEQUATE, BloodStock.StockLevel.LOW] else 0
                
                BloodStock.objects.get_or_create(
                    blood_bank=bb,
                    blood_group=bg,
                    defaults={
                        'stock_level': lvl,
                        'units_available': units,
                        'notes': f'Updated by duty officer at Red Cross.'
                    }
                )
                blood_stock_count += 1

        self.stdout.write(f'Seeded {blood_stock_count} blood group stock entries.')

        # 8. Ambulance Providers
        ambulances_data = [
            ('Nepal Ambulance Service (Red Cross)', 'government', '102', 'Tripureshwor, Kathmandu', 'Kathmandu', 85.316, 27.696, True, True, True, True),
            ('Patan Hospital Emergency Dispatch', 'government', '+97715522295', 'Lagankhel, Lalitpur', 'Lalitpur', 85.323, 27.667, True, True, True, True),
            ('Bhaktapur Red Cross Dispatch', 'ngo', '+97716612266', 'Dudhpati, Bhaktapur', 'Bhaktapur', 85.422, 27.673, True, True, False, True),
            ('Trauma Center Emergency Care', 'government', '103', 'Mahankal, Kathmandu', 'Kathmandu', 85.314, 27.705, True, True, True, True),
            ('MediCare Private Ambulance', 'private', '+97714467000', 'Chabahil, Kathmandu', 'Kathmandu', 85.348, 27.718, True, True, False, True),
        ]

        for hospital_name, stype, phone, addr, dist, lon, lat, active, is_24h, has_icu, has_o2 in ambulances_data:
            AmbulanceProvider.objects.get_or_create(
                hospital_name=hospital_name,
                defaults={
                    'service_type': stype,
                    'contact_number': phone,
                    'address': addr,
                    'district': dist,
                    'longitude': lon,
                    'latitude': lat,
                    'is_active': active,
                    'is_24h': is_24h,
                    'has_icu': has_icu,
                    'has_oxygen': has_o2,
                    'notes': 'Call dispatch directly. 24/7 service operating in Kathmandu Valley.'
                }
            )

        self.stdout.write('Seeded 5 ambulance providers.')
        self.stdout.write('Database seeding complete! 🎉')

from django.contrib import admin
from .models import Pharmacy, Medicine, PharmacyMedicineStock

admin.site.register(Pharmacy)
admin.site.register(Medicine)
admin.site.register(PharmacyMedicineStock)
from django.contrib import admin
from .models import (
    Pharmacy,
    MedicineCategory,
    Medicine,
    PharmacyMedicineStock,
    BloodBank,
    BloodStock,
    AmbulanceProvider,
    MedicalProfile
)

class PharmacyMedicineStockInline(admin.TabularInline):
    model = PharmacyMedicineStock
    extra = 1
    autocomplete_fields = ['medicine']

@admin.register(Pharmacy)
class PharmacyAdmin(admin.ModelAdmin):
    list_display = ('name', 'district', 'phone', 'is_24h', 'verification_status', 'is_active', 'updated_at')
    list_filter = ('district', 'is_24h', 'verification_status', 'is_active')
    search_fields = ('name', 'address', 'phone', 'district')
    prepopulated_fields = {'slug': ('name',)}
    inlines = [PharmacyMedicineStockInline]
    ordering = ('name',)

@admin.register(MedicineCategory)
class MedicineCategoryAdmin(admin.ModelAdmin):
    list_display = ('name', 'icon')
    search_fields = ('name',)
    ordering = ('name',)

@admin.register(Medicine)
class MedicineAdmin(admin.ModelAdmin):
    list_display = ('name', 'generic_name', 'category', 'strength', 'dosage_form', 'is_essential', 'requires_prescription')
    list_filter = ('category', 'is_essential', 'requires_prescription', 'dosage_form')
    search_fields = ('name', 'generic_name', 'brand_name')
    ordering = ('name',)

@admin.register(PharmacyMedicineStock)
class PharmacyMedicineStockAdmin(admin.ModelAdmin):
    list_display = ('pharmacy', 'medicine', 'availability', 'price_npr', 'quantity_on_hand', 'updated_at')
    list_filter = ('availability', 'updated_at')
    search_fields = ('pharmacy__name', 'medicine__name', 'medicine__generic_name')
    autocomplete_fields = ('pharmacy', 'medicine')

class BloodStockInline(admin.TabularInline):
    model = BloodStock
    extra = 1

@admin.register(BloodBank)
class BloodBankAdmin(admin.ModelAdmin):
    list_display = ('name', 'district', 'phone', 'is_24h', 'is_active', 'updated_at')
    list_filter = ('district', 'is_24h', 'is_active')
    search_fields = ('name', 'address', 'phone', 'district')
    inlines = [BloodStockInline]
    ordering = ('name',)

@admin.register(BloodStock)
class BloodStockAdmin(admin.ModelAdmin):
    list_display = ('blood_bank', 'blood_group', 'stock_level', 'units_available', 'updated_at')
    list_filter = ('blood_group', 'stock_level')
    search_fields = ('blood_bank__name', 'blood_group')

@admin.register(AmbulanceProvider)
class AmbulanceProviderAdmin(admin.ModelAdmin):
    list_display = ('hospital_name', 'service_type', 'contact_number', 'district', 'is_24h', 'has_icu', 'has_oxygen', 'is_active')
    list_filter = ('service_type', 'district', 'is_24h', 'has_icu', 'has_oxygen', 'is_active')
    search_fields = ('hospital_name', 'contact_number', 'address', 'district')
    ordering = ('hospital_name',)

@admin.register(MedicalProfile)
class MedicalProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'blood_group', 'emergency_contact_name', 'emergency_contact_phone', 'updated_at')
    search_fields = ('user__username', 'user__first_name', 'user__last_name', 'emergency_contact_name')

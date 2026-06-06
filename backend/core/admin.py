from django.contrib import admin

from .models import BloodBank, EssentialMedicine, Pharmacy


@admin.register(Pharmacy)
class PharmacyAdmin(admin.ModelAdmin):
    list_display = ('name', 'address', 'phone', 'stock_status', 'updated_at')
    list_filter = ('stock_status', 'updated_at')
    search_fields = ('name', 'address', 'phone')
    ordering = ('name',)


@admin.register(BloodBank)
class BloodBankAdmin(admin.ModelAdmin):
    list_display = ('name', 'address', 'phone', 'updated_at')
    search_fields = ('name', 'address', 'phone')
    ordering = ('name',)


@admin.register(EssentialMedicine)
class EssentialMedicineAdmin(admin.ModelAdmin):
    list_display = ('name', 'generic_name', 'pharmacy', 'availability', 'updated_at')
    list_filter = ('availability', 'updated_at')
    search_fields = ('name', 'generic_name', 'manual_notes')
    autocomplete_fields = ('pharmacy',)
    ordering = ('name',)

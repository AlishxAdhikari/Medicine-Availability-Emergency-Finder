from django.contrib import admin

from .models import Medicine, Pharmacy, PharmacyMedicineStock, PharmacyOwner

admin.site.register(Medicine)
admin.site.register(PharmacyMedicineStock)


@admin.register(Pharmacy)
class PharmacyAdmin(admin.ModelAdmin):
    search_fields = ('name', 'district')


@admin.register(PharmacyOwner)
class PharmacyOwnerAdmin(admin.ModelAdmin):
    """Linking a user to a pharmacy here is how an owner account is created --
    the owner registers through the normal app signup first, then staff make
    the link."""
    list_display = ('user', 'pharmacy', 'created_at')
    search_fields = ('user__username', 'user__email', 'pharmacy__name')
    autocomplete_fields = ('user', 'pharmacy')

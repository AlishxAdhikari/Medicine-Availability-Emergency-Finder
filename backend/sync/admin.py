from django.contrib import admin
from .models import POSIntegrationKey, StockTransaction


@admin.register(POSIntegrationKey)
class POSIntegrationKeyAdmin(admin.ModelAdmin):
    list_display = ('pharmacy', 'key', 'is_active', 'created_at')
    list_filter = ('is_active',)
    search_fields = ('pharmacy__name', 'key')


@admin.register(StockTransaction)
class StockTransactionAdmin(admin.ModelAdmin):
    list_display = ('pharmacy', 'medicine', 'transaction_type', 'quantity_delta', 'server_timestamp')
    list_filter = ('transaction_type', 'source', 'pharmacy')
    search_fields = ('pharmacy__name', 'medicine__name')
    readonly_fields = ('server_timestamp',)
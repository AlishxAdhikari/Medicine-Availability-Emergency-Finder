from django.db import models
import secrets

from pharmacy.models import Pharmacy, Medicine


class POSIntegrationKey(models.Model):
    """Stores API keys for pharmacies' POS systems to authenticate sync requests."""
    pharmacy = models.OneToOneField(
        'pharmacy.Pharmacy',
        on_delete=models.CASCADE,
        related_name='pos_integration'
    )
    key = models.CharField(max_length=64, unique=True, default=secrets.token_hex(32))
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"POS Key for {self.pharmacy.name}"


class StockTransaction(models.Model):
    """Immutable audit log of every stock change from POS or manual adjustments."""
    TRANSACTION_TYPES = [
        ('DISPENSED', 'Dispensed'),
        ('RESTOCKED', 'Restocked'),
        ('ADJUSTED', 'Adjusted'),
    ]
    SOURCE_TYPES = [
        ('POS_SYNC', 'POS Sync'),
        ('MANUAL', 'Manual'),
    ]

    pharmacy = models.ForeignKey(
        'pharmacy.Pharmacy',
        on_delete=models.CASCADE,
        related_name='stock_transactions'
    )
    medicine = models.ForeignKey(
        'pharmacy.Medicine',
        on_delete=models.CASCADE,
        related_name='stock_transactions'
    )
    quantity_delta = models.IntegerField()  # positive for restock, negative for dispense
    transaction_type = models.CharField(
        max_length=20,
        choices=TRANSACTION_TYPES
    )
    source = models.CharField(
        max_length=20,
        choices=SOURCE_TYPES
    )
    client_timestamp = models.DateTimeField()
    server_timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-server_timestamp']

    def __str__(self):
        return f"{self.transaction_type} {self.quantity_delta} of {self.medicine.name} at {self.pharmacy.name}"
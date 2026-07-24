from rest_framework import serializers

from pharmacy.models import Medicine
from .models import StockTransaction


class StockSyncSerializer(serializers.Serializer):
    """Payload for POS stock updates."""
    medicine_barcode_or_name = serializers.CharField(required=True)
    quantity_delta = serializers.IntegerField(required=True)
    transaction_type = serializers.ChoiceField(
        choices=StockTransaction.TRANSACTION_TYPES, 
        required=True
    )
    timestamp = serializers.DateTimeField(required=True)

    def validate_medicine_barcode_or_name(self, value):
        return value


def get_medicine_by_barcode_or_name(identifier: str):
    """Helper to find medicine (extend with barcode field later)."""
    try:
        return Medicine.objects.get(name__iexact=identifier)
    except Medicine.DoesNotExist:
        raise serializers.ValidationError(f"Medicine not found: {identifier}")
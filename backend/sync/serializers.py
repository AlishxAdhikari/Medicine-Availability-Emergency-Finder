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


class OwnerTransactionSerializer(serializers.ModelSerializer):
    """One row of the owner's stock ledger, for the read-only activity feed.

    medicine_name and changed_by_username are flattened onto the row because
    the feed renders a flat list; the viewset select_related()s both, so this
    costs no extra queries.

    changed_by is null for POS_SYNC rows, which authenticate with a
    pharmacy-wide integration key and have no user behind them (see
    StockTransaction.changed_by). The client shows the source instead in that
    case, so the field stays nullable rather than being faked.
    """
    medicine_name = serializers.CharField(source='medicine.name', read_only=True)
    changed_by_username = serializers.CharField(
        source='changed_by.username', read_only=True, default=None,
    )

    class Meta:
        model = StockTransaction
        fields = (
            'id', 'medicine', 'medicine_name', 'quantity_delta',
            'transaction_type', 'source', 'changed_by_username',
            'client_timestamp', 'server_timestamp',
        )
        read_only_fields = fields


def get_medicine_by_barcode_or_name(identifier: str):
    """Helper to find medicine (extend with barcode field later)."""
    try:
        return Medicine.objects.get(name__iexact=identifier)
    except Medicine.DoesNotExist:
        raise serializers.ValidationError(f"Medicine not found: {identifier}")
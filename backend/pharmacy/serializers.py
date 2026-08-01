from rest_framework import serializers

from .models import Medicine, Pharmacy, PharmacyMedicineStock


class MedicineSerializer(serializers.ModelSerializer):
    class Meta:
        model = Medicine
        fields = (
            'id', 'name', 'generic_name', 'brand', 'category',
            'dosage_form', 'strength', 'is_essential', 'requires_prescription',
        )


class PharmacySerializer(serializers.ModelSerializer):
    # Only present when the request included lat/lng — see
    # PharmacyViewSet.list(). SerializerMethodField reads the attribute
    # that sort_by_proximity() attached to each object in services.py.
    distance_km = serializers.SerializerMethodField()

    class Meta:
        model = Pharmacy
        fields = (
            'id', 'name', 'address', 'district', 'latitude', 'longitude',
            'is_24_hour', 'is_verified', 'phone', 'distance_km',
        )

    def get_distance_km(self, obj):
        return getattr(obj, 'distance_km', None)


class PharmacyMedicineStockSerializer(serializers.ModelSerializer):
    """Nested view of a stock row: medicine details inline rather than just
    an id, since the pharmacy-detail screen wants name/price/quantity
    together in one call instead of N follow-up requests."""
    medicine = MedicineSerializer(read_only=True)

    class Meta:
        model = PharmacyMedicineStock
        fields = ('id', 'medicine', 'quantity', 'price', 'low_threshold')


class OwnerStockSerializer(serializers.ModelSerializer):
    """The owner's editable view of a stock row.

    Output-only. The view validates and applies writes itself, because a
    quantity change is not a field assignment -- it has to go through
    apply_stock_change() inside a row lock to produce the audit trail and
    trigger the low-stock alert. Letting a ModelSerializer write `quantity`
    directly would bypass both. price and low_threshold ARE plain field
    assignments and the owner can set both, but they are parsed and applied in
    owner_views.py alongside quantity so that one request is one code path,
    ordered so the alert sees the new threshold.

    `medicine` is nested rather than an id so the dashboard can render a name
    without a second request. On create, the view reads the medicine id
    straight off request.data.
    """
    medicine = MedicineSerializer(read_only=True)

    class Meta:
        model = PharmacyMedicineStock
        fields = ('id', 'medicine', 'quantity', 'price', 'low_threshold')
        read_only_fields = fields

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

from rest_framework import serializers

from .models import AmbulanceProvider, BloodBank, BloodStock


class BloodStockSerializer(serializers.ModelSerializer):
    class Meta:
        model = BloodStock
        fields = ('id', 'blood_group', 'level')


class BloodBankSerializer(serializers.ModelSerializer):
    # Nested, same pattern as PharmacyMedicineStockSerializer nesting
    # Medicine in pharmacy/serializers.py -- one call gets the bank and
    # everything it has in stock, instead of a follow-up request per group.
    stock = BloodStockSerializer(many=True, read_only=True)

    # Only present when the request included lat/lng -- see
    # BloodBankViewSet.list(). Mirrors PharmacySerializer.distance_km.
    distance_km = serializers.SerializerMethodField()

    class Meta:
        model = BloodBank
        fields = (
            'id', 'name', 'district', 'latitude', 'longitude',
            'operating_hours', 'phone', 'stock', 'distance_km',
        )

    def get_distance_km(self, obj):
        return getattr(obj, 'distance_km', None)


class AmbulanceProviderSerializer(serializers.ModelSerializer):
    distance_km = serializers.SerializerMethodField()

    class Meta:
        model = AmbulanceProvider
        fields = (
            'id', 'name', 'service_type', 'district', 'is_24_hour',
            'has_icu', 'has_oxygen', 'phone', 'distance_km',
        )

    def get_distance_km(self, obj):
        return getattr(obj, 'distance_km', None)
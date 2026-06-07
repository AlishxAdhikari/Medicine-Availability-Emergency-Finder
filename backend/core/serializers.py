import math
from rest_framework import serializers
from django.contrib.auth.models import User
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

# ── Distance Helper ──────────────────────────────────────────────────────────

def calculate_distance(lat1, lon1, lat2, lon2):
    if lat1 is None or lon1 is None or lat2 is None or lon2 is None:
        return None
    try:
        R = 6371.0 # Earth radius in km
        dlat = math.radians(float(lat2) - float(lat1))
        dlon = math.radians(float(lon2) - float(lon1))
        a = (math.sin(dlat / 2)**2 +
             math.cos(math.radians(float(lat1))) * math.cos(math.radians(float(lat2))) * math.sin(dlon / 2)**2)
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return round(R * c, 2)
    except (ValueError, TypeError):
        return None


# ── User & Auth Serializers ───────────────────────────────────────────────────

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'first_name', 'last_name')


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True, style={'input_type': 'password'})
    password_confirm = serializers.CharField(write_only=True, required=True, style={'input_type': 'password'})

    class Meta:
        model = User
        fields = ('username', 'email', 'password', 'password_confirm', 'first_name', 'last_name')

    def validate(self, attrs):
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({"password": "Password fields must match."})
        return attrs

    def create(self, validated_data):
        validated_data.pop('password_confirm')
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data.get('email', ''),
            password=validated_data['password'],
            first_name=validated_data.get('first_name', ''),
            last_name=validated_data.get('last_name', '')
        )
        return user


UserRegistrationSerializer = RegisterSerializer


# ── Medical Profile Serializer ───────────────────────────────────────────────

class MedicalProfileSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = MedicalProfile
        fields = (
            'id', 'user', 'blood_group', 'height_cm', 'weight_kg',
            'allergies', 'chronic_conditions', 'current_medications',
            'emergency_contact_name', 'emergency_contact_phone',
            'emergency_contact_relation', 'share_token', 'created_at', 'updated_at'
        )
        read_only_fields = ('share_token', 'created_at', 'updated_at')


# ── Medicine Serializers ─────────────────────────────────────────────────────

class MedicineCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = MedicineCategory
        fields = '__all__'


class MedicineSerializer(serializers.ModelSerializer):
    category_detail = MedicineCategorySerializer(source='category', read_only=True)

    class Meta:
        model = Medicine
        fields = (
            'id', 'name', 'generic_name', 'brand_name', 'category', 'category_detail',
            'dosage_form', 'strength', 'description', 'is_essential', 'requires_prescription'
        )


# ── Pharmacy Medicine Stock Serializers ───────────────────────────────────────

class PharmacyMedicineStockSerializer(serializers.ModelSerializer):
    pharmacy_detail = serializers.SerializerMethodField()
    medicine_detail = MedicineSerializer(source='medicine', read_only=True)

    class Meta:
        model = PharmacyMedicineStock
        fields = (
            'id', 'pharmacy', 'pharmacy_detail', 'medicine', 'medicine_detail', 'availability',
            'price_npr', 'quantity_on_hand', 'notes', 'updated_at'
        )

    def get_pharmacy_detail(self, obj):
        return {
            'id': obj.pharmacy_id,
            'name': obj.pharmacy.name,
            'address': obj.pharmacy.address,
            'district': obj.pharmacy.district,
            'phone': obj.pharmacy.phone,
            'latitude': obj.pharmacy.latitude,
            'longitude': obj.pharmacy.longitude,
        }


# ── Pharmacy Serializers ─────────────────────────────────────────────────────

class PharmacySerializer(serializers.ModelSerializer):
    distance = serializers.SerializerMethodField()
    stock = PharmacyMedicineStockSerializer(many=True, read_only=True)

    class Meta:
        model = Pharmacy
        fields = (
            'id', 'name', 'slug', 'address', 'district', 'phone', 'phone_alt',
            'email', 'latitude', 'longitude', 'distance', 'is_24h', 'opens_at', 'closes_at',
            'is_active', 'verification_status', 'stock', 'created_at', 'updated_at'
        )

    def get_distance(self, obj):
        request = self.context.get('request')
        if not request:
            return None
        lat = request.query_params.get('lat')
        lon = request.query_params.get('lon')
        return calculate_distance(lat, lon, obj.latitude, obj.longitude)


# ── Blood Bank Serializers ───────────────────────────────────────────────────

class BloodStockSerializer(serializers.ModelSerializer):
    class Meta:
        model = BloodStock
        fields = ('id', 'blood_group', 'stock_level', 'units_available', 'notes', 'updated_at')


class BloodBankSerializer(serializers.ModelSerializer):
    distance = serializers.SerializerMethodField()
    blood_stocks = BloodStockSerializer(many=True, read_only=True)

    class Meta:
        model = BloodBank
        fields = (
            'id', 'name', 'address', 'district', 'phone', 'phone_alt',
            'latitude', 'longitude', 'distance', 'is_active', 'is_24h', 'blood_stocks', 'created_at', 'updated_at'
        )

    def get_distance(self, obj):
        request = self.context.get('request')
        if not request:
            return None
        lat = request.query_params.get('lat')
        lon = request.query_params.get('lon')
        return calculate_distance(lat, lon, obj.latitude, obj.longitude)


# ── Ambulance Provider Serializer ────────────────────────────────────────────

class AmbulanceProviderSerializer(serializers.ModelSerializer):
    distance = serializers.SerializerMethodField()

    class Meta:
        model = AmbulanceProvider
        fields = (
            'id', 'hospital_name', 'service_type', 'contact_number', 'contact_alt',
            'address', 'district', 'latitude', 'longitude', 'distance', 'is_active', 'is_24h',
            'has_icu', 'has_oxygen', 'notes', 'created_at', 'updated_at'
        )

    def get_distance(self, obj):
        request = self.context.get('request')
        if not request:
            return None
        lat = request.query_params.get('lat')
        lon = request.query_params.get('lon')
        return calculate_distance(lat, lon, obj.latitude, obj.longitude)

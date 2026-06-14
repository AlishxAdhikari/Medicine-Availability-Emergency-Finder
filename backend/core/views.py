import uuid
from rest_framework import viewsets, permissions, status, generics
from rest_framework.response import Response
from rest_framework.decorators import action
from django.contrib.auth.models import User
from django.db.models import Prefetch

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
from .serializers import (
    UserSerializer,
    RegisterSerializer,
    MedicalProfileSerializer,
    MedicineCategorySerializer,
    MedicineSerializer,
    PharmacyMedicineStockSerializer,
    PharmacySerializer,
    BloodStockSerializer,
    BloodBankSerializer,
    AmbulanceProviderSerializer,
    calculate_distance
)
from .filters import (
    PharmacyFilter,
    MedicineFilter,
    BloodBankFilter,
    AmbulanceProviderFilter
)


# ── Auth Views ───────────────────────────────────────────────────────────────

class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]


# ── Medical Profile Views ──────────────────────────────────────────────────────

class MedicalProfileViewSet(viewsets.ModelViewSet):
    serializer_class = MedicalProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return MedicalProfile.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        share_token = uuid.uuid4().hex
        serializer.save(user=self.request.user, share_token=share_token)

    @action(detail=False, methods=['get', 'put', 'patch'])
    def me(self, request):
        profile, created = MedicalProfile.objects.get_or_create(
            user=request.user,
            defaults={'share_token': uuid.uuid4().hex}
        )
        if not profile.share_token:
            profile.share_token = uuid.uuid4().hex
            profile.save()

        if request.method in ['PUT', 'PATCH']:
            partial = request.method == 'PATCH'
            serializer = self.get_serializer(profile, data=request.data, partial=partial)
            serializer.is_valid(raise_exception=True)
            serializer.save()
            return Response(serializer.data)
        
        serializer = self.get_serializer(profile)
        return Response(serializer.data)

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny])
    def public(self, request):
        """Public read-only endpoint for emergency responders to access medical ID via share_token"""
        share_token = request.query_params.get('token')
        if not share_token:
            return Response(
                {'error': 'share_token query parameter is required'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            profile = MedicalProfile.objects.get(share_token=share_token)
            serializer = self.get_serializer(profile)
            return Response(serializer.data)
        except MedicalProfile.DoesNotExist:
            return Response(
                {'error': 'Invalid share_token'},
                status=status.HTTP_404_NOT_FOUND
            )


# ── Shared Helper Mixin for Python Distance Sorting ───────────────────────────

class DistanceSortingMixin:
    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        
        lat = request.query_params.get('lat')
        lon = request.query_params.get('lon')
        radius = request.query_params.get('radius')
        
        if lat and lon:
            try:
                lat_val = float(lat)
                lon_val = float(lon)
                items = list(queryset)
                
                # Compute distance for each object
                for item in items:
                    item.distance = calculate_distance(lat_val, lon_val, item.latitude, item.longitude)
                
                # Optional radius filter in km
                if radius:
                    radius_val = float(radius)
                    items = [item for item in items if item.distance is not None and item.distance <= radius_val]
                
                # Sort items by distance (ascending)
                items.sort(key=lambda x: x.distance if x.distance is not None else float('inf'))
                
                page = self.paginate_queryset(items)
                if page is not None:
                    serializer = self.get_serializer(page, many=True)
                    return self.get_paginated_response(serializer.data)
                
                serializer = self.get_serializer(items, many=True)
                return Response(serializer.data)
            except (ValueError, TypeError):
                pass
                
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
            
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)


# ── Pharmacy ViewSet ──────────────────────────────────────────────────────────

class PharmacyViewSet(DistanceSortingMixin, viewsets.ModelViewSet):
    queryset = Pharmacy.objects.filter(is_active=True).prefetch_related(
        Prefetch('stock', queryset=PharmacyMedicineStock.objects.select_related('medicine'))
    )
    serializer_class = PharmacySerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_class = PharmacyFilter
    search_fields = ['name', 'address', 'district']


# ── Medicine Category & Catalogue ViewSets ───────────────────────────────────

class MedicineCategoryViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = MedicineCategory.objects.all()
    serializer_class = MedicineCategorySerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]


class MedicineViewSet(viewsets.ModelViewSet):
    queryset = Medicine.objects.all().select_related('category')
    serializer_class = MedicineSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_class = MedicineFilter
    search_fields = ['name', 'generic_name', 'brand_name']


class PharmacyMedicineStockViewSet(viewsets.ModelViewSet):
    queryset = PharmacyMedicineStock.objects.all().select_related('pharmacy', 'medicine', 'pharmacy__managed_by')
    serializer_class = PharmacyMedicineStockSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_fields = ['pharmacy', 'medicine', 'availability']


# ── Blood Bank ViewSet ────────────────────────────────────────────────────────

class BloodBankViewSet(DistanceSortingMixin, viewsets.ModelViewSet):
    queryset = BloodBank.objects.filter(is_active=True).prefetch_related('blood_stocks')
    serializer_class = BloodBankSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_class = BloodBankFilter
    search_fields = ['name', 'address', 'district']


# ── Ambulance Provider ViewSet ───────────────────────────────────────────────

class AmbulanceProviderViewSet(DistanceSortingMixin, viewsets.ModelViewSet):
    queryset = AmbulanceProvider.objects.filter(is_active=True)
    serializer_class = AmbulanceProviderSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_class = AmbulanceProviderFilter
    search_fields = ['hospital_name', 'address', 'district']

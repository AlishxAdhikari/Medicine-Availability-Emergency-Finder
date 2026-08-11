from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .filters import MedicineFilter, PharmacyFilter
from .mixins import ProximityListMixin
from .models import Medicine, Pharmacy
from .serializers import (
    MedicineSerializer,
    PharmacyMedicineStockSerializer,
    PharmacySerializer,
)


class MedicineViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/medicines/?search=&category=&dosage_form=&is_essential=&requires_prescription="""
    queryset = Medicine.objects.all().order_by('name')
    serializer_class = MedicineSerializer
    filterset_class = MedicineFilter
    permission_classes = [permissions.AllowAny]


class PharmacyViewSet(ProximityListMixin, viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/pharmacies/?search=&district=&is_24_hour=&is_verified=&lat=&lng=&radius_km="""
    queryset = Pharmacy.objects.all().order_by('name')
    serializer_class = PharmacySerializer
    filterset_class = PharmacyFilter
    permission_classes = [permissions.AllowAny]

    @action(detail=True, methods=['get'])
    def stock(self, request, pk=None):
        """GET /api/v1/pharmacies/<id>/stock/ -- full stock list for one pharmacy."""
        pharmacy = self.get_object()
        stock = pharmacy.stock_entries.select_related('medicine').order_by('medicine__name')
        serializer = PharmacyMedicineStockSerializer(stock, many=True)
        return Response(serializer.data)

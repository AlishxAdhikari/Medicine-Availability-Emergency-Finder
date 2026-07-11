from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .filters import MedicineFilter, PharmacyFilter
from .models import Medicine, Pharmacy
from .serializers import (
    MedicineSerializer,
    PharmacyMedicineStockSerializer,
    PharmacySerializer,
)
from .services import sort_by_proximity


class MedicineViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/medicines/?search=&category=&dosage_form=&is_essential=&requires_prescription="""
    queryset = Medicine.objects.all().order_by('name')
    serializer_class = MedicineSerializer
    filterset_class = MedicineFilter
    permission_classes = [permissions.AllowAny]


class PharmacyViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/pharmacies/?search=&district=&is_24_hour=&is_verified=&lat=&lng=&radius_km="""
    queryset = Pharmacy.objects.all().order_by('name')
    serializer_class = PharmacySerializer
    filterset_class = PharmacyFilter
    permission_classes = [permissions.AllowAny]

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())

        lat = request.query_params.get('lat')
        lng = request.query_params.get('lng')
        if lat is not None and lng is not None:
            try:
                lat, lng = float(lat), float(lng)
            except ValueError:
                return Response({'detail': 'lat and lng must be numbers.'}, status=400)

            radius_km = request.query_params.get('radius_km')
            if radius_km is not None:
                try:
                    radius_km = float(radius_km)
                except ValueError:
                    return Response({'detail': 'radius_km must be a number.'}, status=400)

            queryset = sort_by_proximity(queryset, lat, lng, radius_km)

        page = self.paginate_queryset(queryset)
        serializer = self.get_serializer(page if page is not None else queryset, many=True)
        if page is not None:
            return self.get_paginated_response(serializer.data)
        return Response(serializer.data)

    @action(detail=True, methods=['get'])
    def stock(self, request, pk=None):
        """GET /api/v1/pharmacies/<id>/stock/ -- full stock list for one pharmacy."""
        pharmacy = self.get_object()
        stock = pharmacy.stock_entries.select_related('medicine').order_by('medicine__name')
        serializer = PharmacyMedicineStockSerializer(stock, many=True)
        return Response(serializer.data)

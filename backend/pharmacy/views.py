from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .filters import MedicineFilter, PharmacyFilter
from .mixins import ProximityListMixin
from .models import Medicine, Pharmacy, PharmacyMedicineStock
from .serializers import (
    MedicineAvailabilitySerializer,
    MedicineSerializer,
    PharmacyMedicineStockSerializer,
    PharmacySerializer,
)
from .services import haversine_km


class MedicineViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/medicines/?search=&category=&dosage_form=&is_essential=&requires_prescription="""
    queryset = Medicine.objects.all().order_by('name')
    serializer_class = MedicineSerializer
    filterset_class = MedicineFilter
    permission_classes = [permissions.AllowAny]

    @action(detail=True, methods=['get'])
    def availability(self, request, pk=None):
        """GET /api/v1/medicines/<id>/availability/?lat=&lng=&radius_km=

        Every pharmacy that stocks this medicine, in one query. Replaces the
        N+1 pattern a client would otherwise need -- list pharmacies, then
        call .../stock/ once per pharmacy just to check whether it carries
        this one medicine -- with a single query filtered the other way
        round: start from the medicine, join out to its stock rows.

        select_related('pharmacy') means the pharmacy fields the serializer
        reads (name, address, distance_km's lat/lng, ...) come back in the
        same query as the stock rows, not one extra query per row.

        lat/lng/radius_km behave like PharmacyViewSet's proximity params
        (see ProximityListMixin), but aren't reused from there directly:
        that mixin sorts Pharmacy objects, this sorts PharmacyMedicineStock
        rows by their related pharmacy's distance, which is a different
        enough shape that forcing a shared mixin would obscure both.
        """
        medicine = self.get_object()
        stock_qs = (
            PharmacyMedicineStock.objects
            .filter(medicine=medicine)
            .select_related('pharmacy')
            .order_by('pharmacy__name')
        )

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

            results = []
            for stock in stock_qs:
                distance = haversine_km(lat, lng, stock.pharmacy.latitude, stock.pharmacy.longitude)
                if radius_km is not None and distance > radius_km:
                    continue
                # Same trick PharmacySerializer relies on elsewhere: attach
                # the computed distance to the object so the serializer's
                # SerializerMethodField can read it back with getattr().
                stock.pharmacy.distance_km = round(distance, 2)
                results.append(stock)
            results.sort(key=lambda s: s.pharmacy.distance_km)
            stock_qs = results

        serializer = MedicineAvailabilitySerializer(stock_qs, many=True)
        return Response(serializer.data)


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
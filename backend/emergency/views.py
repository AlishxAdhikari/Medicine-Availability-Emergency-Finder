from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from pharmacy.mixins import ProximityListMixin

from .filters import AmbulanceFilter, BloodBankFilter
from .models import AmbulanceProvider, BloodBank
from .serializers import AmbulanceProviderSerializer, BloodBankSerializer


class DistrictsActionMixin:
    """Adds GET <endpoint>/districts/ returning the districts that actually
    have rows, so the app's district filter can be driven by the data instead
    of a hardcoded client-side list that silently hides seeded districts."""

    @action(detail=False, methods=['get'], pagination_class=None)
    def districts(self, request):
        # .order_by() clears the viewset's order_by('name'): without that,
        # 'name' stays in the SELECT and DISTINCT then de-duplicates
        # (district, name) pairs rather than districts.
        names = self.get_queryset().order_by().values_list('district', flat=True).distinct()
        return Response(sorted(names))


class BloodBankViewSet(DistrictsActionMixin, ProximityListMixin, viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/blood-banks/?district=&blood_group=&lat=&lng=&radius_km="""
    queryset = BloodBank.objects.all().prefetch_related('stock').order_by('name')
    serializer_class = BloodBankSerializer
    filterset_class = BloodBankFilter
    permission_classes = [permissions.AllowAny]


class AmbulanceViewSet(DistrictsActionMixin, viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/ambulances/?district=&has_icu=&has_oxygen=&is_24_hour=&service_type="""
    queryset = AmbulanceProvider.objects.all().order_by('name')
    serializer_class = AmbulanceProviderSerializer
    filterset_class = AmbulanceFilter
    permission_classes = [permissions.AllowAny]
from rest_framework import permissions, viewsets
from rest_framework.response import Response

from pharmacy.services import sort_by_proximity

from .filters import AmbulanceFilter, BloodBankFilter
from .models import AmbulanceProvider, BloodBank
from .serializers import AmbulanceProviderSerializer, BloodBankSerializer


class BloodBankViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/blood-banks/?district=&blood_group=&lat=&lng=&radius_km="""
    queryset = BloodBank.objects.all().prefetch_related('stock').order_by('name')
    serializer_class = BloodBankSerializer
    filterset_class = BloodBankFilter
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


class AmbulanceViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/ambulances/?district=&has_icu=&has_oxygen=&is_24_hour=&service_type="""
    queryset = AmbulanceProvider.objects.all().order_by('name')
    serializer_class = AmbulanceProviderSerializer
    filterset_class = AmbulanceFilter
    permission_classes = [permissions.AllowAny]
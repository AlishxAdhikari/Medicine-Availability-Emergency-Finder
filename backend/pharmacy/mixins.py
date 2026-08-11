from rest_framework.response import Response

from .services import sort_by_proximity


class ProximityListMixin:
    """Adds optional `?lat=&lng=&radius_km=` distance sorting to a list view.

    PharmacyViewSet and BloodBankViewSet had byte-identical copies of this
    list() method. Both answer the same question -- "what is near me?" -- so
    the parsing, the two 400s and the pagination handling now live in one
    place; a fix to the validation no longer has to be remembered twice.

    Applies only when both lat and lng are given. Without them the view falls
    through to its normal ordering, so callers that just want "all pharmacies
    in this district" are unaffected.

    Note that sort_by_proximity returns a list, not a queryset (the distance
    is computed in Python, since there is no PostGIS here), which is why
    pagination is applied after it rather than by the default ListModelMixin.
    """

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

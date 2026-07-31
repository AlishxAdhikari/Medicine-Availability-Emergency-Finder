from django.contrib.auth.models import AnonymousUser
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from pharmacy.services import apply_stock_change
from .authentication import POSKeyAuthentication
from .serializers import StockSyncSerializer, get_medicine_by_barcode_or_name


class StockSyncView(APIView):
    """POST /api/v1/stock/sync/"""
    authentication_classes = [POSKeyAuthentication]
    permission_classes = []

    def post(self, request):
        # Bug fix: the old check `not request.user or not hasattr(request.user, 'pk')`
        # never actually caught a missing/invalid key. When POSKeyAuthentication
        # doesn't find a key, it returns None and DRF falls back to
        # AnonymousUser -- which is truthy and DOES have a `.pk` attribute
        # (it's just None), so the old check let it through. The request then
        # crashed further down trying to use AnonymousUser as if it were a
        # Pharmacy foreign key. Checking for AnonymousUser directly (and for
        # None, just in case) is what actually rejects an unauthenticated
        # request here.
        if request.user is None or isinstance(request.user, AnonymousUser):
            return Response({'detail': 'Authentication credentials were not provided.'},
                          status=status.HTTP_401_UNAUTHORIZED)

        serializer = StockSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        pharmacy = request.user
        medicine = get_medicine_by_barcode_or_name(
            serializer.validated_data['medicine_barcode_or_name']
        )

        delta = serializer.validated_data['quantity_delta']

        stock, txn, clamped = apply_stock_change(
            pharmacy,
            medicine,
            delta=delta,
            source='POS_SYNC',
            transaction_type=serializer.validated_data['transaction_type'],
        )

        return Response({
            'status': 'accepted',
            'new_quantity': stock.quantity,
            'transaction_id': txn.id,
            'note': 'Quantity was clamped to 0' if clamped else None,
        }, status=status.HTTP_200_OK)
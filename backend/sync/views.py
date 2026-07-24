from django.db import transaction
from django.db.models import F
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from pharmacy.models import PharmacyMedicineStock
from .authentication import POSKeyAuthentication
from .models import StockTransaction
from .serializers import StockSyncSerializer, get_medicine_by_barcode_or_name


class StockSyncView(APIView):
    """POST /api/v1/stock/sync/"""
    authentication_classes = [POSKeyAuthentication]
    permission_classes = []

    def post(self, request):
        if not request.user or not hasattr(request.user, 'pk'):
            return Response({'detail': 'Authentication credentials were not provided.'}, 
                          status=status.HTTP_401_UNAUTHORIZED)

        serializer = StockSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        pharmacy = request.user
        medicine = get_medicine_by_barcode_or_name(
            serializer.validated_data['medicine_barcode_or_name']
        )

        delta = serializer.validated_data['quantity_delta']

        with transaction.atomic():
            stock, _ = PharmacyMedicineStock.objects.select_for_update().get_or_create(
                pharmacy=pharmacy,
                medicine=medicine,
                defaults={'price': 0.0}
            )

            # Prevent negative quantity
            new_quantity = max(0, stock.quantity + delta)
            stock.quantity = new_quantity
            stock.save()

            # Log the transaction (even if clamped)
            txn = StockTransaction.objects.create(
                pharmacy=pharmacy,
                medicine=medicine,
                quantity_delta=delta,
                transaction_type=serializer.validated_data['transaction_type'],
                source='POS_SYNC',
                client_timestamp=serializer.validated_data['timestamp'],
            )

        return Response({
            'status': 'accepted',
            'new_quantity': stock.quantity,
            'transaction_id': txn.id,
            'note': 'Quantity was clamped to 0' if new_quantity == 0 and delta < 0 else None
        }, status=status.HTTP_200_OK)
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.response import Response

from .models import Medicine, PharmacyMedicineStock
from .permissions import IsPharmacyOwner
from .serializers import OwnerStockSerializer
from .services import apply_stock_change


class OwnerStockViewSet(viewsets.ViewSet):
    """/api/v1/my-pharmacy/stock/ -- the owner's own stock, and the only
    human-facing write path to PharmacyMedicineStock.

    There is no pharmacy id anywhere in these URLs on purpose. The pharmacy
    is resolved from the caller's token (same approach as core's
    MedicalProfileView), so there is no id for a caller to swap for someone
    else's. Every lookup is additionally scoped to that pharmacy, which is
    what turns a foreign row into a 404 rather than a 403 -- a 403 would
    confirm the row exists.
    """
    permission_classes = [IsPharmacyOwner]

    @property
    def pharmacy(self):
        return self.request.user.pharmacy_owner.pharmacy

    def get_queryset(self):
        return PharmacyMedicineStock.objects.filter(
            pharmacy=self.pharmacy
        ).select_related('medicine').order_by('medicine__name')

    def list(self, request):
        serializer = OwnerStockSerializer(self.get_queryset(), many=True)
        return Response(serializer.data)

    def create(self, request):
        medicine = get_object_or_404(Medicine, pk=request.data.get('medicine'))

        if PharmacyMedicineStock.objects.filter(
            pharmacy=self.pharmacy, medicine=medicine
        ).exists():
            return Response(
                {'medicine': ['This pharmacy already stocks that medicine. Edit it instead.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            quantity = int(request.data.get('quantity'))
        except (TypeError, ValueError):
            return Response({'quantity': ['A whole number is required.']},
                            status=status.HTTP_400_BAD_REQUEST)
        if quantity < 0:
            return Response({'quantity': ['Quantity cannot be negative.']},
                            status=status.HTTP_400_BAD_REQUEST)

        stock, _, _ = apply_stock_change(
            self.pharmacy, medicine, absolute=quantity,
            source='MANUAL', transaction_type='ADJUSTED', user=request.user,
        )

        price = request.data.get('price')
        if price is not None:
            stock.price = price
            stock.save(update_fields=['price'])

        return Response(OwnerStockSerializer(stock).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        stock = get_object_or_404(self.get_queryset(), pk=pk)

        if 'quantity' in request.data:
            try:
                quantity = int(request.data['quantity'])
            except (TypeError, ValueError):
                return Response({'quantity': ['A whole number is required.']},
                                status=status.HTTP_400_BAD_REQUEST)
            if quantity < 0:
                return Response({'quantity': ['Quantity cannot be negative.']},
                                status=status.HTTP_400_BAD_REQUEST)
            stock, _, _ = apply_stock_change(
                self.pharmacy, stock.medicine, absolute=quantity,
                source='MANUAL', transaction_type='ADJUSTED', user=request.user,
            )

        if 'price' in request.data:
            stock.price = request.data['price']
            stock.save(update_fields=['price'])

        return Response(OwnerStockSerializer(stock).data)

    def destroy(self, request, pk=None):
        stock = get_object_or_404(self.get_queryset(), pk=pk)

        # Zero it through the ledger first, so removing a row that still had
        # stock on it doesn't vanish from the audit log. The transaction holds
        # its own FKs and survives the row's deletion.
        apply_stock_change(
            self.pharmacy, stock.medicine, absolute=0,
            source='MANUAL', transaction_type='ADJUSTED', user=request.user,
        )
        stock.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

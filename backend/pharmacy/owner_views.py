from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.response import Response

from .models import Medicine, PharmacyMedicineStock
from .permissions import IsPharmacyOwner
from .serializers import OwnerStockSerializer
from .services import apply_stock_change


def _parse_quantity(raw):
    """Returns (quantity, error_response). error_response is None on success."""
    try:
        quantity = int(raw)
    except (TypeError, ValueError):
        return None, Response({'quantity': ['A whole number is required.']},
                               status=status.HTTP_400_BAD_REQUEST)
    if quantity < 0:
        return None, Response({'quantity': ['Quantity cannot be negative.']},
                               status=status.HTTP_400_BAD_REQUEST)
    return quantity, None


def _parse_price(raw):
    """Returns (price, error_response). error_response is None on success.

    Mirrors _parse_quantity: malformed or negative input must be a 400, not
    a 500 from a ValidationError/IntegrityError inside save().
    """
    if raw is None:
        return None, Response({'price': ['Price cannot be null.']},
                               status=status.HTTP_400_BAD_REQUEST)
    try:
        price = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        return None, Response({'price': ['A valid decimal number is required.']},
                               status=status.HTTP_400_BAD_REQUEST)
    if price < 0:
        return None, Response({'price': ['Price cannot be negative.']},
                               status=status.HTTP_400_BAD_REQUEST)
    return price, None


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
        try:
            medicine_id = int(request.data.get('medicine'))
        except (TypeError, ValueError):
            return Response({'medicine': ['A valid medicine id is required.']},
                            status=status.HTTP_400_BAD_REQUEST)
        medicine = get_object_or_404(Medicine, pk=medicine_id)

        if PharmacyMedicineStock.objects.filter(
            pharmacy=self.pharmacy, medicine=medicine
        ).exists():
            return Response(
                {'medicine': ['This pharmacy already stocks that medicine. Edit it instead.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

        quantity, error = _parse_quantity(request.data.get('quantity'))
        if error is not None:
            return error

        price = None
        if 'price' in request.data:
            price, error = _parse_price(request.data.get('price'))
            if error is not None:
                return error

        with transaction.atomic():
            stock, _, _ = apply_stock_change(
                self.pharmacy, medicine, absolute=quantity,
                source='MANUAL', transaction_type='ADJUSTED', user=request.user,
            )

            if price is not None:
                stock.price = price
                stock.save(update_fields=['price'])

        return Response(OwnerStockSerializer(stock).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        stock = get_object_or_404(self.get_queryset(), pk=pk)

        quantity = None
        if 'quantity' in request.data:
            quantity, error = _parse_quantity(request.data['quantity'])
            if error is not None:
                return error

        price = None
        if 'price' in request.data:
            price, error = _parse_price(request.data['price'])
            if error is not None:
                return error

        with transaction.atomic():
            if quantity is not None:
                stock, _, _ = apply_stock_change(
                    self.pharmacy, stock.medicine, absolute=quantity,
                    source='MANUAL', transaction_type='ADJUSTED', user=request.user,
                )

            if price is not None:
                stock.price = price
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

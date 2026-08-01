from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.response import Response

from .models import Medicine, PharmacyMedicineStock
from .permissions import IsPharmacyOwner
from .serializers import OwnerStockSerializer
from .services import apply_stock_change


def _parse_non_negative_int(raw, field, label):
    """Returns (value, error_response). error_response is None on success."""
    try:
        value = int(raw)
    except (TypeError, ValueError):
        return None, Response({field: ['A whole number is required.']},
                               status=status.HTTP_400_BAD_REQUEST)
    if value < 0:
        return None, Response({field: [f'{label} cannot be negative.']},
                               status=status.HTTP_400_BAD_REQUEST)
    return value, None


def _parse_quantity(raw):
    return _parse_non_negative_int(raw, 'quantity', 'Quantity')


def _parse_low_threshold(raw):
    """The quantity at or below which sync/signals.py alerts. Owner-settable
    because it is the one number the whole alerting feature keys off, and a
    pharmacy that turns over 500 boxes a week is not served by the model's
    default of 10."""
    return _parse_non_negative_int(raw, 'low_threshold', 'Low-stock threshold')


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

        low_threshold = None
        if 'low_threshold' in request.data:
            low_threshold, error = _parse_low_threshold(request.data['low_threshold'])
            if error is not None:
                return error

        with transaction.atomic():
            # alert=False: the opening quantity is not news. low_threshold
            # defaults to 10, so without this every medicine added with a
            # single-digit opening count -- an ordinary thing to do -- pushed a
            # "low stock" alert to every client watching this pharmacy, about a
            # number the owner had just finished typing.
            stock, _, _ = apply_stock_change(
                self.pharmacy, medicine, absolute=quantity,
                source='MANUAL', transaction_type='ADJUSTED', user=request.user,
                alert=False,
            )

            update_fields = []
            if price is not None:
                stock.price = price
                update_fields.append('price')
            if low_threshold is not None:
                stock.low_threshold = low_threshold
                update_fields.append('low_threshold')
            if update_fields:
                stock.save(update_fields=update_fields)

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

        low_threshold = None
        if 'low_threshold' in request.data:
            low_threshold, error = _parse_low_threshold(request.data['low_threshold'])
            if error is not None:
                return error

        with transaction.atomic():
            # Threshold first, deliberately. sync/signals.py reads
            # low_threshold off the row when the transaction lands, so a PATCH
            # that raises the threshold and drops the quantity in one call has
            # to have written the new threshold before apply_stock_change runs
            # -- otherwise the alert is judged against the value the owner just
            # replaced. (A threshold change on its own writes no transaction
            # and so raises no alert, even if it puts an existing quantity into
            # the low band: alerts hang off movement, by design.)
            if low_threshold is not None:
                stock.low_threshold = low_threshold
                stock.save(update_fields=['low_threshold'])

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
        #
        # alert=False, because this zero is bookkeeping, not a shortage. Left
        # alerting, every removal pushed "critical, 0 left" for a medicine that
        # ceased to exist a millisecond later -- telling every watching client
        # to go and buy the one thing this pharmacy had just declared it no
        # longer carries.
        apply_stock_change(
            self.pharmacy, stock.medicine, absolute=0,
            source='MANUAL', transaction_type='ADJUSTED', user=request.user,
            alert=False,
        )
        stock.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

from decimal import Decimal, InvalidOperation

from django.db import IntegrityError, transaction
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.response import Response

from .models import Medicine, PharmacyMedicineStock
from .permissions import IsPharmacyOwner
from .serializers import OwnerStockSerializer
from .services import apply_stock_change


ALREADY_STOCKED = 'This pharmacy already stocks that medicine. Edit it instead.'


class _AlreadyStocked(Exception):
    """Raised from inside create()'s transaction, so returning the 400 also
    rolls back the row the attempt had already created."""


def _parse_non_negative_int(raw, field, label):
    """Returns (value, error_response). error_response is None on success."""
    if isinstance(raw, bool):
        # int(True) is 1, so a JSON `true` would otherwise sail through as a
        # quantity of one. bool is a subclass of int, hence the explicit check.
        return None, Response({field: ['A whole number is required.']},
                               status=status.HTTP_400_BAD_REQUEST)
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
        """Add a medicine to this pharmacy's stock.

        Accepts either:
          - medicine: <catalog id>  (existing behaviour), or
          - medicine_name: "<string>"  — find by exact name, or create a new
            catalog Medicine row so owners can stock strengths/products that
            were not in the seed list (e.g. Amoxicillin 250mg when only 500mg
            exists).
        Optional with medicine_name: generic_name, category, dosage_form, strength.
        """
        raw_medicine = request.data.get('medicine')
        medicine_name = (request.data.get('medicine_name') or '').strip()

        medicine = None
        if medicine_name and (raw_medicine is None or raw_medicine == ''):
            # Create-or-get by exact name so 250mg stays distinct from 500mg.
            defaults = {
                'generic_name': (request.data.get('generic_name') or '').strip(),
                'category': (request.data.get('category') or 'General').strip() or 'General',
                'dosage_form': (request.data.get('dosage_form') or 'Tablet').strip() or 'Tablet',
                'strength': (request.data.get('strength') or '').strip(),
                'brand': (request.data.get('brand') or '').strip(),
            }
            # Infer strength from name if not provided (e.g. "... 250mg")
            if not defaults['strength']:
                import re
                m = re.search(r'(\d+(?:[./]\d+)?\s*(?:mg|mcg|g|ml|iu|%))', medicine_name, re.I)
                if m:
                    defaults['strength'] = m.group(1).replace(' ', '')
            medicine, _ = Medicine.objects.get_or_create(
                name=medicine_name,
                defaults=defaults,
            )
        else:
            if isinstance(raw_medicine, bool):
                # int(True) == 1: a JSON `true` here used to resolve to whichever
                # medicine happens to hold pk 1.
                raw_medicine = None
            try:
                medicine_id = int(raw_medicine)
            except (TypeError, ValueError):
                return Response(
                    {'medicine': [
                        'Provide medicine (catalog id) or medicine_name (to create/find).'
                    ]},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            medicine = get_object_or_404(Medicine, pk=medicine_id)

        quantity, error = _parse_quantity(request.data.get('quantity'))
        if error is not None:
            return error

        # Required on create, unlike on PATCH. Defaulting it meant a caller
        # that omitted price published the medicine to every public search at
        # 0.00 -- and a stated price of nothing is worse than no listing.
        if 'price' not in request.data:
            return Response({'price': ['This field is required.']},
                            status=status.HTTP_400_BAD_REQUEST)
        price, error = _parse_price(request.data.get('price'))
        if error is not None:
            return error

        low_threshold = None
        if 'low_threshold' in request.data:
            low_threshold, error = _parse_low_threshold(request.data['low_threshold'])
            if error is not None:
                return error

        try:
            with transaction.atomic():
                # "Do we already stock this?" is answered by claiming the row,
                # not by asking first. A separate .exists() check before the
                # transaction reads a state that another request can invalidate
                # before this one writes -- and the failure is silent rather
                # than loud, because get_or_create() swallows the unique
                # violation and re-fetches the winner's row (see Django's
                # _create_object_from_params). The second POST would then take
                # the first one's row, overwrite its quantity with `absolute`,
                # and answer 201 Created, so both owners believe they added it
                # and one of them is looking at the other's count.
                #
                # get_or_create's `created` flag is the same statement that
                # would have clobbered, so there is no window between deciding
                # and acting. On SQLite the IMMEDIATE transaction mode
                # serialises the block outright; on PostgreSQL the loser blocks
                # on the unique index and comes back created=False.
                _, created = PharmacyMedicineStock.objects.get_or_create(
                    pharmacy=self.pharmacy, medicine=medicine,
                    defaults={'price': 0},
                )
                if not created:
                    raise _AlreadyStocked

                # alert=False: the opening quantity is not news. low_threshold
                # defaults to 10, so without this every medicine added with a
                # single-digit opening count -- an ordinary thing to do --
                # pushed a "low stock" alert to every client watching this
                # pharmacy, about a number the owner had just finished typing.
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
        except (_AlreadyStocked, IntegrityError):
            # IntegrityError as well, for the database that raises the unique
            # violation rather than resolving it: same answer either way, and
            # the same answer the sequential case gives.
            return Response({'medicine': [ALREADY_STOCKED]},
                            status=status.HTTP_400_BAD_REQUEST)

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


class OwnerCustomerViewSet(viewsets.ModelViewSet):
    """CRUD for walk-in customers + membership of the owner's pharmacy."""

    permission_classes = [IsPharmacyOwner]
    serializer_class = None  # set below to avoid circular import at module load
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    def get_serializer_class(self):
        from .serializers import PharmacyCustomerSerializer
        return PharmacyCustomerSerializer

    def get_queryset(self):
        from .models import PharmacyCustomer
        pharmacy = self.request.user.pharmacy_owner.pharmacy
        qs = PharmacyCustomer.objects.filter(pharmacy=pharmacy)
        q = (self.request.query_params.get('q') or '').strip()
        if q:
            from django.db.models import Q
            qs = qs.filter(Q(name__icontains=q) | Q(phone__icontains=q))
        return qs

    def perform_create(self, serializer):
        pharmacy = self.request.user.pharmacy_owner.pharmacy
        serializer.save(pharmacy=pharmacy)

    def create(self, request, *args, **kwargs):
        from django.db import IntegrityError
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            return Response(
                {'phone': ['A customer with this phone already exists.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

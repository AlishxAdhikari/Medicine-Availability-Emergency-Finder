from django.contrib.auth.models import AnonymousUser
from rest_framework import status, viewsets
from rest_framework.authentication import SessionAuthentication
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.authentication import JWTAuthentication

from pharmacy.permissions import IsPharmacyOwner
from pharmacy.services import apply_stock_change
from .authentication import POSKeyAuthentication
from .models import StockTransaction
from .serializers import (
    OwnerTransactionSerializer,
    StockSyncSerializer,
    get_medicine_by_barcode_or_name,
)
from .throttling import POSKeyRateThrottle


class StockSyncView(APIView):
    """POST /api/v1/stock/sync/"""
    authentication_classes = [POSKeyAuthentication]
    permission_classes = []
    # A leaked or brute-forced X-POS-API-Key would otherwise be able to hammer
    # this endpoint at any rate DRF's other views allow -- unlike login/register/
    # shared_profile (see medalert_api/settings.py), which were already scoped,
    # this endpoint had no rate limit at all until now. The rate is generous
    # (a real POS could legitimately fire several events per second during a
    # busy checkout), not tight -- this is a ceiling against abuse, not a
    # normal-traffic limiter.
    #
    # Uses a dedicated throttle class rather than just `throttle_scope`
    # (which is what every other scoped view uses): the project-wide default
    # throttle keys off request.user.is_authenticated, and POSKeyAuthentication
    # sets request.user to a Pharmacy instance, not a Django User -- see
    # POSKeyRateThrottle's docstring in sync/throttling.py.
    throttle_classes = [POSKeyRateThrottle]

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

class OwnerTransactionViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/v1/my-pharmacy/transactions/ -- the owner's stock ledger.

    StockTransaction has been written on every stock change since the sync app
    was added (pharmacy/services.py:apply_stock_change is the single writer),
    but nothing could read it back. This is the read side: an audit trail the
    owner can actually see, showing each dispense/restock/adjustment as it
    happens.

    Like OwnerStockViewSet, there is no pharmacy id in the URL. The pharmacy
    comes from the caller's token and every row is filtered to it, so one
    owner cannot read another's sales history by guessing an id.

    Authentication is spelled out here because this app's DEFAULT_AUTHENTICATION
    is not what serves this endpoint: sync's other view uses POSKeyAuthentication
    for machine callers, whereas this one is read by a signed-in human.

    Read-only by design -- the ledger is an immutable audit log, so it is
    exposed through ReadOnlyModelViewSet and never accepts a write.
    """
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsPharmacyOwner]
    serializer_class = OwnerTransactionSerializer

    def get_queryset(self):
        # select_related for the two fields the serializer flattens; without
        # it, a 50-row page of the feed costs 100 extra queries.
        return (
            StockTransaction.objects
            .filter(pharmacy=self.request.user.pharmacy_owner.pharmacy)
            .select_related('medicine', 'changed_by')
        )
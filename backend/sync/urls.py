from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import OwnerTransactionViewSet, StockSyncView

# Mounted at /api/v1/ in medalert_api/urls.py.
#
# The owner-facing ledger lives here rather than in pharmacy/urls.py, next to
# the other my-pharmacy/ routes, because StockTransaction is a sync model and
# sync already imports pharmacy. Registering it from pharmacy would close that
# import loop.
router = DefaultRouter()
router.register('my-pharmacy/transactions', OwnerTransactionViewSet, basename='owner-transaction')

urlpatterns = [
    path('stock/sync/', StockSyncView.as_view(), name='stock-sync'),
] + router.urls

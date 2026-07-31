from rest_framework.routers import DefaultRouter

from .owner_views import OwnerStockViewSet
from .views import MedicineViewSet, PharmacyViewSet

# Mounted at /api/v1/ in medalert_api/urls.py, so the final paths are
# /api/v1/medicines/ and /api/v1/pharmacies/ (plus /api/v1/pharmacies/<id>/stock/),
# and /api/v1/my-pharmacy/stock/ for the owner-only write API.
router = DefaultRouter()
router.register('medicines', MedicineViewSet, basename='medicine')
router.register('pharmacies', PharmacyViewSet, basename='pharmacy')
router.register('my-pharmacy/stock', OwnerStockViewSet, basename='owner-stock')

urlpatterns = router.urls

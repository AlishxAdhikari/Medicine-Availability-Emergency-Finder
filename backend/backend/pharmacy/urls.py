from rest_framework.routers import DefaultRouter

from .views import MedicineViewSet, PharmacyViewSet

# Mounted at /api/v1/ in medalert_api/urls.py, so the final paths are
# /api/v1/medicines/ and /api/v1/pharmacies/ (plus /api/v1/pharmacies/<id>/stock/).
router = DefaultRouter()
router.register('medicines', MedicineViewSet, basename='medicine')
router.register('pharmacies', PharmacyViewSet, basename='pharmacy')

urlpatterns = router.urls

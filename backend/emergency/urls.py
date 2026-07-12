from rest_framework.routers import DefaultRouter

from .views import AmbulanceViewSet, BloodBankViewSet

# Mounted at /api/v1/ in medalert_api/urls.py, so the final paths are
# /api/v1/blood-banks/ and /api/v1/ambulances/
router = DefaultRouter()
router.register('blood-banks', BloodBankViewSet, basename='bloodbank')
router.register('ambulances', AmbulanceViewSet, basename='ambulance')

urlpatterns = router.urls
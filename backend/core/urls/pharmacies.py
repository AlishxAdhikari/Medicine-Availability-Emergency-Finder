from django.urls import path, include
from rest_framework.routers import DefaultRouter
from core.views import PharmacyViewSet, PharmacyMedicineStockViewSet

router = DefaultRouter()
router.register(r'stocks', PharmacyMedicineStockViewSet, basename='stock')
router.register(r'', PharmacyViewSet, basename='pharmacy')

urlpatterns = [
    path('', include(router.urls)),
]

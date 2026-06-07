from django.urls import path, include
from rest_framework.routers import DefaultRouter
from core.views import BloodBankViewSet

router = DefaultRouter()
router.register(r'', BloodBankViewSet, basename='bloodbank')

urlpatterns = [
    path('', include(router.urls)),
]

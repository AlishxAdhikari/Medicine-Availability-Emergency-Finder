from django.urls import path, include
from rest_framework.routers import DefaultRouter
from core.views import MedicalProfileViewSet

router = DefaultRouter()
router.register(r'', MedicalProfileViewSet, basename='medical-profile')

urlpatterns = [
    path('', include(router.urls)),
]

from django.urls import path, include
from rest_framework.routers import DefaultRouter
from core.views import AmbulanceProviderViewSet

router = DefaultRouter()
router.register(r'', AmbulanceProviderViewSet, basename='ambulance')

urlpatterns = [
    path('', include(router.urls)),
]

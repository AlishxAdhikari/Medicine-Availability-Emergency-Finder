from django.contrib import admin
from django.urls import path, include
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
    TokenVerifyView,
)

api_v1 = [
    # Auth
    path('auth/token/', TokenObtainPairView.as_view(), name='token_obtain'),
    path('auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/token/verify/', TokenVerifyView.as_view(), name='token_verify'),
    path('auth/', include('core.urls.auth')),
    # Resources
    path('pharmacies/', include('core.urls.pharmacies')),
    path('medicines/', include('core.urls.medicines')),
    path('blood-banks/', include('core.urls.blood_banks')),
    path('ambulances/', include('core.urls.ambulances')),
    path('medical-id/', include('core.urls.medical_id')),
]

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/v1/', include(api_v1)),
]
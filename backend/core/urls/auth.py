from django.urls import path
from core.views import RegisterView, MedicalProfileViewSet

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('profile/me/', MedicalProfileViewSet.as_view({'get': 'me', 'put': 'me', 'patch': 'me'}), name='profile_me'),
]

from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    CurrentUserView,
    LoginIdentifierView,
    MedicalProfileView,
    RegisterView,
    SharedProfileView,
    ThrottledLoginView,
)

# Mounted at /api/v1/auth/ in medalert_api/urls.py
urlpatterns = [
    path('register/', RegisterView.as_view(), name='auth-register'),
    path('login-identifier/', LoginIdentifierView.as_view(), name='auth-login-identifier'),
    # simplejwt's built-in views handle login and refresh directly —
    # no need to reimplement token issuance ourselves. Login goes through a
    # thin subclass that adds a throttle scope; refresh is left unthrottled
    # because a client whose access token expired mid-session must always be
    # able to renew it, and it already requires a valid refresh token.
    path('login/', ThrottledLoginView.as_view(), name='auth-login'),
    path('refresh/', TokenRefreshView.as_view(), name='auth-refresh'),
    # Re-reads role/pharmacy for a session resumed without a fresh login.
    path('me/', CurrentUserView.as_view(), name='auth-me'),

    # A3: Medical ID
    path('medical-id/', MedicalProfileView.as_view(), name='medical-id'),
    path(
        'medical-id/share/<uuid:share_token>/',
        SharedProfileView.as_view(),
        name='medical-id-share',
    ),
]
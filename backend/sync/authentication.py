from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

from .models import POSIntegrationKey


class POSKeyAuthentication(BaseAuthentication):
    """Custom DRF auth that checks X-POS-API-Key header and sets request.user to the Pharmacy instance."""

    def authenticate(self, request):
        key = request.headers.get('X-POS-API-Key')
        if not key:
            return None  # Allow other authentication methods (JWT etc.)

        try:
            integration = POSIntegrationKey.objects.select_related('pharmacy').get(
                key=key, 
                is_active=True
            )
            return (integration.pharmacy, None)  # request.user = pharmacy
        except POSIntegrationKey.DoesNotExist:
            raise AuthenticationFailed('Invalid POS API key')
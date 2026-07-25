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

    def authenticate_header(self, request):
        """Without this, DRF can't attach a WWW-Authenticate header to the
        error response, and its exception handler silently downgrades an
        AuthenticationFailed from 401 to 403 instead (see
        rest_framework.views.exception_handler). Implementing this fixes
        that -- invalid keys now correctly return 401, not 403.
        """
        return 'X-POS-API-Key'
from rest_framework import permissions


class IsPharmacyOwner(permissions.BasePermission):
    """Allows only users linked to a Pharmacy via PharmacyOwner.

    Role is derived from the link existing, not from a stored field, so
    revoking ownership in admin takes effect on the very next request with
    no token invalidation needed.
    """
    message = 'This account is not linked to a pharmacy.'

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and hasattr(request.user, 'pharmacy_owner')
        )

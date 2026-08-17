from rest_framework.throttling import SimpleRateThrottle


class POSKeyRateThrottle(SimpleRateThrottle):
    """Rate-limits StockSyncView per POS API key, not per Django user.

    The project-wide default (rest_framework.throttling.ScopedRateThrottle,
    see REST_FRAMEWORK in settings.py) keys its cache entry off
    request.user.is_authenticated. That works for every other throttled view
    because they all sit behind JWT auth, where request.user is a real
    Django User. StockSyncView sits behind POSKeyAuthentication instead,
    which deliberately sets request.user to the Pharmacy model instance
    itself (see sync/authentication.py) -- a POS terminal has no user
    account to log in as. Pharmacy has no .is_authenticated, so the default
    throttle raises an AttributeError before the view ever runs.

    This throttles on the API key header directly: each pharmacy's POS
    terminal gets its own bucket, and a request with a missing or invalid
    key still gets throttled by IP (via get_ident) rather than crashing --
    the view's own auth check is what turns that request into a 401, not
    this class.
    """
    scope = 'pos_sync'

    def get_cache_key(self, request, view):
        key = request.headers.get('X-POS-API-Key') or self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': key}
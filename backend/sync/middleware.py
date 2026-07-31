"""JWT authentication for WebSocket connections.

Channels' AuthMiddlewareStack authenticates from the Django session cookie,
which the Flutter client never has -- it holds a JWT pair in secure storage
and talks to DRF with an Authorization header. Browsers can't set custom
headers on a WebSocket handshake, so the token travels in the query string
instead.

That does mean the token can land in server access logs. Accepted
deliberately: access tokens here are short-lived and refreshable, and the
alternative (a subprotocol hack, or a pre-auth ticket endpoint) is more
moving parts than this pipe warrants today.
"""
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth import get_user_model
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken


@database_sync_to_async
def _user_from_token(raw_token):
    try:
        token = AccessToken(raw_token)
    except TokenError:
        return AnonymousUser()

    User = get_user_model()
    try:
        return User.objects.get(pk=token['user_id'])
    except (User.DoesNotExist, KeyError):
        return AnonymousUser()


class JWTAuthMiddleware:
    """Puts a resolved user on the connection scope, or AnonymousUser."""

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        query = parse_qs(scope.get('query_string', b'').decode())
        tokens = query.get('token')
        scope['user'] = await _user_from_token(tokens[0]) if tokens else AnonymousUser()
        return await self.inner(scope, receive, send)

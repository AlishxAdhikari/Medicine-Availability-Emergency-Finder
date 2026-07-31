"""
ASGI config for medalert_api project.

Routes plain HTTP requests through Django as normal, and upgrades
WebSocket connections (ws://.../ws/stock/<pharmacy_id>/) into the
Channels consumer defined in sync/consumers.py.
"""

import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'medalert_api.settings')

# Must call this BEFORE importing anything that touches Django models
# (like sync.routing, which imports consumers.py, which imports models) --
# otherwise Django's app registry isn't ready yet and you'll get
# AppRegistryNotReady errors.
django_asgi_app = get_asgi_application()

import sync.routing  # noqa: E402
from sync.middleware import JWTAuthMiddleware  # noqa: E402

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    # JWT rather than Channels' session-based AuthMiddlewareStack: the Flutter
    # client authenticates with a token pair, never a session cookie.
    "websocket": JWTAuthMiddleware(
        URLRouter(sync.routing.websocket_urlpatterns)
    ),
})
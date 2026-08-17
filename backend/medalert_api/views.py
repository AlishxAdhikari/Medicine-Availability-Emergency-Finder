from django.db import connection
from django.db.utils import OperationalError
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    """GET /api/v1/health/ -- unauthenticated liveness/readiness probe.

    Meant for an external uptime monitor (UptimeRobot, a hosting platform's
    health check, etc.) to poll on an interval and alert if it stops
    answering or starts reporting 'error'. Checks the database specifically
    rather than just returning 200 unconditionally, since "the ASGI process
    is up" and "the app can actually serve a request" are different failure
    modes -- a dead DATABASE_URL or an exhausted connection pool should show
    up here, not just as a wall of unrelated 500s in the request logs.

    Deliberately does not check the Channels/Redis layer: InMemoryChannelLayer
    (the default here, see settings.py) has no external dependency to check,
    and this endpoint should stay meaningful without code changes if a
    deployment switches to the Redis layer.
    """
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
        db_ok = True
    except OperationalError:
        db_ok = False

    status_code = 200 if db_ok else 503
    return Response(
        {'status': 'ok' if db_ok else 'error', 'database': 'ok' if db_ok else 'unreachable'},
        status=status_code,
    )
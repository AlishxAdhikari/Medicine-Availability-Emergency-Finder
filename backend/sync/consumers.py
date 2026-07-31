import json

from channels.generic.websocket import AsyncWebsocketConsumer


class StockConsumer(AsyncWebsocketConsumer):
    """One WebSocket connection per pharmacy dashboard/Flutter client.

    Clients connect to ws://<host>/ws/stock/<pharmacy_id>/ and get pushed a
    JSON message every time sync/signals.py detects that pharmacy's stock
    crossed its low_threshold. No polling needed on the client side.
    """

    async def connect(self):
        # Any signed-in user may watch any pharmacy: pharmacy_search_screen.dart
        # subscribes to whichever pharmacy is the top search result, and this
        # group only ever carries data that GET /api/v1/pharmacies/<id>/stock/
        # already serves publicly. Ownership is deliberately NOT checked here.
        #
        # When live sync broadens, anything owner-only goes to a separate
        # pharmacy_<id>_owner group that does check ownership -- so this socket
        # never becomes a wider channel than the equivalent REST endpoint.
        user = self.scope.get('user')
        if user is None or not user.is_authenticated:
            # Deliberately accept() before close(code=4401): most ASGI servers
            # (Daphne included) respond to a pre-accept close by denying the
            # handshake with a plain HTTP 403, which throws away the custom
            # close code before it ever reaches a real client. Completing the
            # upgrade first means the close frame -- and 4401 specifically --
            # actually arrives, which the Dart client depends on to trigger
            # its token-refresh-and-reconnect-once flow. Nothing is ever sent
            # on the socket in between, so this leaks nothing. Do not "tidy"
            # this back to close-before-accept.
            await self.accept()
            await self.close(code=4401)
            return

        self.pharmacy_id = self.scope['url_route']['kwargs']['pharmacy_id']
        self.group_name = f'pharmacy_{self.pharmacy_id}'

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        group_name = getattr(self, 'group_name', None)
        if group_name is not None:
            await self.channel_layer.group_discard(group_name, self.channel_name)

    # Name must match the "type" key used in channel_layer.group_send() --
    # Channels converts "stock_alert" -> calls this method automatically.
    async def stock_alert(self, event):
        await self.send(text_data=json.dumps(event['data']))
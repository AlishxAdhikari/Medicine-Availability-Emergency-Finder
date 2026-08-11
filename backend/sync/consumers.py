import json

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer


@database_sync_to_async
def _owns_pharmacy(user, pharmacy_id):
    """True when [user] is linked to [pharmacy_id] via PharmacyOwner.

    Same rule as pharmacy/permissions.py:IsPharmacyOwner, evaluated per
    connection. Ownership is derived from the link existing rather than a
    stored role, so an admin revoking it takes effect on the next connect
    with no token invalidation -- and str() on both sides because the id
    arrives from the URL route as text.
    """
    owner_link = getattr(user, 'pharmacy_owner', None)
    if owner_link is None:
        return False
    return str(owner_link.pharmacy_id) == str(pharmacy_id)


class StockConsumer(AsyncWebsocketConsumer):
    """One WebSocket connection per pharmacy dashboard/Flutter client.

    Clients connect to ws://<host>/ws/stock/<pharmacy_id>/ and are pushed
    JSON messages by sync/signals.py. Three kinds arrive, distinguished by an
    `event` key:

      stock_level       -- a medicine's new quantity, on every movement.
                           Public: any signed-in user watching this pharmacy
                           gets it. This is the one customer search results
                           track.
      stock_alert       -- a medicine is at or below its low_threshold.
                           Public, and exceptional rather than routine.
      stock_transaction -- every individual stock movement. Owner-only.

    No polling needed on the client side.
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

        # The owner group carries the full stock ledger: every sale, restock
        # and adjustment. That is strictly more than GET /pharmacies/<id>/stock/
        # exposes publicly -- it is a pharmacy's trading history -- so unlike
        # the group above, membership is gated on actually owning this
        # pharmacy. Keeping it as a second group rather than filtering at send
        # time means a non-owner's socket is never even a candidate recipient.
        self.owner_group_name = None
        if await _owns_pharmacy(user, self.pharmacy_id):
            self.owner_group_name = f'pharmacy_{self.pharmacy_id}_owner'
            await self.channel_layer.group_add(self.owner_group_name, self.channel_name)

        await self.accept()

    async def disconnect(self, close_code):
        group_name = getattr(self, 'group_name', None)
        if group_name is not None:
            await self.channel_layer.group_discard(group_name, self.channel_name)

        owner_group_name = getattr(self, 'owner_group_name', None)
        if owner_group_name is not None:
            await self.channel_layer.group_discard(owner_group_name, self.channel_name)

    # Name must match the "type" key used in channel_layer.group_send() --
    # Channels converts "stock_alert" -> calls this method automatically.
    async def stock_alert(self, event):
        await self.send(text_data=json.dumps(event['data']))

    # Routine level updates, same public group as stock_alert.
    async def stock_level(self, event):
        await self.send(text_data=json.dumps(event['data']))

    # Sent only to the owner group; see connect().
    async def stock_transaction(self, event):
        await self.send(text_data=json.dumps(event['data']))
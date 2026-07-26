import json

from channels.generic.websocket import AsyncWebsocketConsumer


class StockConsumer(AsyncWebsocketConsumer):
    """One WebSocket connection per pharmacy dashboard/Flutter client.

    Clients connect to ws://<host>/ws/stock/<pharmacy_id>/ and get pushed a
    JSON message every time sync/signals.py detects that pharmacy's stock
    crossed its low_threshold. No polling needed on the client side.
    """

    async def connect(self):
        self.pharmacy_id = self.scope['url_route']['kwargs']['pharmacy_id']
        self.group_name = f'pharmacy_{self.pharmacy_id}'

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    # Name must match the "type" key used in channel_layer.group_send() --
    # Channels converts "stock_alert" -> calls this method automatically.
    async def stock_alert(self, event):
        await self.send(text_data=json.dumps(event['data']))
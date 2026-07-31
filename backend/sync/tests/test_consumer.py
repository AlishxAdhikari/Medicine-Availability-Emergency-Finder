"""
C3: tests for sync/consumers.py -- the actual WebSocket layer, using
Channels' WebsocketCommunicator to open a real (in-memory) connection
rather than mocking anything. This is the piece test_signals.py
deliberately doesn't cover: does a message sent to a pharmacy's group
actually arrive at a connected client's socket.

Django 4.1+ runs `async def test_...` methods on a TransactionTestCase
natively, so no extra test runner plugin is needed here.
"""
from datetime import timedelta

from channels.db import database_sync_to_async
from channels.layers import get_channel_layer
from channels.testing import WebsocketCommunicator
from django.contrib.auth import get_user_model
from django.test import TransactionTestCase
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from medalert_api.asgi import application

User = get_user_model()


class StockConsumerTests(TransactionTestCase):

    def setUp(self):
        # Created synchronously here rather than inside the async tests --
        # TransactionTestCase.setUp is sync, so no database_sync_to_async
        # wrapper is needed.
        self.user = User.objects.create_user(username='ws-user', password='pw123456!')
        self.token = str(RefreshToken.for_user(self.user).access_token)

    def url(self, pharmacy_id):
        return f'/ws/stock/{pharmacy_id}/?token={self.token}'

    async def test_client_connects_and_receives_group_message(self):
        """The core round-trip: connect to ws/stock/<id>/, have something
        group_send a stock_alert to that same pharmacy's group, and confirm
        the connected client actually receives it. This is what proves the
        consumer + routing + channel layer are wired together correctly --
        test_signals.py only proves the signal *decides* to send; this
        proves the send actually *arrives*.
        """
        pharmacy_id = 1
        communicator = WebsocketCommunicator(application, self.url(pharmacy_id))
        connected, subprotocol = await communicator.connect()
        self.assertTrue(connected, 'WebSocket failed to connect -- check routing.py path matches')

        channel_layer = get_channel_layer()
        await channel_layer.group_send(
            f'pharmacy_{pharmacy_id}',
            {
                'type': 'stock_alert',
                'data': {
                    'medicine_id': 42,
                    'medicine_name': 'Paracetamol 500mg',
                    'quantity': 2,
                    'level': 'critical',
                },
            },
        )

        response = await communicator.receive_json_from(timeout=2)
        self.assertEqual(response['medicine_id'], 42)
        self.assertEqual(response['medicine_name'], 'Paracetamol 500mg')
        self.assertEqual(response['quantity'], 2)
        self.assertEqual(response['level'], 'critical')

        await communicator.disconnect()

    async def test_client_does_not_receive_other_pharmacies_alerts(self):
        """A client connected to pharmacy 1's group should NOT see an alert
        broadcast to pharmacy 2's group -- this is what proves the
        per-pharmacy group isolation in connect() actually works, not just
        that messages arrive at all.
        """
        communicator = WebsocketCommunicator(application, self.url(1))
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        channel_layer = get_channel_layer()
        await channel_layer.group_send(
            'pharmacy_2',  # a DIFFERENT pharmacy's group
            {
                'type': 'stock_alert',
                'data': {'medicine_id': 99, 'medicine_name': 'X', 'quantity': 0, 'level': 'critical'},
            },
        )

        # receive_nothing() returns True if nothing arrived within the
        # timeout -- that's exactly what we want here, since this client is
        # in pharmacy_1's group and the message went to pharmacy_2's group.
        nothing_arrived = await communicator.receive_nothing(timeout=1)
        self.assertTrue(nothing_arrived, 'Client received a message meant for a different pharmacy')
        await communicator.disconnect()

    async def test_disconnect_removes_client_from_group(self):
        """After disconnecting, a group_send to that pharmacy should not
        raise or hang -- the client should have been cleanly removed from
        the group (group_discard in consumers.py). This mostly guards
        against a connection leak silently keeping stale sockets in a group.
        """
        communicator = WebsocketCommunicator(application, self.url(1))
        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await communicator.disconnect()

        channel_layer = get_channel_layer()
        # Should complete without error even though no one is listening anymore.
        await channel_layer.group_send(
            'pharmacy_1',
            {'type': 'stock_alert', 'data': {'medicine_id': 1, 'medicine_name': 'X', 'quantity': 1, 'level': 'low'}},
        )

    async def _assert_rejected_with_4401(self, communicator, msg=None):
        """StockConsumer.connect() accepts the handshake before closing with
        4401 (see the comment in consumers.py: most ASGI servers turn a
        pre-accept close into a bare HTTP 403 and the custom code never
        reaches a real client). So WebsocketCommunicator.connect() reports
        `connected=True` here -- the upgrade genuinely completed -- and the
        4401 close arrives as the *next* ASGI message, not as the second
        element of connect()'s return tuple. This helper reads that message
        and pins the close code, so a regression back to close-before-accept
        (which would make `connected` False here and short the close frame
        entirely) fails this test.
        """
        connected, _ = await communicator.connect()
        self.assertTrue(connected, msg or 'Handshake should complete so the close frame actually reaches the client')
        close_message = await communicator.receive_output()
        self.assertEqual(close_message['type'], 'websocket.close')
        self.assertEqual(close_message.get('code'), 4401)
        await communicator.disconnect()

    async def test_connection_without_a_token_is_rejected(self):
        """The socket used to accept anyone. It carries only data the public
        REST stock endpoint already serves, so this was never a leak -- but
        unauthenticated clients could open unbounded sockets against
        arbitrary group ids, and the next phase puts richer data on this
        pipe."""
        communicator = WebsocketCommunicator(application, '/ws/stock/1/')
        await self._assert_rejected_with_4401(communicator, 'Anonymous connection should have been rejected')

    async def test_connection_with_a_garbage_token_is_rejected(self):
        communicator = WebsocketCommunicator(application, '/ws/stock/1/?token=not-a-jwt')
        await self._assert_rejected_with_4401(communicator)

    async def test_connection_with_an_expired_token_is_rejected(self):
        token = AccessToken.for_user(self.user)
        # Force the token's expiry into the past rather than waiting out the
        # real lifetime.
        token.set_exp(lifetime=-timedelta(seconds=1))
        communicator = WebsocketCommunicator(application, f'/ws/stock/1/?token={token}')
        await self._assert_rejected_with_4401(communicator, 'Expired token should have been rejected')

    async def test_connection_with_a_deleted_users_token_is_rejected(self):
        token = str(RefreshToken.for_user(self.user).access_token)
        await database_sync_to_async(self.user.delete)()
        communicator = WebsocketCommunicator(application, f'/ws/stock/1/?token={token}')
        await self._assert_rejected_with_4401(communicator, 'A token for a since-deleted user should have been rejected')

    async def test_connection_with_a_deactivated_users_token_is_rejected(self):
        self.user.is_active = False
        await database_sync_to_async(self.user.save)()
        communicator = WebsocketCommunicator(application, self.url(1))
        await self._assert_rejected_with_4401(communicator, "A deactivated user's token should have been rejected")
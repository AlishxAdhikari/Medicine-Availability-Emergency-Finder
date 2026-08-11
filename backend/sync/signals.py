from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db import transaction
from django.db.models.signals import post_save
from django.dispatch import receiver

from pharmacy.models import PharmacyMedicineStock
from .models import StockTransaction


@receiver(post_save, sender=StockTransaction)
def check_threshold(sender, instance, created, **kwargs):
    # Only react to brand-new transactions -- StockTransaction is meant to
    # be append-only, so `created` should always be True in practice, but
    # this guards against any future code path that re-saves a row.
    if not created:
        return

    # Set by apply_stock_change(alert=False) -- a movement the caller has
    # already established is not worth *warning* anyone about (a row being
    # deleted, or a row being created by the owner who is looking at it). Read
    # off the instance rather than from the DB because it is deliberately not a
    # stored field: it describes this one write, not the transaction forever.
    #
    # Scope note: this suppresses the low-stock *alert* only. It used to
    # `return` here and so silently suppressed the ledger push and the level
    # push too, which contradicted broadcast_transaction's own docstring and
    # meant an owner's opening quantity never reached any watching client.
    skip_alert = bool(getattr(instance, 'skip_low_stock_alert', False))

    # post_save fires INSIDE the caller's atomic block, so at this moment the
    # quantity that would be broadcast is not yet committed and may never be.
    # apply_stock_change() runs in its own atomic(), and owner_views.py wraps
    # that in a second one to apply price/low_threshold -- any failure in the
    # rest of that block rolls the quantity back, after clients were already
    # told about it. There is no un-send. on_commit both defers the send until
    # the number is real and moves the read below to committed state, so a
    # rolled-back write is silent and a committed one is described accurately.
    #
    # Outside a transaction, on_commit runs the callback immediately, so the
    # POS path behaves exactly as before.
    #
    # Order matters to one thing only: broadcast_stock_state sends the routine
    # level update before any exceptional alert, so a client applying them in
    # arrival order ends on the alert rather than overwriting it.
    transaction.on_commit(lambda: broadcast_transaction(instance))
    transaction.on_commit(lambda: broadcast_stock_state(instance, alert=not skip_alert))


def broadcast_transaction(txn):
    """Pushes every committed stock movement to the pharmacy's owner group.

    Separate from broadcast_if_low because the two answer different
    questions. A low-stock alert is exceptional and public -- any signed-in
    user watching this pharmacy sees it, because the quantity behind it is
    already served publicly by GET /pharmacies/<id>/stock/. This one is
    routine and private: it is the pharmacy's trading history, which only
    /my-pharmacy/transactions/ exposes and only to the owner. Hence the
    _owner group, whose membership consumers.py gates on ownership.

    Deliberately NOT suppressed by skip_low_stock_alert. That flag means "this
    movement is not worth warning anyone about" -- an opening quantity the
    owner just typed, or the zeroing that precedes a row being deleted. Both
    are still real ledger rows that /my-pharmacy/transactions/ returns, so
    omitting them here would make the live feed disagree with the same feed
    after a refresh.

    The payload matches OwnerTransactionSerializer field for field, so the
    client decodes a pushed row with exactly the same code as a fetched one.
    """
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'pharmacy_{txn.pharmacy_id}_owner',
        {
            'type': 'stock_transaction',  # must match the method in consumers.py
            'data': {
                'event': 'stock_transaction',
                'id': txn.id,
                'medicine': txn.medicine_id,
                'medicine_name': txn.medicine.name,
                'quantity_delta': txn.quantity_delta,
                'transaction_type': txn.transaction_type,
                'source': txn.source,
                'changed_by_username': (
                    txn.changed_by.username if txn.changed_by_id else None
                ),
                'client_timestamp': txn.client_timestamp.isoformat(),
                'server_timestamp': txn.server_timestamp.isoformat(),
            },
        },
    )


def broadcast_stock_state(txn, *, alert=True):
    """Reads the committed stock row for [txn]'s pharmacy/medicine pair and
    pushes its new level to every client watching this pharmacy -- plus a
    stock_alert when that level is at or below its threshold.

    Two messages rather than one because they answer different questions and
    a client may want only one of them:

      stock_level -- the routine fact "this medicine is now at N". Sent on
                     EVERY committed movement. This is what makes a customer's
                     search results track an owner's sale in real time; before
                     it existed the public group carried alerts only, so a sale
                     from 50 to 49 was invisible on every customer phone and
                     live sync appeared broken for all but near-empty stock.
      stock_alert -- the exceptional judgement "this is low enough to warn
                     about", carrying a severity the client renders loudly.

    Both go to the public `pharmacy_<id>` group, which is safe for the same
    reason it always was: GET /pharmacies/<id>/stock/ already serves these
    quantities to any signed-in user. Nothing here is owner-only -- that stays
    in broadcast_transaction's `_owner` group.

    Split out of the receiver so the whole decision -- not just the send --
    happens after commit: reading the row from inside the transaction would
    reinstate exactly the uncommitted-quantity problem on_commit exists to
    avoid. One read serves both messages.
    """
    try:
        stock = PharmacyMedicineStock.objects.get(
            pharmacy=txn.pharmacy, medicine=txn.medicine
        )
    except PharmacyMedicineStock.DoesNotExist:
        # The row is gone -- e.g. an owner removed the medicine between the
        # write and the commit. There is no level to report and no shortage to
        # warn about. This is also what makes the delete path quiet without
        # needing skip_low_stock_alert to gate this function.
        return

    channel_layer = get_channel_layer()
    group = f'pharmacy_{txn.pharmacy_id}'

    async_to_sync(channel_layer.group_send)(
        group,
        {
            'type': 'stock_level',  # must match the method name in consumers.py
            'data': {
                'event': 'stock_level',
                'medicine_id': txn.medicine_id,
                'medicine_name': txn.medicine.name,
                'quantity': stock.quantity,
                # Sent alongside the quantity so a client can colour a chip
                # "low" without having to fetch the threshold separately.
                'low_threshold': stock.low_threshold,
            },
        },
    )

    if not alert:
        return
    if stock.quantity > stock.low_threshold:
        return  # plenty of stock, nothing to warn about

    async_to_sync(channel_layer.group_send)(
        group,
        {
            'type': 'stock_alert',  # must match the method name in consumers.py
            'data': {
                # Discriminator, so a client reading one socket can tell the
                # message kinds apart. Absent on messages sent by older
                # servers, which the client treats as a stock_alert.
                'event': 'stock_alert',
                'medicine_id': txn.medicine_id,
                'medicine_name': txn.medicine.name,
                'quantity': stock.quantity,
                'level': 'critical' if stock.quantity == 0 else 'low',
            },
        },
    )

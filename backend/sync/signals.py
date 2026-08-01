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

    # Set by apply_stock_change(alert=False) -- a ledger row the caller has
    # already established is not worth waking clients for (a row being deleted,
    # or a row being created by the owner who is looking at it). Read off the
    # instance rather than from the DB because it is deliberately not a stored
    # field: it describes this one write, not the transaction forever.
    if getattr(instance, 'skip_low_stock_alert', False):
        return

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
    transaction.on_commit(lambda: broadcast_if_low(instance))


def broadcast_if_low(txn):
    """Reads the committed stock row for [txn]'s pharmacy/medicine pair and
    pushes a stock_alert if it is at or below its threshold.

    Split out of the receiver so the whole decision -- not just the send --
    happens after commit: reading the row from inside the transaction would
    reinstate exactly the uncommitted-quantity problem on_commit exists to
    avoid.
    """
    try:
        stock = PharmacyMedicineStock.objects.get(
            pharmacy=txn.pharmacy, medicine=txn.medicine
        )
    except PharmacyMedicineStock.DoesNotExist:
        # The row is gone -- e.g. an owner removed the medicine between the
        # write and the commit. Nothing to report a shortage about.
        return

    if stock.quantity > stock.low_threshold:
        return  # plenty of stock, nothing to alert about

    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'pharmacy_{txn.pharmacy_id}',
        {
            'type': 'stock_alert',  # must match the method name in consumers.py
            'data': {
                'medicine_id': txn.medicine_id,
                'medicine_name': txn.medicine.name,
                'quantity': stock.quantity,
                'level': 'critical' if stock.quantity == 0 else 'low',
            },
        },
    )

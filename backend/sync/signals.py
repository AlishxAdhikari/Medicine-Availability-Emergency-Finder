from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
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

    try:
        stock = PharmacyMedicineStock.objects.get(
            pharmacy=instance.pharmacy, medicine=instance.medicine
        )
    except PharmacyMedicineStock.DoesNotExist:
        return

    if stock.quantity > stock.low_threshold:
        return  # plenty of stock, nothing to alert about

    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'pharmacy_{instance.pharmacy_id}',
        {
            'type': 'stock_alert',  # must match the method name in consumers.py
            'data': {
                'medicine_id': instance.medicine_id,
                'medicine_name': instance.medicine.name,
                'quantity': stock.quantity,
                'level': 'critical' if stock.quantity == 0 else 'low',
            },
        },
    )
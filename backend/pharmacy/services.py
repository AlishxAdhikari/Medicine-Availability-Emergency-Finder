from math import asin, cos, radians, sin, sqrt

from .models import PharmacyMedicineStock


def haversine_km(lat1, lon1, lat2, lon2):
    """Great-circle distance between two lat/lng points, in kilometres.

    Plain-Python implementation because the current DB is SQLite (no
    PostGIS). This gets called per-row after the queryset is fetched, which
    is fine at the pharmacy counts in this project (report's 10,000-record
    NFR target) but would want to move to a PostGIS ST_Distance query if the
    dataset grew much larger — see report section 2.5.
    """
    r_km = 6371
    phi1, phi2 = radians(lat1), radians(lat2)
    d_phi = radians(lat2 - lat1)
    d_lambda = radians(lon2 - lon1)
    a = sin(d_phi / 2) ** 2 + cos(phi1) * cos(phi2) * sin(d_lambda / 2) ** 2
    return 2 * r_km * asin(sqrt(a))


def sort_by_proximity(queryset, lat, lng, radius_km=None):
    """Attaches a `.distance_km` attribute to each object and returns a
    list sorted nearest-first. Returns a plain list, not a queryset, since
    the distance can't be computed in SQL without PostGIS.

    If radius_km is given, results further than that are dropped entirely.
    """
    results = []
    for obj in queryset:
        distance = haversine_km(lat, lng, obj.latitude, obj.longitude)
        if radius_km is not None and distance > radius_km:
            continue
        obj.distance_km = round(distance, 2)
        results.append(obj)
    results.sort(key=lambda o: o.distance_km)
    return results


def apply_stock_change(pharmacy, medicine, *, absolute=None, delta=None,
                       source, transaction_type, user=None, alert=True):
    """The single write path for stock quantity, used by both the owner API
    and the POS sync endpoint.

    Exactly one of `absolute` or `delta` must be given. The owner endpoints
    pass `absolute` -- an owner counting a shelf knows the total, not the
    difference -- and the POS passes `delta`, since it knows what moved.
    Both are resolved to a final quantity *inside* the row lock, so neither
    caller computes anything from a value it read before the lock existed.

    The lock is select_for_update() on a real database. On SQLite -- which has
    no row-level locking and where Django no-ops select_for_update() -- the
    same serialisation comes from OPTIONS['transaction_mode'] = 'IMMEDIATE' in
    settings.py, which takes the database's write lock at BEGIN. Either way the
    read-then-write below is atomic against a concurrent writer; if you move
    this code to another project, take that setting with it.

    Quantity is clamped at zero, but the StockTransaction records the delta
    that was *requested*, not the clamped one: a POS dispensing 150 units
    from a shelf of 100 is a real discrepancy, and rounding it away in the
    ledger would hide it.

    Writing the StockTransaction is also what makes the low-stock WebSocket
    alert fire -- sync/signals.py hooks post_save on StockTransaction, not on
    the stock row -- so any caller that skips this function silently loses
    alerting.

    `alert=False` writes the ledger row without the alert, for the two owner
    paths where a low quantity is not news: the zeroing write that precedes a
    row's deletion (the medicine is about to stop existing, so "critical, 0
    left" would be a lie), and a row's own creation (the owner just typed that
    number in and is looking at it). Both still land in the ledger -- only the
    broadcast is suppressed. Everything else, POS included, alerts.

    Returns (stock, transaction, clamped).
    """
    if (absolute is None) == (delta is None):
        raise ValueError('Pass exactly one of absolute= or delta=.')

    from django.db import transaction as db_transaction
    from django.utils import timezone

    from sync.models import StockTransaction

    with db_transaction.atomic():
        stock, _ = PharmacyMedicineStock.objects.select_for_update().get_or_create(
            pharmacy=pharmacy, medicine=medicine, defaults={'price': 0.0},
        )

        if absolute is not None:
            requested_delta = absolute - stock.quantity
            target = absolute
        else:
            requested_delta = delta
            target = stock.quantity + delta

        clamped = target < 0
        stock.quantity = max(0, target)
        stock.save(update_fields=['quantity'])

        # Built then saved, rather than objects.create(), so the suppression
        # flag is already on the instance the post_save receiver is handed.
        txn = StockTransaction(
            pharmacy=pharmacy,
            medicine=medicine,
            quantity_delta=requested_delta,
            transaction_type=transaction_type,
            source=source,
            changed_by=user,
            client_timestamp=timezone.now(),
        )
        txn.skip_low_stock_alert = not alert
        txn.save()

    return stock, txn, clamped

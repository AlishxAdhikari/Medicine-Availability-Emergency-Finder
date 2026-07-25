"""
C3: pretends to be a pharmacy's POS terminal, POSTing realistic dispensing/
restocking events to the real sync endpoint at a configurable interval.

Exists so the team can demo and manually exercise the whole ingestion
pipeline (and, once C2 lands, the live WebSocket alert) without needing an
actual pharmacy's POS hardware.

Usage:
    python manage.py simulate_pos
    python manage.py simulate_pos --pharmacy "City Central Pharmacy"
    python manage.py simulate_pos --interval-min 1 --interval-max 3 --once
    python manage.py simulate_pos --base-url http://127.0.0.1:8000
"""
import random
import time

import requests
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from pharmacy.models import Medicine
from sync.models import POSIntegrationKey

# Mostly dispensing (stock going down), with an occasional restock -- this
# mirrors a real pharmacy's traffic pattern far better than uniform random
# deltas would, and is more likely to actually cross a low_threshold so the
# alerting pipeline (C2) has something to react to once it exists.
QUANTITY_DELTA_CHOICES = [-1, -2, -1, -1, -3, -1, 10, 20]


class Command(BaseCommand):
    help = "Simulates a pharmacy POS terminal sending stock-sync events."

    def add_arguments(self, parser):
        parser.add_argument(
            '--base-url', default='http://127.0.0.1:8000',
            help='Base URL of the running Django server (default: %(default)s)',
        )
        parser.add_argument(
            '--pharmacy', default=None,
            help='Name of the pharmacy to simulate (default: a random pharmacy '
                 'that already has a POS integration key)',
        )
        parser.add_argument(
            '--interval-min', type=float, default=2.0,
            help='Minimum seconds between simulated events (default: %(default)s)',
        )
        parser.add_argument(
            '--interval-max', type=float, default=8.0,
            help='Maximum seconds between simulated events (default: %(default)s)',
        )
        parser.add_argument(
            '--once', action='store_true',
            help='Send a single event and exit, instead of looping forever.',
        )

    def handle(self, *args, **options):
        base_url = options['base_url'].rstrip('/')
        sync_url = f"{base_url}/api/v1/stock/sync/"

        integration = self._pick_integration(options['pharmacy'])
        medicines = list(Medicine.objects.all())
        if not medicines:
            raise CommandError(
                "No medicines in the database. Run 'python manage.py "
                "seed_pharmacies' first."
            )

        self.stdout.write(self.style.SUCCESS(
            f"Simulating POS traffic for '{integration.pharmacy.name}' -> {sync_url}"
        ))

        while True:
            medicine = random.choice(medicines)
            delta = random.choice(QUANTITY_DELTA_CHOICES)
            transaction_type = 'RESTOCKED' if delta > 0 else 'DISPENSED'

            payload = {
                'medicine_barcode_or_name': medicine.name,
                'quantity_delta': delta,
                'transaction_type': transaction_type,
                'timestamp': timezone.now().isoformat(),
            }

            try:
                response = requests.post(
                    sync_url,
                    json=payload,
                    headers={'X-POS-API-Key': integration.key},
                    timeout=5,
                )
                self._log(payload, response)
            except requests.exceptions.RequestException as exc:
                self.stderr.write(self.style.ERROR(
                    f"Request failed: {exc} -- is 'python manage.py runserver' "
                    f"running at {base_url}?"
                ))

            if options['once']:
                break
            time.sleep(random.uniform(options['interval_min'], options['interval_max']))

    def _pick_integration(self, pharmacy_name):
        qs = POSIntegrationKey.objects.filter(is_active=True).select_related('pharmacy')
        if pharmacy_name:
            qs = qs.filter(pharmacy__name=pharmacy_name)
            integration = qs.first()
            if integration is None:
                raise CommandError(
                    f"No active POS integration key found for pharmacy "
                    f"'{pharmacy_name}'. Create one via the admin or shell first."
                )
            return integration

        integration = qs.order_by('?').first()
        if integration is None:
            raise CommandError(
                "No POSIntegrationKey rows exist yet. Create one for a "
                "pharmacy first, e.g. via Django admin or:\n"
                "  python manage.py shell -c \"from pharmacy.models import "
                "Pharmacy; from sync.models import POSIntegrationKey; "
                "POSIntegrationKey.objects.create(pharmacy=Pharmacy.objects.first())\""
            )
        return integration

    def _log(self, payload, response):
        sign = '+' if payload['quantity_delta'] > 0 else ''
        line = (
            f"  {payload['transaction_type']:10s} "
            f"{sign}{payload['quantity_delta']:>3d}  {payload['medicine_barcode_or_name']:30s} "
            f"-> HTTP {response.status_code}"
        )
        if response.status_code in (200, 201):
            self.stdout.write(self.style.SUCCESS(line))
        else:
            self.stdout.write(self.style.WARNING(f"{line}  {response.text[:150]}"))
# Pharmacy Owner Role & Stock Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a pharmacy owner log in and edit their own pharmacy's stock, while users keep read-only access.

**Architecture:** A `PharmacyOwner` row links a Django user to a `Pharmacy`; the role is derived from that link rather than stored. Owner-only endpoints live under `/api/v1/my-pharmacy/` and resolve the pharmacy from the JWT, never from the URL. All quantity changes — owner and POS — funnel through one locked service function that writes a `StockTransaction`, which is what makes the existing low-stock WebSocket alert fire on manual edits for free.

**Tech Stack:** Django 6, Django REST Framework, `djangorestframework-simplejwt`, Django Channels (ASGI/Daphne), Flutter/Dart, `http`, `flutter_secure_storage`, `web_socket_channel`.

**Spec:** `docs/superpowers/specs/2026-07-31-pharmacy-owner-role-design.md`

## Global Constraints

- Backend tests run from `backend/` using the project virtualenv: `./venv/Scripts/python.exe manage.py test <app>`. A bare `python` is not on PATH here and will fail with `ModuleNotFoundError: No module named 'django'`.
- Flutter tests run from the repo root: `flutter test`.
- Analyzer must introduce NO NEW issues. `dart analyze` does NOT report "No issues found!" on this repo — it reports **8 pre-existing issues** (1 unused import in `pharmacy_search_screen.dart`, 1 doc-comment lint in `stock_alert_service.dart`, 2 unnecessary imports in `create_account_screen.dart` / `medical_id_screen.dart`, and 4 `use_build_context_synchronously` hits in `create_account_screen.dart`, `login_screen.dart` ×2, `pharmacy_search_screen.dart`). Verify your work by confirming the count is still 8 and no new entry names a line you wrote. Do not fix the pre-existing 8 as part of a task — they are listed in the ledger for final-review triage.
- The dev database is SQLite, which silently no-ops `select_for_update()`. Write the locking code correctly anyway — `sync/tests/test_stock_sync.py::test_concurrent_requests_do_not_lose_updates` already documents this and is expected to fail on SQLite. Do not "fix" it by removing the lock.
- **Verified baseline: `sync` runs 17 tests with exactly ONE failure**, `test_concurrent_requests_do_not_lose_updates`. Any second failure means you broke something. Note that `test_missing_api_key_returns_401` and `test_invalid_api_key_returns_401` have stale docstrings claiming they fail — the bugs they describe were fixed in `sync/views.py` and both tests now pass. Believe the test run, not the docstring.
- Role is derived via `hasattr(user, 'pharmacy_owner')`. Never add a stored `role` field.
- Owner endpoints must re-scope their queryset to the owner's pharmacy on every request, so another pharmacy's row 404s rather than 403s.
- Existing behavior in `sync/views.py` that must survive the Task 3 refactor: a delta driving stock below zero is clamped to 0, but the `StockTransaction` records the **requested** delta, and the response carries `note: 'Quantity was clamped to 0'`.
-  - ~~Do not touch `low_threshold` from the owner API. It is deliberately out of scope.~~ Superseded: a later fix round put `low_threshold` back in scope for the owner API (see `pharmacy/serializers.py::OwnerStockSerializer` and `pharmacy/owner_views.py`, which both allow the owner to set it). This line is kept for history, not as current guidance.
- Commit after each task.

## File Structure

**Backend — create**
- `backend/pharmacy/permissions.py` — `IsPharmacyOwner`
- `backend/pharmacy/owner_views.py` — the `/my-pharmacy/stock/` viewset (kept out of `views.py`, which already holds the public read API)
- `backend/pharmacy/tests_owner.py` — owner API tests
- `backend/sync/middleware.py` — `JWTAuthMiddleware` for WebSocket connections

**Backend — modify**
- `backend/pharmacy/models.py` — add `PharmacyOwner`
- `backend/pharmacy/admin.py` — register `PharmacyOwner`
- `backend/pharmacy/serializers.py` — add `OwnerStockSerializer`
- `backend/pharmacy/services.py` — add `apply_stock_change`
- `backend/pharmacy/urls.py` — register the owner route
- `backend/core/serializers.py` — add `role` + `pharmacy` to `UserSerializer`
- `backend/sync/models.py` — add `StockTransaction.changed_by`
- `backend/sync/views.py` — call `apply_stock_change`
- `backend/sync/consumers.py` — reject unauthenticated connections
- `backend/medalert_api/asgi.py` — swap in `JWTAuthMiddleware`
- `backend/sync/tests/test_consumer.py` — existing tests connect anonymously and **will break** in Task 5

**Flutter — create**
- `lib/services/owner_stock_service.dart`
- `lib/screens/owner_dashboard_screen.dart`
- `test/owner_stock_service_test.dart`
- `test/login_routing_test.dart`

**Flutter — modify**
- `lib/services/api_client.dart` — add `patch`/`delete`
- `lib/state.dart` — role state + snapshot round-trip
- `lib/screens/login_screen.dart` — route on role, both paths
- `lib/screens/home_screen.dart` — clear role on logout
- `lib/main.dart` — register `/owner`
- `lib/services/stock_alert_service.dart` — attach token
- `lib/screens/pharmacy_search_screen.dart` — await the now-async `connect`

---

### Task 1: Ownership model

**Files:**
- Modify: `backend/pharmacy/models.py`
- Modify: `backend/pharmacy/admin.py`
- Modify: `backend/sync/models.py:36-56`
- Test: `backend/pharmacy/tests_owner.py` (create)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `pharmacy.models.PharmacyOwner` with fields `user` (OneToOne to `AUTH_USER_MODEL`, `related_name='pharmacy_owner'`) and `pharmacy` (FK to `Pharmacy`, `related_name='owners'`); `sync.models.StockTransaction.changed_by` (nullable FK to `AUTH_USER_MODEL`, `related_name='stock_changes'`)

- [ ] **Step 1: Write the failing test**

Create `backend/pharmacy/tests_owner.py`:

```python
from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase

from pharmacy.models import Pharmacy, PharmacyOwner

User = get_user_model()


def make_pharmacy(name='Test Pharmacy'):
    return Pharmacy.objects.create(
        name=name, address='Test Address', district='Kathmandu',
        latitude=27.7, longitude=85.3,
    )


class PharmacyOwnerModelTests(TestCase):

    def test_owner_link_exposes_pharmacy_and_marks_role(self):
        """The role is derived from the link, not stored -- this is the
        check every permission and serializer in this feature relies on."""
        user = User.objects.create_user(username='owner1', password='pw123456!')
        pharmacy = make_pharmacy()
        PharmacyOwner.objects.create(user=user, pharmacy=pharmacy)

        user.refresh_from_db()
        self.assertTrue(hasattr(user, 'pharmacy_owner'))
        self.assertEqual(user.pharmacy_owner.pharmacy, pharmacy)

    def test_plain_user_has_no_owner_link(self):
        user = User.objects.create_user(username='plain', password='pw123456!')
        self.assertFalse(hasattr(user, 'pharmacy_owner'))

    def test_a_user_can_own_only_one_pharmacy(self):
        """OneToOneField on user -- a second link for the same user must fail
        rather than silently making 'which pharmacy?' ambiguous."""
        user = User.objects.create_user(username='owner2', password='pw123456!')
        PharmacyOwner.objects.create(user=user, pharmacy=make_pharmacy('A'))

        with self.assertRaises(IntegrityError):
            PharmacyOwner.objects.create(user=user, pharmacy=make_pharmacy('B'))

    def test_a_pharmacy_can_have_several_owners(self):
        pharmacy = make_pharmacy()
        for name in ('owner3', 'owner4'):
            user = User.objects.create_user(username=name, password='pw123456!')
            PharmacyOwner.objects.create(user=user, pharmacy=pharmacy)

        self.assertEqual(pharmacy.owners.count(), 2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python manage.py test pharmacy.tests_owner -v 2`
Expected: FAIL — `ImportError: cannot import name 'PharmacyOwner' from 'pharmacy.models'`

- [ ] **Step 3: Add the model**

Append to `backend/pharmacy/models.py`:

```python
class PharmacyOwner(models.Model):
    """Links a Django user to the pharmacy they run.

    The app has no stored role field on purpose. "Is this user a pharmacy
    owner?" is answered by whether this row exists (hasattr(user,
    'pharmacy_owner')), so there is no second source of truth that can drift
    out of step with the link itself.

    OneToOne on user: a user owns at most one pharmacy, so "which pharmacy is
    this request for?" always has exactly one answer. FK on pharmacy: one shop
    can have several owner logins.

    Created by staff in Django admin -- there is deliberately no self-service
    claim flow, since nothing would stop a user claiming a pharmacy they
    don't run.
    """
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='pharmacy_owner',
    )
    pharmacy = models.ForeignKey(
        Pharmacy,
        on_delete=models.CASCADE,
        related_name='owners',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.username} owns {self.pharmacy.name}"
```

Add to the top of the same file, above `from django.db import models`:

```python
from django.conf import settings
```

- [ ] **Step 4: Add `changed_by` to StockTransaction**

In `backend/sync/models.py`, add this field to `StockTransaction`, directly after the `source` field:

```python
    # Who made the change, for source='MANUAL' rows. Null for POS_SYNC, which
    # authenticates with a pharmacy-wide integration key and has no user
    # behind it. Without this, a MANUAL audit row records that *someone*
    # adjusted stock but not who, which is most of the value of the log.
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='stock_changes',
    )
```

Add to the top of `backend/sync/models.py`:

```python
from django.conf import settings
```

- [ ] **Step 5: Register in admin**

Replace the contents of `backend/pharmacy/admin.py`:

```python
from django.contrib import admin

from .models import Medicine, Pharmacy, PharmacyMedicineStock, PharmacyOwner

admin.site.register(Pharmacy)
admin.site.register(Medicine)
admin.site.register(PharmacyMedicineStock)


@admin.register(PharmacyOwner)
class PharmacyOwnerAdmin(admin.ModelAdmin):
    """Linking a user to a pharmacy here is how an owner account is created --
    the owner registers through the normal app signup first, then staff make
    the link."""
    list_display = ('user', 'pharmacy', 'created_at')
    search_fields = ('user__username', 'user__email', 'pharmacy__name')
    autocomplete_fields = ('user', 'pharmacy')
```

`autocomplete_fields` needs the referenced admins to declare `search_fields`. Replace `admin.site.register(Pharmacy)` with:

```python
@admin.register(Pharmacy)
class PharmacyAdmin(admin.ModelAdmin):
    search_fields = ('name', 'district')
```

Django's built-in `UserAdmin` already declares `search_fields`, so `user` needs nothing further.

- [ ] **Step 6: Make and run migrations**

Run: `cd backend && python manage.py makemigrations pharmacy sync && python manage.py migrate`
Expected: two migrations created (`pharmacy` adds `PharmacyOwner`, `sync` adds `changed_by`), applied cleanly.

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd backend && python manage.py test pharmacy sync -v 2`
Expected: the four new tests PASS. The `sync` suite is unchanged by this task except for the new nullable column; `test_concurrent_requests_do_not_lose_updates` still fails on SQLite as documented.

- [ ] **Step 8: Commit**

```bash
git add backend/pharmacy/models.py backend/pharmacy/admin.py backend/pharmacy/tests_owner.py backend/sync/models.py backend/pharmacy/migrations/ backend/sync/migrations/
git commit -m "feat: add PharmacyOwner link and StockTransaction.changed_by"
```

---

### Task 2: Role in the login response

**Files:**
- Modify: `backend/core/serializers.py:94-102`
- Test: `backend/core/tests.py`

**Interfaces:**
- Consumes: `pharmacy.models.PharmacyOwner` (Task 1)
- Produces: `UserSerializer` emits `role: 'pharmacy_owner' | 'user'` and `pharmacy: {id, name} | null`. The Flutter client reads both in Task 8.

- [ ] **Step 1: Write the failing test**

Append to `backend/core/tests.py`:

```python
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from pharmacy.models import Pharmacy, PharmacyOwner

User = get_user_model()


class LoginRoleTests(TestCase):
    """The login response is the only thing telling the Flutter client which
    screen to open, so role and pharmacy have to be on it -- a second
    round trip would mean the app briefly doesn't know who it's talking to."""

    def setUp(self):
        self.client = APIClient()
        self.password = 'pw123456!'

    def _login(self, username):
        return self.client.post('/api/v1/auth/login-identifier/', {
            'identifier': username, 'password': self.password,
        }, format='json')

    def test_plain_user_login_reports_user_role(self):
        User.objects.create_user(username='plain', email='p@x.com', password=self.password)

        response = self._login('plain')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['role'], 'user')
        self.assertIsNone(response.data['user']['pharmacy'])

    def test_owner_login_reports_owner_role_and_pharmacy(self):
        user = User.objects.create_user(username='owner', email='o@x.com', password=self.password)
        pharmacy = Pharmacy.objects.create(
            name='Owned Pharmacy', address='A', district='Kathmandu',
            latitude=27.7, longitude=85.3,
        )
        PharmacyOwner.objects.create(user=user, pharmacy=pharmacy)

        response = self._login('owner')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['role'], 'pharmacy_owner')
        self.assertEqual(response.data['user']['pharmacy']['id'], pharmacy.id)
        self.assertEqual(response.data['user']['pharmacy']['name'], 'Owned Pharmacy')
```

Make sure `from django.test import TestCase` is imported at the top of the file if it isn't already.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python manage.py test core.tests.LoginRoleTests -v 2`
Expected: FAIL with `KeyError: 'role'`

- [ ] **Step 3: Add the derived fields**

Replace `UserSerializer` in `backend/core/serializers.py`:

```python
class UserSerializer(serializers.ModelSerializer):
    """Read-only representation of the logged-in user, returned alongside
    the register/login response so the client doesn't need a second round
    trip. Includes first_name/last_name so the app can show the person's
    real name on any device, not just the one they registered on.

    role and pharmacy are derived from the PharmacyOwner link rather than
    stored, so they can never disagree with it. The client routes on role
    straight out of the login response -- see login_screen.dart.
    """
    role = serializers.SerializerMethodField()
    pharmacy = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'first_name', 'last_name', 'role', 'pharmacy')

    def get_role(self, obj):
        return 'pharmacy_owner' if hasattr(obj, 'pharmacy_owner') else 'user'

    def get_pharmacy(self, obj):
        owner_link = getattr(obj, 'pharmacy_owner', None)
        if owner_link is None:
            return None
        return {'id': owner_link.pharmacy_id, 'name': owner_link.pharmacy.name}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && python manage.py test core -v 2`
Expected: PASS, including the pre-existing `core` tests.

- [ ] **Step 5: Commit**

```bash
git add backend/core/serializers.py backend/core/tests.py
git commit -m "feat: report pharmacy-owner role and pharmacy on login"
```

---

### Task 3: Shared stock-change service

**Files:**
- Modify: `backend/pharmacy/services.py`
- Modify: `backend/sync/views.py:43-63`
- Test: `backend/pharmacy/tests_owner.py`

**Interfaces:**
- Consumes: `StockTransaction.changed_by` (Task 1)
- Produces: `pharmacy.services.apply_stock_change(pharmacy, medicine, *, absolute=None, delta=None, source, transaction_type, user=None)` returning `(stock, txn, clamped: bool)`. Tasks 4 and the refactored `sync/views.py` both call it.

- [ ] **Step 1: Write the failing test**

Append to `backend/pharmacy/tests_owner.py`:

```python
from django.utils import timezone

from pharmacy.models import Medicine, PharmacyMedicineStock
from pharmacy.services import apply_stock_change
from sync.models import StockTransaction


class ApplyStockChangeTests(TestCase):
    """One locked write path for both callers. The owner API sends an
    absolute count (what's on the shelf); the POS sends a delta (what
    moved). Both resolve to a final quantity inside the lock so neither
    caller does arithmetic on a value it read earlier."""

    def setUp(self):
        self.pharmacy = make_pharmacy()
        self.medicine = Medicine.objects.create(
            name='Paracetamol 500mg', category='Analgesic',
            dosage_form='Tablet', strength='500mg',
        )
        self.stock = PharmacyMedicineStock.objects.create(
            pharmacy=self.pharmacy, medicine=self.medicine, quantity=100, price=10,
        )
        self.user = User.objects.create_user(username='owner5', password='pw123456!')

    def test_absolute_write_records_the_derived_delta(self):
        stock, txn, clamped = apply_stock_change(
            self.pharmacy, self.medicine, absolute=80,
            source='MANUAL', transaction_type='ADJUSTED', user=self.user,
        )

        self.assertEqual(stock.quantity, 80)
        self.assertEqual(txn.quantity_delta, -20)
        self.assertEqual(txn.source, 'MANUAL')
        self.assertEqual(txn.transaction_type, 'ADJUSTED')
        self.assertEqual(txn.changed_by, self.user)
        self.assertFalse(clamped)

    def test_delta_write_applies_the_delta(self):
        stock, txn, clamped = apply_stock_change(
            self.pharmacy, self.medicine, delta=-5,
            source='POS_SYNC', transaction_type='DISPENSED',
        )

        self.assertEqual(stock.quantity, 95)
        self.assertEqual(txn.quantity_delta, -5)
        self.assertIsNone(txn.changed_by)

    def test_delta_below_zero_clamps_quantity_but_logs_requested_delta(self):
        """Pre-existing POS behaviour that must survive this refactor: the
        shelf can't go negative, but the ledger records what was actually
        asked for, so the discrepancy stays visible."""
        stock, txn, clamped = apply_stock_change(
            self.pharmacy, self.medicine, delta=-150,
            source='POS_SYNC', transaction_type='DISPENSED',
        )

        self.assertEqual(stock.quantity, 0)
        self.assertEqual(txn.quantity_delta, -150)
        self.assertTrue(clamped)

    def test_creates_the_stock_row_when_absent(self):
        other = Medicine.objects.create(
            name='Amoxicillin 250mg', category='Antibiotic',
            dosage_form='Capsule', strength='250mg',
        )

        stock, txn, _ = apply_stock_change(
            self.pharmacy, other, absolute=30,
            source='MANUAL', transaction_type='ADJUSTED', user=self.user,
        )

        self.assertEqual(stock.quantity, 30)
        self.assertEqual(txn.quantity_delta, 30)
        self.assertEqual(PharmacyMedicineStock.objects.filter(medicine=other).count(), 1)

    def test_requires_exactly_one_of_absolute_or_delta(self):
        with self.assertRaises(ValueError):
            apply_stock_change(
                self.pharmacy, self.medicine,
                source='MANUAL', transaction_type='ADJUSTED',
            )
        with self.assertRaises(ValueError):
            apply_stock_change(
                self.pharmacy, self.medicine, absolute=10, delta=5,
                source='MANUAL', transaction_type='ADJUSTED',
            )
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python manage.py test pharmacy.tests_owner.ApplyStockChangeTests -v 2`
Expected: FAIL — `ImportError: cannot import name 'apply_stock_change'`

- [ ] **Step 3: Write the service function**

Append to `backend/pharmacy/services.py`:

```python
def apply_stock_change(pharmacy, medicine, *, absolute=None, delta=None,
                       source, transaction_type, user=None):
    """The single write path for stock quantity, used by both the owner API
    and the POS sync endpoint.

    Exactly one of `absolute` or `delta` must be given. The owner endpoints
    pass `absolute` -- an owner counting a shelf knows the total, not the
    difference -- and the POS passes `delta`, since it knows what moved.
    Both are resolved to a final quantity *inside* the row lock, so neither
    caller computes anything from a value it read before the lock existed.

    Quantity is clamped at zero, but the StockTransaction records the delta
    that was *requested*, not the clamped one: a POS dispensing 150 units
    from a shelf of 100 is a real discrepancy, and rounding it away in the
    ledger would hide it.

    Writing the StockTransaction is also what makes the low-stock WebSocket
    alert fire -- sync/signals.py hooks post_save on StockTransaction, not on
    the stock row -- so any caller that skips this function silently loses
    alerting.

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

        txn = StockTransaction.objects.create(
            pharmacy=pharmacy,
            medicine=medicine,
            quantity_delta=requested_delta,
            transaction_type=transaction_type,
            source=source,
            changed_by=user,
            client_timestamp=timezone.now(),
        )

    return stock, txn, clamped
```

Check the top of `services.py` for an existing `PharmacyMedicineStock` import; add `from .models import PharmacyMedicineStock` if it isn't there.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && python manage.py test pharmacy.tests_owner.ApplyStockChangeTests -v 2`
Expected: PASS (5 tests)

- [ ] **Step 5: Refactor the POS sync view onto it**

In `backend/sync/views.py`, replace the `with transaction.atomic():` block and the `return Response(...)` that follows (lines 43-70) with:

```python
        stock, txn, clamped = apply_stock_change(
            pharmacy,
            medicine,
            delta=delta,
            source='POS_SYNC',
            transaction_type=serializer.validated_data['transaction_type'],
        )

        return Response({
            'status': 'accepted',
            'new_quantity': stock.quantity,
            'transaction_id': txn.id,
            'note': 'Quantity was clamped to 0' if clamped else None,
        }, status=status.HTTP_200_OK)
```

Update the imports at the top of `backend/sync/views.py`: add `from pharmacy.services import apply_stock_change`, and drop `from django.db import transaction`, `from django.db.models import F`, and `from pharmacy.models import PharmacyMedicineStock` if nothing else in the file uses them.

Note the one intentional behavior change: `client_timestamp` is now the server's clock rather than the POS-supplied `timestamp`. The serializer still validates `timestamp`, and `sync/tests/test_stock_sync.py::test_duplicate_transaction_same_timestamp` filters on `client_timestamp` — so that test will need its filter changed to count all transactions instead. Do that in the next step.

- [ ] **Step 6: Update the affected sync test**

In `backend/sync/tests/test_stock_sync.py::test_duplicate_transaction_same_timestamp`, replace the assertion:

```python
        self.assertEqual(
            StockTransaction.objects.filter(client_timestamp=shared_timestamp).count(),
            2,
            "Documents current no-dedupe behaviour -- update this test once "
            "the team agrees on a dedupe strategy for retried POS events."
        )
```

with:

```python
        # client_timestamp is now set server-side by apply_stock_change, so
        # this counts rows rather than filtering on the POS-supplied value.
        self.assertEqual(
            StockTransaction.objects.count(),
            2,
            "Documents current no-dedupe behaviour -- update this test once "
            "the team agrees on a dedupe strategy for retried POS events."
        )
```

- [ ] **Step 7: Run the full sync suite**

Run: `cd backend && ./venv/Scripts/python.exe manage.py test sync pharmacy -v 2`
Expected: PASS except the one pre-existing SQLite failure, `test_concurrent_requests_do_not_lose_updates`. Confirm the failure list is exactly that one and no larger — if a second appears, the refactor broke something. In particular `test_missing_api_key_returns_401` and `test_invalid_api_key_returns_401` currently PASS despite docstrings claiming otherwise; if either starts failing, that is a regression you caused.

- [ ] **Step 8: Commit**

```bash
git add backend/pharmacy/services.py backend/pharmacy/tests_owner.py backend/sync/views.py backend/sync/tests/test_stock_sync.py
git commit -m "refactor: funnel all stock writes through apply_stock_change"
```

---

### Task 4: Owner stock API

**Files:**
- Create: `backend/pharmacy/permissions.py`
- Create: `backend/pharmacy/owner_views.py`
- Modify: `backend/pharmacy/serializers.py`
- Modify: `backend/pharmacy/urls.py`
- Test: `backend/pharmacy/tests_owner.py`

**Interfaces:**
- Consumes: `PharmacyOwner` (Task 1), `apply_stock_change` (Task 3)
- Produces: `GET/POST /api/v1/my-pharmacy/stock/`, `PATCH/DELETE /api/v1/my-pharmacy/stock/<id>/`. Consumed by `owner_stock_service.dart` in Task 7.

- [ ] **Step 1: Write the failing test**

Append to `backend/pharmacy/tests_owner.py`:

```python
class OwnerStockApiTests(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.password = 'pw123456!'
        self.owner = User.objects.create_user(username='owner6', password=self.password)
        self.pharmacy = make_pharmacy('My Pharmacy')
        PharmacyOwner.objects.create(user=self.owner, pharmacy=self.pharmacy)

        self.medicine = Medicine.objects.create(
            name='Paracetamol 500mg', category='Analgesic',
            dosage_form='Tablet', strength='500mg',
        )
        self.stock = PharmacyMedicineStock.objects.create(
            pharmacy=self.pharmacy, medicine=self.medicine, quantity=100, price=10,
        )

    def _auth(self, user):
        self.client.force_authenticate(user=user)

    def test_owner_lists_only_their_own_stock(self):
        other_pharmacy = make_pharmacy('Someone Elses')
        PharmacyMedicineStock.objects.create(
            pharmacy=other_pharmacy, medicine=self.medicine, quantity=7, price=5,
        )
        self._auth(self.owner)

        response = self.client.get('/api/v1/my-pharmacy/stock/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['quantity'], 100)
        self.assertEqual(response.data[0]['medicine']['name'], 'Paracetamol 500mg')

    def test_plain_user_is_forbidden(self):
        plain = User.objects.create_user(username='plain6', password=self.password)
        self._auth(plain)

        self.assertEqual(self.client.get('/api/v1/my-pharmacy/stock/').status_code, 403)

    def test_anonymous_is_rejected(self):
        self.assertIn(self.client.get('/api/v1/my-pharmacy/stock/').status_code, (401, 403))

    def test_patch_sets_absolute_quantity_and_logs_manual_transaction(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'quantity': 60}, format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantity, 60)
        txn = StockTransaction.objects.get()
        self.assertEqual(txn.quantity_delta, -40)
        self.assertEqual(txn.source, 'MANUAL')
        self.assertEqual(txn.changed_by, self.owner)

    def test_patch_can_change_price_without_touching_quantity(self):
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'price': '12.50'}, format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.stock.refresh_from_db()
        self.assertEqual(str(self.stock.price), '12.50')
        self.assertEqual(self.stock.quantity, 100)
        self.assertEqual(StockTransaction.objects.count(), 0)

    def test_owner_cannot_touch_another_pharmacys_row(self):
        """404 rather than 403 on purpose -- a 403 would confirm the row
        exists, which is itself a leak."""
        other_pharmacy = make_pharmacy('Someone Elses')
        foreign = PharmacyMedicineStock.objects.create(
            pharmacy=other_pharmacy, medicine=self.medicine, quantity=7, price=5,
        )
        self._auth(self.owner)

        response = self.client.patch(
            f'/api/v1/my-pharmacy/stock/{foreign.id}/', {'quantity': 0}, format='json',
        )

        self.assertEqual(response.status_code, 404)
        foreign.refresh_from_db()
        self.assertEqual(foreign.quantity, 7)

    def test_post_adds_a_medicine(self):
        new_medicine = Medicine.objects.create(
            name='Amoxicillin 250mg', category='Antibiotic',
            dosage_form='Capsule', strength='250mg',
        )
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': new_medicine.id, 'quantity': 25, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 201)
        created = PharmacyMedicineStock.objects.get(pharmacy=self.pharmacy, medicine=new_medicine)
        self.assertEqual(created.quantity, 25)
        self.assertEqual(StockTransaction.objects.filter(medicine=new_medicine).count(), 1)

    def test_post_rejects_a_medicine_already_stocked(self):
        self._auth(self.owner)

        response = self.client.post('/api/v1/my-pharmacy/stock/', {
            'medicine': self.medicine.id, 'quantity': 5, 'price': '8.00',
        }, format='json')

        self.assertEqual(response.status_code, 400)

    def test_delete_zeroes_then_removes_the_row(self):
        """Removing a medicine is 'we no longer carry this', which is not the
        same as a quantity of zero -- so the removal still lands in the
        ledger before the row goes."""
        self._auth(self.owner)

        response = self.client.delete(f'/api/v1/my-pharmacy/stock/{self.stock.id}/')

        self.assertEqual(response.status_code, 204)
        self.assertFalse(PharmacyMedicineStock.objects.filter(id=self.stock.id).exists())
        txn = StockTransaction.objects.get()
        self.assertEqual(txn.quantity_delta, -100)
        self.assertEqual(txn.source, 'MANUAL')

    def test_manual_edit_below_threshold_fires_the_low_stock_alert(self):
        """Routing owner edits through StockTransaction is what makes the
        existing sync/signals.py alert fire on them -- this is the test that
        proves it, since the signal hooks the transaction, not the row."""
        from unittest.mock import patch as mock_patch

        self.stock.low_threshold = 10
        self.stock.save()
        self._auth(self.owner)

        with mock_patch('sync.signals.async_to_sync') as mocked:
            self.client.patch(
                f'/api/v1/my-pharmacy/stock/{self.stock.id}/', {'quantity': 3}, format='json',
            )

        self.assertTrue(mocked.called, 'Low-stock alert did not fire on a manual edit')
```

Add `from rest_framework.test import APIClient` and `from sync.models import StockTransaction` to the imports at the top of `tests_owner.py` if Task 3 didn't already.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python manage.py test pharmacy.tests_owner.OwnerStockApiTests -v 2`
Expected: FAIL — 404s on every request, since the route doesn't exist.

- [ ] **Step 3: Write the permission class**

Create `backend/pharmacy/permissions.py`:

```python
from rest_framework import permissions


class IsPharmacyOwner(permissions.BasePermission):
    """Allows only users linked to a Pharmacy via PharmacyOwner.

    Role is derived from the link existing, not from a stored field, so
    revoking ownership in admin takes effect on the very next request with
    no token invalidation needed.
    """
    message = 'This account is not linked to a pharmacy.'

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and hasattr(request.user, 'pharmacy_owner')
        )
```

- [ ] **Step 4: Write the serializer**

Append to `backend/pharmacy/serializers.py`:

```python
class OwnerStockSerializer(serializers.ModelSerializer):
    """The owner's editable view of a stock row.

    Output-only. The view validates and applies writes itself, because a
    quantity change is not a field assignment -- it has to go through
    apply_stock_change() inside a row lock to produce the audit trail and
    trigger the low-stock alert. Letting a ModelSerializer write `quantity`
    directly would bypass both.

    `medicine` is nested rather than an id so the dashboard can render a name
    without a second request. On create, the view reads the medicine id
    straight off request.data.
    """
    medicine = MedicineSerializer(read_only=True)

    class Meta:
        model = PharmacyMedicineStock
        fields = ('id', 'medicine', 'quantity', 'price', 'low_threshold')
        read_only_fields = fields
```

- [ ] **Step 5: Write the viewset**

Create `backend/pharmacy/owner_views.py`:

```python
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.response import Response

from .models import Medicine, PharmacyMedicineStock
from .permissions import IsPharmacyOwner
from .serializers import OwnerStockSerializer
from .services import apply_stock_change


class OwnerStockViewSet(viewsets.ViewSet):
    """/api/v1/my-pharmacy/stock/ -- the owner's own stock, and the only
    human-facing write path to PharmacyMedicineStock.

    There is no pharmacy id anywhere in these URLs on purpose. The pharmacy
    is resolved from the caller's token (same approach as core's
    MedicalProfileView), so there is no id for a caller to swap for someone
    else's. Every lookup is additionally scoped to that pharmacy, which is
    what turns a foreign row into a 404 rather than a 403 -- a 403 would
    confirm the row exists.
    """
    permission_classes = [IsPharmacyOwner]

    @property
    def pharmacy(self):
        return self.request.user.pharmacy_owner.pharmacy

    def get_queryset(self):
        return PharmacyMedicineStock.objects.filter(
            pharmacy=self.pharmacy
        ).select_related('medicine').order_by('medicine__name')

    def list(self, request):
        serializer = OwnerStockSerializer(self.get_queryset(), many=True)
        return Response(serializer.data)

    def create(self, request):
        medicine = get_object_or_404(Medicine, pk=request.data.get('medicine'))

        if PharmacyMedicineStock.objects.filter(
            pharmacy=self.pharmacy, medicine=medicine
        ).exists():
            return Response(
                {'medicine': ['This pharmacy already stocks that medicine. Edit it instead.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            quantity = int(request.data.get('quantity'))
        except (TypeError, ValueError):
            return Response({'quantity': ['A whole number is required.']},
                            status=status.HTTP_400_BAD_REQUEST)
        if quantity < 0:
            return Response({'quantity': ['Quantity cannot be negative.']},
                            status=status.HTTP_400_BAD_REQUEST)

        stock, _, _ = apply_stock_change(
            self.pharmacy, medicine, absolute=quantity,
            source='MANUAL', transaction_type='ADJUSTED', user=request.user,
        )

        price = request.data.get('price')
        if price is not None:
            stock.price = price
            stock.save(update_fields=['price'])

        return Response(OwnerStockSerializer(stock).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        stock = get_object_or_404(self.get_queryset(), pk=pk)

        if 'quantity' in request.data:
            try:
                quantity = int(request.data['quantity'])
            except (TypeError, ValueError):
                return Response({'quantity': ['A whole number is required.']},
                                status=status.HTTP_400_BAD_REQUEST)
            if quantity < 0:
                return Response({'quantity': ['Quantity cannot be negative.']},
                                status=status.HTTP_400_BAD_REQUEST)
            stock, _, _ = apply_stock_change(
                self.pharmacy, stock.medicine, absolute=quantity,
                source='MANUAL', transaction_type='ADJUSTED', user=request.user,
            )

        if 'price' in request.data:
            stock.price = request.data['price']
            stock.save(update_fields=['price'])

        return Response(OwnerStockSerializer(stock).data)

    def destroy(self, request, pk=None):
        stock = get_object_or_404(self.get_queryset(), pk=pk)

        # Zero it through the ledger first, so removing a row that still had
        # stock on it doesn't vanish from the audit log. The transaction holds
        # its own FKs and survives the row's deletion.
        apply_stock_change(
            self.pharmacy, stock.medicine, absolute=0,
            source='MANUAL', transaction_type='ADJUSTED', user=request.user,
        )
        stock.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
```

- [ ] **Step 6: Register the route**

Replace `backend/pharmacy/urls.py`:

```python
from rest_framework.routers import DefaultRouter

from .owner_views import OwnerStockViewSet
from .views import MedicineViewSet, PharmacyViewSet

# Mounted at /api/v1/ in medalert_api/urls.py, so the final paths are
# /api/v1/medicines/ and /api/v1/pharmacies/ (plus /api/v1/pharmacies/<id>/stock/),
# and /api/v1/my-pharmacy/stock/ for the owner-only write API.
router = DefaultRouter()
router.register('medicines', MedicineViewSet, basename='medicine')
router.register('pharmacies', PharmacyViewSet, basename='pharmacy')
router.register('my-pharmacy/stock', OwnerStockViewSet, basename='owner-stock')

urlpatterns = router.urls
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd backend && python manage.py test pharmacy -v 2`
Expected: PASS (10 tests in `OwnerStockApiTests` plus the earlier classes)

- [ ] **Step 8: Commit**

```bash
git add backend/pharmacy/permissions.py backend/pharmacy/owner_views.py backend/pharmacy/serializers.py backend/pharmacy/urls.py backend/pharmacy/tests_owner.py
git commit -m "feat: owner-only stock API under /my-pharmacy/stock/"
```

---

### Task 5: WebSocket authentication

**Files:**
- Create: `backend/sync/middleware.py`
- Modify: `backend/sync/consumers.py:14-19`
- Modify: `backend/medalert_api/asgi.py:25-30`
- Modify: `backend/sync/tests/test_consumer.py` (all three existing tests break)

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: WebSocket connections require `?token=<access_jwt>`; unauthenticated connections close with code `4401`. `stock_alert_service.dart` supplies the token in Task 6.

- [ ] **Step 1: Update the existing tests to authenticate**

All three tests in `backend/sync/tests/test_consumer.py` connect anonymously and assert `connected` is True. They must now mint a token. Add to the top of the file:

```python
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.tokens import RefreshToken

User = get_user_model()
```

Add a `setUp` and a URL helper to `StockConsumerTests`:

```python
    def setUp(self):
        # Created synchronously here rather than inside the async tests --
        # TransactionTestCase.setUp is sync, so no database_sync_to_async
        # wrapper is needed.
        self.user = User.objects.create_user(username='ws-user', password='pw123456!')
        self.token = str(RefreshToken.for_user(self.user).access_token)

    def url(self, pharmacy_id):
        return f'/ws/stock/{pharmacy_id}/?token={self.token}'
```

Then replace every `WebsocketCommunicator(application, '/ws/stock/1/')` with `WebsocketCommunicator(application, self.url(1))`, and the one in the first test with `WebsocketCommunicator(application, self.url(pharmacy_id))`.

Add a new test to the same class:

```python
    async def test_connection_without_a_token_is_rejected(self):
        """The socket used to accept anyone. It carries only data the public
        REST stock endpoint already serves, so this was never a leak -- but
        unauthenticated clients could open unbounded sockets against
        arbitrary group ids, and the next phase puts richer data on this
        pipe."""
        communicator = WebsocketCommunicator(application, '/ws/stock/1/')
        connected, _ = await communicator.connect()
        self.assertFalse(connected, 'Anonymous connection should have been rejected')
        await communicator.disconnect()

    async def test_connection_with_a_garbage_token_is_rejected(self):
        communicator = WebsocketCommunicator(application, '/ws/stock/1/?token=not-a-jwt')
        connected, _ = await communicator.connect()
        self.assertFalse(connected)
        await communicator.disconnect()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && python manage.py test sync.tests.test_consumer -v 2`
Expected: the two new tests FAIL (anonymous connections still succeed). The three updated tests still pass, since an ignored query string is harmless.

- [ ] **Step 3: Write the middleware**

Create `backend/sync/middleware.py`:

```python
"""JWT authentication for WebSocket connections.

Channels' AuthMiddlewareStack authenticates from the Django session cookie,
which the Flutter client never has -- it holds a JWT pair in secure storage
and talks to DRF with an Authorization header. Browsers can't set custom
headers on a WebSocket handshake, so the token travels in the query string
instead.

That does mean the token can land in server access logs. Accepted
deliberately: access tokens here are short-lived and refreshable, and the
alternative (a subprotocol hack, or a pre-auth ticket endpoint) is more
moving parts than this pipe warrants today.
"""
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth import get_user_model
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken


@database_sync_to_async
def _user_from_token(raw_token):
    try:
        token = AccessToken(raw_token)
    except TokenError:
        return AnonymousUser()

    User = get_user_model()
    try:
        user = User.objects.get(pk=token['user_id'])
    except (User.DoesNotExist, KeyError):
        return AnonymousUser()

    # is_authenticated is True even for a deactivated account, so without this
    # check a disabled user holding an unexpired token would keep the socket
    # while DRF's JWTAuthentication rejects that same token on REST ("User is
    # inactive"). Match the REST contract.
    return user if user.is_active else AnonymousUser()


class JWTAuthMiddleware:
    """Puts a resolved user on the connection scope, or AnonymousUser."""

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        query = parse_qs(scope.get('query_string', b'').decode())
        tokens = query.get('token')
        scope['user'] = await _user_from_token(tokens[0]) if tokens else AnonymousUser()
        return await self.inner(scope, receive, send)
```

- [ ] **Step 4: Reject anonymous connections in the consumer**

Replace `connect()` in `backend/sync/consumers.py`:

```python
    async def connect(self):
        # Any signed-in user may watch any pharmacy: pharmacy_search_screen.dart
        # subscribes to whichever pharmacy is the top search result, and this
        # group only ever carries data that GET /api/v1/pharmacies/<id>/stock/
        # already serves publicly. Ownership is deliberately NOT checked here.
        #
        # When live sync broadens, anything owner-only goes to a separate
        # pharmacy_<id>_owner group that does check ownership -- so this socket
        # never becomes a wider channel than the equivalent REST endpoint.
        # accept() BEFORE close() is deliberate and must not be "tidied up".
        # Closing without accepting makes Daphne deny the handshake with an
        # HTTP 403, and the 4401 never reaches the client -- it survives only
        # in Channels' in-memory test transport. Accepting first completes the
        # upgrade so the close frame, and its code, actually arrive. Nothing is
        # ever sent on the socket before the close, so this leaks nothing.
        user = self.scope.get('user')
        if user is None or not user.is_authenticated:
            await self.accept()
            await self.close(code=4401)
            return

        self.pharmacy_id = self.scope['url_route']['kwargs']['pharmacy_id']
        self.group_name = f'pharmacy_{self.pharmacy_id}'

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
```

`disconnect()` runs even for a rejected connection, and `self.group_name` won't exist then. Make it tolerant:

```python
    async def disconnect(self, close_code):
        group_name = getattr(self, 'group_name', None)
        if group_name is not None:
            await self.channel_layer.group_discard(group_name, self.channel_name)
```

- [ ] **Step 5: Wire the middleware into ASGI**

In `backend/medalert_api/asgi.py`, replace the import of `AuthMiddlewareStack` and the `application` block:

```python
from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application
```

```python
import sync.routing  # noqa: E402
from sync.middleware import JWTAuthMiddleware  # noqa: E402

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    # JWT rather than Channels' session-based AuthMiddlewareStack: the Flutter
    # client authenticates with a token pair, never a session cookie.
    "websocket": JWTAuthMiddleware(
        URLRouter(sync.routing.websocket_urlpatterns)
    ),
})
```

Delete the now-unused `from channels.auth import AuthMiddlewareStack` import.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && python manage.py test sync -v 2`
Expected: all five `test_consumer` tests PASS. `test_signals.py` unaffected. `test_stock_sync.py` still has its three documented failures.

- [ ] **Step 7: Commit**

```bash
git add backend/sync/middleware.py backend/sync/consumers.py backend/medalert_api/asgi.py backend/sync/tests/test_consumer.py
git commit -m "feat: require a JWT to open the stock WebSocket"
```

---

### Task 6: Flutter client plumbing

**Files:**
- Modify: `lib/services/api_client.dart:88-95`
- Modify: `lib/state.dart:160-298`, `lib/state.dart:300-329`
- Modify: `lib/services/stock_alert_service.dart:56-86`
- Modify: `lib/screens/pharmacy_search_screen.dart:373-387`
- Test: `test/owner_state_test.dart` (create)

**Interfaces:**
- Consumes: the login response shape from Task 2
- Produces: `ApiClient.patch(path, body, {auth})` and `ApiClient.delete(path, {auth})`; `AppStateManager.isPharmacyOwnerNotifier` (`ValueNotifier<bool>`), `AppStateManager.ownedPharmacyIdNotifier` (`ValueNotifier<int?>`), `AppStateManager.ownedPharmacyNameNotifier` (`ValueNotifier<String>`), `AppStateManager.setOwnerRole({required bool isOwner, int? pharmacyId, String pharmacyName})`, `AppStateManager.clearOwnerRole()`; `StockAlertService.connect` becomes `Future<Stream<StockAlert>>`

- [ ] **Step 1: Write the failing test**

Create `test/owner_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/state.dart';

void main() {
  setUp(() {
    AppStateManager.instance.clearOwnerRole();
  });

  test('owner role is recorded and exposed', () {
    AppStateManager.instance.setOwnerRole(
      isOwner: true,
      pharmacyId: 7,
      pharmacyName: 'My Pharmacy',
    );

    expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isTrue);
    expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, 7);
    expect(AppStateManager.instance.ownedPharmacyNameNotifier.value, 'My Pharmacy');
  });

  test('clearing the role resets every owner field', () {
    AppStateManager.instance.setOwnerRole(
      isOwner: true,
      pharmacyId: 7,
      pharmacyName: 'My Pharmacy',
    );

    AppStateManager.instance.clearOwnerRole();

    expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isFalse);
    expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, isNull);
    expect(AppStateManager.instance.ownedPharmacyNameNotifier.value, '');
  });

  test('owner role survives a snapshot round trip', () {
    // The biometric login path restores from a snapshot rather than a login
    // response, so without this an owner unlocking with a fingerprint lands
    // on the user home screen instead of their dashboard.
    AppStateManager.instance.setOwnerRole(
      isOwner: true,
      pharmacyId: 7,
      pharmacyName: 'My Pharmacy',
    );
    final profile = AppStateManager.instance.userProfileNotifier.value;

    final snapshot = profileToSnapshot(profile);
    AppStateManager.instance.clearOwnerRole();
    applyOwnerRoleFromSnapshot(snapshot);

    expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isTrue);
    expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, 7);
    expect(AppStateManager.instance.ownedPharmacyNameNotifier.value, 'My Pharmacy');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/owner_state_test.dart`
Expected: FAIL — compile error, `setOwnerRole` isn't defined.

- [ ] **Step 3: Add the role state**

In `lib/state.dart`, inside `AppStateManager` alongside the other notifiers (after `isLoggedInNotifier` at line 169):

```dart
  /// Whether the signed-in account is linked to a pharmacy. Set from the
  /// `role` field on the login response (see core/serializers.py's
  /// UserSerializer), and from the saved snapshot on the biometric path.
  final ValueNotifier<bool> isPharmacyOwnerNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int?> ownedPharmacyIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String> ownedPharmacyNameNotifier = ValueNotifier<String>('');
```

And alongside the other mutators (after `setLoggedIn`):

```dart
  void setOwnerRole({required bool isOwner, int? pharmacyId, String pharmacyName = ''}) {
    isPharmacyOwnerNotifier.value = isOwner;
    ownedPharmacyIdNotifier.value = isOwner ? pharmacyId : null;
    ownedPharmacyNameNotifier.value = isOwner ? pharmacyName : '';
  }

  /// Call on logout as well as before a fresh login, so one account's
  /// pharmacy can't leak into the next session on a shared device.
  void clearOwnerRole() {
    setOwnerRole(isOwner: false);
  }
```

- [ ] **Step 4: Add the snapshot round trip**

In `profileToSnapshot` in `lib/state.dart`, add these three entries to the returned map:

```dart
    'isPharmacyOwner': AppStateManager.instance.isPharmacyOwnerNotifier.value,
    'ownedPharmacyId': AppStateManager.instance.ownedPharmacyIdNotifier.value,
    'ownedPharmacyName': AppStateManager.instance.ownedPharmacyNameNotifier.value,
```

Add this top-level function next to `profileFromSnapshot`:

```dart
/// Restores the owner role from a biometric snapshot. Kept separate from
/// profileFromSnapshot because that builds a UserProfile, while the role
/// lives on AppStateManager rather than on the profile object.
void applyOwnerRoleFromSnapshot(Map<String, dynamic> s) {
  AppStateManager.instance.setOwnerRole(
    isOwner: s['isPharmacyOwner'] as bool? ?? false,
    pharmacyId: s['ownedPharmacyId'] as int?,
    pharmacyName: s['ownedPharmacyName'] as String? ?? '',
  );
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/owner_state_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Add PATCH and DELETE to ApiClient**

In `lib/services/api_client.dart`, after the `put` method:

```dart
  /// PATCH with a JSON body -- the owner stock API takes partial updates
  /// (quantity alone, price alone), so PUT would force the client to send
  /// fields it isn't changing.
  Future<dynamic> patch(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.patch(uri, headers: await _headers(auth: auth), body: jsonEncode(body));
    return _handleResponse(response, retryRequest: () => patch(path, body, auth: auth));
  }

  Future<dynamic> delete(String path, {bool auth = false}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.delete(uri, headers: await _headers(auth: auth));
    return _handleResponse(response, retryRequest: () => delete(path, auth: auth));
  }
```

- [ ] **Step 7: Attach the token to the WebSocket**

In `lib/services/stock_alert_service.dart`, add `import 'api_client.dart';` at the top, then change `connect` to be async and append the token:

```dart
  /// Connects to a specific pharmacy's stock-alert group. Returns a
  /// broadcast stream so multiple widgets could listen if needed, though
  /// typically only one screen watches a given pharmacy at a time.
  ///
  /// The access token goes in the query string because browsers can't set
  /// custom headers on a WebSocket handshake -- sync/middleware.py reads it
  /// from there. Without a valid token the server accepts the socket and then
  /// immediately closes it with code 4401.
  Future<Stream<StockAlert>> connect(int pharmacyId) async {
    disconnect(); // close any previous connection first -- one at a time

    _retriedAfterAuthFailure = false;
    // The controller is created here, not in _attach, so it survives a
    // reconnect -- the caller keeps listening to the same stream across a
    // token refresh and never sees the socket flap.
    _controller = StreamController<StockAlert>.broadcast();
    await _attach(pharmacyId);
    return _controller!.stream;
  }

  Future<void> _attach(int pharmacyId) async {
    final token = await ApiClient.instance.accessToken;
    final uri = Uri.parse('$_wsBaseUrl/ws/stock/$pharmacyId/').replace(
      queryParameters: {if (token != null) 'token': token},
    );
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (raw) {
        try {
          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller?.add(StockAlert.fromJson(json));
        } catch (_) {
          // Malformed message from the server -- drop it rather than
          // crashing the whole stream for one bad payload.
        }
      },
      onError: (_) {
        // Connection dropped (server restarted, network blip, etc). The
        // stream just ends; the UI's listener should treat "no more
        // alerts" as normal rather than fatal.
        _controller?.close();
      },
      onDone: () async {
        // 4401 from sync/consumers.py means the access token was missing,
        // expired, or belongs to a deleted/deactivated user. An access token
        // lives 30 minutes (SIMPLE_JWT in settings.py), so a screen left open
        // will hit this routinely -- refresh once and reopen rather than
        // silently going dead until the user navigates away and back.
        // Retry once only: if the refresh itself is what's failing, reopening
        // in a loop would hammer the server.
        if (_channel?.closeCode == 4401 && !_retriedAfterAuthFailure) {
          _retriedAfterAuthFailure = true;
          if (await ApiClient.instance.refreshAccessToken()) {
            await _attach(pharmacyId);
            return; // same controller, so the caller's stream stays alive
          }
        }
        _controller?.close();
      },
    );
  }
```

Add the retry flag alongside the existing fields at the top of the class:

```dart
  bool _retriedAfterAuthFailure = false;
```

The old body of `connect` is fully replaced by the two methods above — do not leave a duplicate `listen` block behind. `disconnect()` is unchanged.

- [ ] **Step 8: Update the one caller**

In `lib/screens/pharmacy_search_screen.dart`, make `_watchTopResultForLiveStock` async and await the connect:

```dart
  Future<void> _watchTopResultForLiveStock() async {
    if (_results.isEmpty) {
      _alertSubscription?.cancel();
      _alertService.disconnect();
      _watchedPharmacyId = null;
      return;
    }

    final topPharmacy = _results.first;
    if (_watchedPharmacyId == topPharmacy.id) return; // already watching this one

    _alertSubscription?.cancel();
    _watchedPharmacyId = topPharmacy.id;
    final stream = await _alertService.connect(topPharmacy.id);
    if (!mounted) return;
    _alertSubscription = stream.listen(_onStockAlert);
  }
```

Its call site does not need to await — it is fire-and-forget. If the analyzer flags an unawaited future there, prefix the call with `unawaited(` from `dart:async` and import it.

- [ ] **Step 9: Verify analyzer and full suite**

Run: `dart analyze && flutter test`
Expected: "No issues found!" and all tests pass (1 pre-existing skip in `widget_test.dart`).

- [ ] **Step 10: Commit**

```bash
git add lib/services/api_client.dart lib/state.dart lib/services/stock_alert_service.dart lib/screens/pharmacy_search_screen.dart test/owner_state_test.dart
git commit -m "feat: owner role state, PATCH/DELETE support, authenticated stock socket"
```

---

### Task 7: Owner stock service

**Files:**
- Create: `lib/services/owner_stock_service.dart`
- Test: `test/owner_stock_service_test.dart` (create)

**Interfaces:**
- Consumes: `ApiClient.patch`/`delete` (Task 6), the endpoints from Task 4
- Produces: `OwnerStock` model (`id`, `medicineId`, `medicineName`, `quantity`, `price`) and `OwnerStockService.instance` with `fetchStock()`, `setQuantity(int stockId, int quantity)`, `addMedicine({required int medicineId, required int quantity, required String price})`, `removeStock(int stockId)`. Task 9's dashboard calls all four.

- [ ] **Step 1: Write the failing test**

Create `test/owner_stock_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/owner_stock_service.dart';

void main() {
  group('OwnerStock.fromJson', () {
    test('maps the nested medicine shape from OwnerStockSerializer', () {
      final stock = OwnerStock.fromJson({
        'id': 3,
        'medicine': {'id': 11, 'name': 'Paracetamol 500mg'},
        'quantity': 42,
        'price': '10.50',
      });

      expect(stock.id, 3);
      expect(stock.medicineId, 11);
      expect(stock.medicineName, 'Paracetamol 500mg');
      expect(stock.quantity, 42);
      expect(stock.price, '10.50');
    });

    test('tolerates a missing price rather than throwing', () {
      // DRF renders DecimalField as a string, but a row created by the POS
      // sync defaults to 0.0 -- don't let a shape surprise blank the screen.
      final stock = OwnerStock.fromJson({
        'id': 4,
        'medicine': {'id': 12, 'name': 'Amoxicillin 250mg'},
        'quantity': 0,
      });

      expect(stock.price, '0');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/owner_stock_service_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'medalert/services/owner_stock_service.dart'`

- [ ] **Step 3: Write the service**

Create `lib/services/owner_stock_service.dart`:

```dart
import 'api_client.dart';

/// One row of the owner's own stock, as returned by OwnerStockSerializer
/// in pharmacy/serializers.py.
class OwnerStock {
  final int id;
  final int medicineId;
  final String medicineName;
  final int quantity;
  final String price;

  OwnerStock({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.price,
  });

  factory OwnerStock.fromJson(Map<String, dynamic> json) {
    final medicine = Map<String, dynamic>.from(json['medicine'] as Map);
    return OwnerStock(
      id: json['id'] as int,
      medicineId: medicine['id'] as int,
      medicineName: medicine['name'] as String,
      quantity: json['quantity'] as int,
      // DRF renders DecimalField as a string; a row the POS created defaults
      // to 0.0, so don't assume the key is always present.
      price: json['price']?.toString() ?? '0',
    );
  }
}

/// Wraps /api/v1/my-pharmacy/stock/ -- the owner-only write API built in
/// pharmacy/owner_views.py. Every call is authenticated; the backend
/// resolves which pharmacy from the token, so no pharmacy id is ever sent.
class OwnerStockService {
  OwnerStockService._internal();
  static final OwnerStockService instance = OwnerStockService._internal();

  final _client = ApiClient.instance;

  Future<List<OwnerStock>> fetchStock() async {
    final data = await _client.get('/my-pharmacy/stock/', auth: true);
    return (data as List)
        .map((row) => OwnerStock.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Sends the absolute count the owner sees on the shelf. The server
  /// derives the delta inside a row lock -- see apply_stock_change().
  Future<OwnerStock> setQuantity(int stockId, int quantity) async {
    final data = await _client.patch(
      '/my-pharmacy/stock/$stockId/', {'quantity': quantity}, auth: true,
    );
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<OwnerStock> setPrice(int stockId, String price) async {
    final data = await _client.patch(
      '/my-pharmacy/stock/$stockId/', {'price': price}, auth: true,
    );
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<OwnerStock> addMedicine({
    required int medicineId,
    required int quantity,
    required String price,
  }) async {
    final data = await _client.post('/my-pharmacy/stock/', {
      'medicine': medicineId,
      'quantity': quantity,
      'price': price,
    }, auth: true);
    return OwnerStock.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> removeStock(int stockId) async {
    await _client.delete('/my-pharmacy/stock/$stockId/', auth: true);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/owner_stock_service_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/owner_stock_service.dart test/owner_stock_service_test.dart
git commit -m "feat: owner stock service wrapping /my-pharmacy/stock/"
```

---

### Task 8: Role-aware login routing

**Files:**
- Modify: `lib/screens/login_screen.dart:23-56`, `lib/screens/login_screen.dart:65-116`
- Modify: `lib/screens/home_screen.dart:69-74`
- Modify: `lib/main.dart:31-36`
- Test: `test/login_routing_test.dart` (create)

**Interfaces:**
- Consumes: `setOwnerRole`/`clearOwnerRole`/`applyOwnerRoleFromSnapshot` (Task 6), the `role` field (Task 2)
- Produces: a top-level `String routeForRole(Map<String, dynamic> user)` in `login_screen.dart` returning `'/owner'` or `'/home'`; the `/owner` route registered in `main.dart`

- [ ] **Step 1: Write the failing test**

Create `test/login_routing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/screens/login_screen.dart';

void main() {
  group('routeForRole', () {
    test('sends a pharmacy owner to the dashboard', () {
      final route = routeForRole({
        'role': 'pharmacy_owner',
        'pharmacy': {'id': 7, 'name': 'My Pharmacy'},
      });

      expect(route, '/owner');
    });

    test('sends a plain user home', () {
      expect(routeForRole({'role': 'user', 'pharmacy': null}), '/home');
    });

    test('falls back to home when the server sends no role', () {
      // An older backend, or a response shape change -- default to the
      // read-only experience rather than opening an editor the account may
      // have no permission to use.
      expect(routeForRole({}), '/home');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/login_routing_test.dart`
Expected: FAIL — `routeForRole` isn't defined.

- [ ] **Step 3: Add the routing helper**

At the top level of `lib/screens/login_screen.dart` (outside the class), after the imports:

```dart
/// Picks the landing route from the `role` field on the login response
/// (core/serializers.py's UserSerializer). Falls back to the user home when
/// role is missing, so an older backend degrades to the read-only
/// experience rather than opening an editor the account can't use.
String routeForRole(Map<String, dynamic> user) {
  return user['role'] == 'pharmacy_owner' ? '/owner' : '/home';
}
```

- [ ] **Step 4: Route on the password path**

In `_handleLogin`, replace the block from `AppStateManager.instance.setLoggedIn(true);` through `Navigator.pushReplacementNamed(context, '/home');` (lines 98-99) with:

```dart
      final pharmacy = user['pharmacy'] as Map<String, dynamic>?;
      AppStateManager.instance.setOwnerRole(
        isOwner: user['role'] == 'pharmacy_owner',
        pharmacyId: pharmacy?['id'] as int?,
        pharmacyName: pharmacy?['name'] as String? ?? '',
      );

      // Re-snapshot after the role is set, so the biometric path restores it
      // too -- otherwise a fingerprint login drops an owner on the user home.
      if (await BiometricService.instance.isEnabled) {
        final p = AppStateManager.instance.userProfileNotifier.value;
        await BiometricService.instance.saveUserSnapshot(profileToSnapshot(p));
      }
      if (!mounted) return;

      AppStateManager.instance.setLoggedIn(true);
      Navigator.pushReplacementNamed(context, routeForRole(user));
```

Delete the now-duplicated earlier `if (await BiometricService.instance.isEnabled)` block at lines 93-96 — the snapshot must be taken *after* `setOwnerRole`, not before, or it saves a stale role.

- [ ] **Step 5: Route on the biometric path**

In `_handleBiometricLogin`, replace the block from `if (snapshot != null) {` through `Navigator.pushReplacementNamed(context, '/home');` with:

```dart
        final snapshot = await BiometricService.instance.getUserSnapshot();
        if (snapshot != null) {
          AppStateManager.instance.updateProfile(profileFromSnapshot(snapshot));
          applyOwnerRoleFromSnapshot(snapshot);
        }

        try {
          await MedicalProfileService.instance.fetch();
        } catch (_) {}

        final p = AppStateManager.instance.userProfileNotifier.value;
        await BiometricService.instance.saveUserSnapshot(profileToSnapshot(p));
        if (!mounted) return;

        AppStateManager.instance.setLoggedIn(true);
        Navigator.pushReplacementNamed(
          context,
          AppStateManager.instance.isPharmacyOwnerNotifier.value ? '/owner' : '/home',
        );
```

- [ ] **Step 6: Clear the role on logout**

In `lib/screens/home_screen.dart`, immediately before the existing `AppStateManager.instance.setLoggedIn(false);` (line 74), add:

```dart
              AppStateManager.instance.clearOwnerRole();
```

- [ ] **Step 7: Register the route**

In `lib/main.dart`, add the import and the route:

```dart
import 'screens/owner_dashboard_screen.dart';
```

```dart
            '/owner': (context) => const OwnerDashboardScreen(),
```

This will not compile until Task 9 creates the screen. Create a minimal placeholder now so this task's tests can run, and Task 9 fills it in:

```dart
// lib/screens/owner_dashboard_screen.dart
import 'package:flutter/material.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `dart analyze && flutter test`
Expected: "No issues found!" and all tests pass, including the three new routing tests.

- [ ] **Step 9: Commit**

```bash
git add lib/screens/login_screen.dart lib/screens/home_screen.dart lib/main.dart lib/screens/owner_dashboard_screen.dart test/login_routing_test.dart
git commit -m "feat: route pharmacy owners to their dashboard after login"
```

---

### Task 9: Owner dashboard screen

**Files:**
- Modify: `lib/screens/owner_dashboard_screen.dart` (replace the Task 8 placeholder)
- Test: manual, plus `dart analyze` and the existing suite

**Interfaces:**
- Consumes: `OwnerStockService` (Task 7), `ownedPharmacyNameNotifier` (Task 6), `PharmacyService` for the medicine search
- Produces: the `/owner` screen

- [ ] **Step 1: Check the medicine search helper exists**

Run: `grep -n "searchMedicines\|/medicines/" lib/services/pharmacy_service.dart`
Expected: a method hitting `/medicines/`. If there isn't one, add:

```dart
  /// GET /api/v1/medicines/?search= -- the catalog the owner picks from when
  /// adding a medicine their pharmacy doesn't stock yet.
  Future<List<Map<String, dynamic>>> searchMedicines(String query) async {
    final data = await _client.get('/medicines/', query: {'search': query});
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
```

- [ ] **Step 2: Write the screen**

Replace `lib/screens/owner_dashboard_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/owner_stock_service.dart';
import '../services/pharmacy_service.dart';
import '../state.dart';

/// The pharmacy owner's stock editor -- the only human-facing write path to
/// PharmacyMedicineStock. Reached from login when the account is linked to a
/// pharmacy (see routeForRole in login_screen.dart).
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  List<OwnerStock> _stock = [];
  bool _loading = true;
  String? _error;
  // Per-row inline errors, keyed by stock id, so one rejected edit doesn't
  // replace the whole list with an error screen.
  final Map<int, String> _rowErrors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stock = await OwnerStockService.instance.fetchStock();
      if (!mounted) return;
      setState(() {
        _stock = stock;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 403 means the owner link was removed while this session was open.
      // Drop back to the normal app rather than looping on an error.
      if (e.statusCode == 403) {
        AppStateManager.instance.clearOwnerRole();
        Navigator.pushReplacementNamed(context, '/home');
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _editRow(OwnerStock row) async {
    final quantityController = TextEditingController(text: row.quantity.toString());
    final priceController = TextEditingController(text: row.price);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row.medicineName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Quantity on shelf',
                helperText: 'Enter the total count, not the change.',
              ),
            ),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final quantity = int.tryParse(quantityController.text.trim());
    final price = priceController.text.trim();

    setState(() => _rowErrors.remove(row.id));
    try {
      OwnerStock updated = row;
      // Two calls rather than one, because a quantity change goes through the
      // ledger and a price change doesn't -- keeping them separate means a
      // price correction never writes a phantom stock adjustment.
      if (quantity != null && quantity != row.quantity) {
        updated = await OwnerStockService.instance.setQuantity(row.id, quantity);
      }
      if (price != row.price) {
        updated = await OwnerStockService.instance.setPrice(row.id, price);
      }
      if (!mounted) return;
      setState(() {
        final index = _stock.indexWhere((s) => s.id == row.id);
        if (index != -1) _stock[index] = updated;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // Leave the old values on screen -- the write didn't happen.
      setState(() => _rowErrors[row.id] = e.message);
    }
  }

  Future<void> _removeRow(OwnerStock row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove medicine'),
        content: Text(
          'Remove ${row.medicineName} from your stock list? '
          'This says your pharmacy no longer carries it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await OwnerStockService.instance.removeStock(row.id);
      if (!mounted) return;
      setState(() => _stock.removeWhere((s) => s.id == row.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _rowErrors[row.id] = e.message);
    }
  }

  Future<void> _addMedicine() async {
    final searchController = TextEditingController();
    final quantityController = TextEditingController(text: '0');
    final priceController = TextEditingController(text: '0.00');
    List<Map<String, dynamic>> results = [];
    int? selectedId;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add a medicine'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(labelText: 'Search the catalog'),
                  onSubmitted: (value) async {
                    final found = await PharmacyService.instance.searchMedicines(value.trim());
                    setDialogState(() => results = found);
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 160,
                  child: ListView(
                    children: results.map((m) {
                      return RadioListTile<int>(
                        value: m['id'] as int,
                        groupValue: selectedId,
                        title: Text(m['name'] as String),
                        onChanged: (value) => setDialogState(() => selectedId = value),
                      );
                    }).toList(),
                  ),
                ),
                TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      try {
                        await OwnerStockService.instance.addMedicine(
                          medicineId: selectedId!,
                          quantity: int.tryParse(quantityController.text.trim()) ?? 0,
                          price: priceController.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(e.message)),
                        );
                      }
                    },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<String>(
          valueListenable: AppStateManager.instance.ownedPharmacyNameNotifier,
          builder: (context, name, _) => Text(name.isEmpty ? 'My Pharmacy' : name),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Open the main app',
            onPressed: () => Navigator.pushNamed(context, '/home'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMedicine,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_stock.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No medicines yet. Use "Add medicine" to start your stock list.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _stock.length,
        itemBuilder: (context, index) {
          final row = _stock[index];
          final rowError = _rowErrors[row.id];
          return ListTile(
            title: Text(row.medicineName),
            subtitle: Text(
              rowError ?? 'Qty ${row.quantity}  ·  Rs ${row.price}',
              style: rowError != null ? TextStyle(color: theme.colorScheme.error) : null,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit quantity and price',
                  onPressed: () => _editRow(row),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () => _removeRow(row),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Verify analyzer and suite**

Run: `dart analyze && flutter test`
Expected: "No issues found!" and all tests pass.

- [ ] **Step 4: Manual end-to-end check**

1. `cd backend && python manage.py runserver 0.0.0.0:8000`
2. In Django admin, create a `PharmacyOwner` linking a test user to a pharmacy that has stock.
3. `flutter run`, log in as that user — you should land on the dashboard, not `/home`.
4. Edit a quantity below its `low_threshold`; confirm the server logs a `StockTransaction` with `source='MANUAL'` and the correct `changed_by`.
5. Log in as a normal user — you should land on `/home`, and `/api/v1/my-pharmacy/stock/` should return 403.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/owner_dashboard_screen.dart lib/services/pharmacy_service.dart
git commit -m "feat: pharmacy owner dashboard with stock editing"
```

---

## Self-Review Notes

**Spec coverage:** ownership model → Task 1; derived role on login → Task 2; `apply_stock_change` and the POS refactor → Task 3; the four owner endpoints, `IsPharmacyOwner`, 404-not-403 scoping, DELETE-writes-a-transaction, and the low-stock signal firing on manual edits → Task 4; WebSocket JWT auth and the "don't check ownership" rule → Task 5; role state, snapshot round trip, PATCH/DELETE → Task 6; owner service → Task 7; routing on both login paths and logout clearing → Task 8; dashboard, inline row errors, and the 403 fallback to `/home` → Task 9.

**Deliberately not covered:** the spec's note about `StockAlertService._wsBaseUrl` hardcoding `192.168.1.64`. It is flagged as out of scope there and stays out of scope here — Task 6 touches that file but not that line.

**Known-failing test that must stay failing:** `sync/tests/test_stock_sync.py::test_concurrent_requests_do_not_lose_updates` fails because SQLite has no row-level locking. Do not "fix" it by removing the lock. Task 3 Step 7 checks the failure list hasn't grown.

This was corrected during execution: the plan originally claimed three known failures, taken from the test docstrings rather than from a run. `test_missing_api_key_returns_401` and `test_invalid_api_key_returns_401` both pass — the bugs their docstrings describe were fixed in `sync/views.py` and nobody updated the prose. Verified baseline is 17 tests, 1 failure.

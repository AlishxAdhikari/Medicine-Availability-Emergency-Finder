# Pharmacy Owner Role & Stock Editing — Design

**Date:** 2026-07-31
**Status:** Approved for planning

## Problem

Pharmacy stock is the data the whole app is built around — search results, the
in-stock indicator, the low-stock alert feed. Today nothing in the product can
edit it.

- `Pharmacy` has no link to a user. There is no role concept anywhere in the
  system; every registered account is a public app user.
- The only write path to `PharmacyMedicineStock` is `POST /api/v1/stock/sync/`
  (`sync/views.py`), authenticated by a per-pharmacy `POSIntegrationKey`. It
  sets `request.user` to a `Pharmacy` instance rather than a `User`, so DRF's
  ordinary permission machinery cannot be reused against it.
- `PharmacyViewSet` is a `ReadOnlyModelViewSet` with `AllowAny`, and
  `/pharmacies/<id>/stock/` inherits that. Stock is world-readable and
  writable by nobody.
- `LoginIdentifierView` returns a JWT plus `UserSerializer`
  (id/username/email/first/last) with no role, and `login_screen.dart` always
  navigates to `/home`.

A pharmacy owner needs to correct their own stock without a POS integration
and without a Django admin login. Users must keep read-only access.

## Scope

**In:** ownership model, role-aware login, owner-only stock write API, owner
dashboard UI in Flutter, and authentication on the stock WebSocket.

**Out:** broadening live sync so every stock change is pushed (currently only
threshold crossings are). That is the next spec and depends on decisions made
here. Owner self-service pharmacy claiming and any owner-verification flow are
also out — linking is an admin action.

## Decisions

| Question | Decision |
|---|---|
| How owners get accounts | Owner registers through the normal form; staff link the user to a `Pharmacy` in Django admin. |
| Login handling | One login form. The login response carries a role; the client routes on it. |
| Editable fields | Quantity, price, and adding/removing stock rows. Not `low_threshold`. |
| Audit trail | Every edit writes a `StockTransaction` with `source='MANUAL'`. |
| Quantity write shape | Absolute value; the server derives the delta. |

Price is included because add/remove forces it: `PharmacyMedicineStock.price`
is a non-null `DecimalField` with no default, so creating a row requires a
value, and silently defaulting to `0.00` would publish a wrong price through
`PharmacyMedicineStockSerializer`, which does expose the field.

## Ownership model

Add to `pharmacy/models.py`:

```python
class PharmacyOwner(models.Model):
    user = models.OneToOneField(AUTH_USER_MODEL, on_delete=models.CASCADE,
                                related_name='pharmacy_owner')
    pharmacy = models.ForeignKey(Pharmacy, on_delete=models.CASCADE,
                                 related_name='owners')
```

Role is **derived** — `hasattr(user, 'pharmacy_owner')` — not stored. A
separate `role` field would be a second source of truth that can disagree with
the link; this cannot. `OneToOneField` on `user` means a user owns at most one
pharmacy. `ForeignKey` on `pharmacy` allows several owner accounts per shop.

Registered in `pharmacy/admin.py` with an autocomplete on both fields, since
admin linking is the account-provisioning path.

`StockTransaction` gains `changed_by`, a nullable FK to the user model.
`source='MANUAL'` carries almost no information without knowing who made the
change, and POS-sourced rows leave it null.

## API

Four endpoints under `/api/v1/my-pharmacy/`. The pharmacy is resolved from the
token, never from the URL — the same approach `MedicalProfileView` uses, which
leaves no id for a caller to tamper with.

| Method | Path | Body | Purpose |
|---|---|---|---|
| GET | `/my-pharmacy/stock/` | — | The owner's own stock list |
| POST | `/my-pharmacy/stock/` | `medicine`, `quantity`, `price` | Add a medicine |
| PATCH | `/my-pharmacy/stock/<id>/` | `quantity` and/or `price` | Edit a row |
| DELETE | `/my-pharmacy/stock/<id>/` | — | Remove a row |

Removing a row means "this pharmacy no longer carries this medicine", which is
distinct from a quantity of zero. DELETE therefore writes a `StockTransaction`
bringing the quantity to zero *before* deleting the row, so a removal with
stock still on the books does not vanish from the audit log. The transaction
survives the deletion — it holds its own FKs to pharmacy and medicine.

An `IsPharmacyOwner` permission class gates all four. The queryset is
re-scoped to `request.user.pharmacy_owner.pharmacy` on every request, so a
stock id belonging to another pharmacy 404s rather than 403s — a 403 would
confirm the row exists.

`UserSerializer` gains two derived read-only fields so login can route:

- `role`: `'pharmacy_owner'` or `'user'`
- `pharmacy`: `{id, name}`, or null for a normal user

### Stock write path

Every quantity change — owner or POS — funnels through one function in
`pharmacy/services.py`:

```
apply_stock_change(pharmacy, medicine, *, absolute=None, delta=None,
                   source, transaction_type, user=None)
```

Exactly one of `absolute` or `delta` is given: the owner endpoints pass
`absolute` (what the shelf holds), the POS sync passes `delta` (what moved).
Both forms are resolved to a final quantity *inside* the lock, so neither
caller computes anything from a value it read earlier.

It takes `select_for_update()` on the row inside a transaction, resolves the
target quantity, clamps it at zero, saves the row, and writes a
`StockTransaction` recording the delta that was *requested* — not the clamped
one. This preserves the existing POS behavior in `sync/views.py`, where a
dispense that would drive stock negative is clamped but logged at its true
size, and the response carries a `note` saying so.

`transaction_type` is `'ADJUSTED'` for owner edits; the POS sync keeps passing
whatever its payload specifies (`DISPENSED` / `RESTOCKED` / `ADJUSTED`).

Routing owner edits through `StockTransaction` is what makes the existing
low-stock alert fire on them for free: `sync/signals.py` hooks `post_save` on
`StockTransaction`, not on the stock row. An owner editing their count down to
zero pushes an alert with no extra wiring.

`sync/views.py` is refactored to call the same function so there is one place
where stock quantity changes, rather than two that must stay in step.

### Known limitation: lost update on absolute writes

An owner reads 50, the POS dispenses 3 (row → 47), the owner saves 50. The row
lands at 50 and the audit log records a `+3` adjustment that did not physically
happen.

Row locking does not remove this — it is inherent to absolute entry. It is the
right trade here: a person doing a stock take is the authority on the shelf
count, and forcing deltas would make correcting a miscount awkward. Recorded so
it is a known behavior rather than a surprise. If it becomes a problem, the fix
is optimistic concurrency (send the quantity the owner saw; reject on
mismatch), not a change of write shape.

## WebSocket authentication

`StockConsumer.connect()` (`sync/consumers.py`) currently accepts every
connection and joins whatever `pharmacy_id` is in the URL.

This is **not** a confidentiality leak today. `pharmacy_search_screen.dart`
opens this socket as a normal user to watch the top search result, and the
payload (medicine name, quantity, low/critical) is data that
`GET /api/v1/pharmacies/<id>/stock/` already serves to anyone under `AllowAny`.
The problems are that connections are unauthenticated and unattributable, so
anonymous clients can open unbounded sockets against arbitrary group ids — and
that this becomes a real confidentiality question as soon as live sync
broadens.

Fix, in this pass:

1. A Channels middleware reads a JWT from the connection query string,
   resolves the user, and puts it on the scope.
2. `StockConsumer.connect()` closes with code `4401` when there is no valid
   user. It does **not** check ownership — watching another pharmacy's public
   alert feed is exactly what the user-facing search screen does.
3. `StockAlertService.connect()` attaches the access token, and on a `4401`
   close refreshes the token via `ApiClient` and reconnects once before giving
   up.

**Rule for the next spec:** the existing `pharmacy_<id>` group stays limited to
data the public REST surface already exposes. Anything owner-only —
transaction history, prices, exact counts beyond the threshold signal — goes to
a separate `pharmacy_<id>_owner` group that does check ownership. That keeps
the socket from ever being a wider channel than the equivalent REST endpoint.

A JWT in a query string can appear in server access logs. Acceptable here
because tokens are short-lived and refreshable, and browsers cannot set custom
headers on a WebSocket handshake. Noted so the choice is deliberate.

## Flutter

**State** — `state.dart` carries the role and the owned pharmacy's id and name.
Logout clears them along with the rest of the session.

**Login routing** — `login_screen.dart` reads `role` from the login response
and routes to `/owner` or `/home`.

The biometric path needs the same treatment and is easy to miss:
`BiometricService` restores a saved profile snapshot, so unless the role is
written into that snapshot and read back, a fingerprint login drops an owner on
the user home screen. Both entry points must route identically.

**Signup** — `create_account_screen.dart` is unchanged. Owners register
normally and are linked by an admin afterwards.

**New files**

- `lib/screens/owner_dashboard_screen.dart` — pharmacy header, stock list,
  inline quantity edit, add and remove.
- `lib/services/owner_stock_service.dart` — wraps the four endpoints, following
  the existing service pattern.

The add flow's medicine picker reuses `GET /medicines/?search=` through the
existing `pharmacy_service.dart`.

**Navigation** — the owner dashboard is a route alongside `/home`, not a
replacement. An owner is also a person who may need the emergency features, so
the normal tabs stay reachable.

## Error handling

- Owner endpoints return DRF validation errors; the dashboard surfaces them
  inline on the edited row rather than as a screen-level error, so one bad
  field does not discard the rest of the list.
- A failed stock write leaves the previous value visible and shows a retry.
- WebSocket disconnects remain non-fatal, matching current behavior: the alert
  stream ending is normal, not an error state.
- A user whose owner link is removed while logged in gets 403 from the owner
  endpoints; the client treats that as "no longer an owner" and returns to
  `/home` rather than showing an error loop.

## Testing

**Backend**

- A non-owner user gets 403 from every `/my-pharmacy/` endpoint.
- An owner requesting a stock id from another pharmacy gets 404.
- An absolute quantity write produces the correct delta in `StockTransaction`.
- A manual edit writes `source='MANUAL'`, `transaction_type='ADJUSTED'`, and
  `changed_by`.
- A manual edit crossing `low_threshold` fires the existing low-stock alert.
- Add and remove behave correctly, including adding a medicine the pharmacy
  already stocks (should fail on the `unique_together`).
- The refactored POS sync path still passes the existing `sync` test suite.

**Flutter**

- Login routes an owner to `/owner` and a normal user to `/home`.
- The biometric path routes identically.
- `owner_stock_service` against a fake client, following
  `test/pharmacy_service_test.dart`.

## Notes

`StockAlertService._wsBaseUrl` hardcodes `192.168.1.64` for Android. It is
pre-existing and out of scope, but this work touches that file, so it is worth
resolving alongside rather than stepping around silently.

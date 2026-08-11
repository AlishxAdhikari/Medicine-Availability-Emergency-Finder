# MedAlert Backend

The Django REST Framework API that powers the MedAlert Nepal Flutter app: authentication, digital medical IDs, pharmacy/medicine data, emergency services (blood banks, ambulances), and real-time pharmacy stock synchronization over WebSocket.

> Part of the **MedAlert Nepal** minor project. See the [project root README](../README.md) for the overall system overview, architecture, and frontend setup.

## Stack

- **Framework:** Django 6 + Django REST Framework
- **Real-time:** Django Channels 4 + Daphne (ASGI) for WebSocket stock alerts
- **Auth:** `djangorestframework-simplejwt` (JWT access/refresh tokens); a custom `X-POS-API-Key` scheme for POS terminals, and JWT-over-query-string for WebSocket handshakes
- **Filtering:** `django-filter`
- **API docs:** `drf-spectacular` (OpenAPI 3 schema + Swagger UI)
- **CORS:** `django-cors-headers`
- **Database:** SQLite by default for local development; configurable via `DATABASE_URL` (`dj-database-url`) for PostgreSQL in production
- **Test data:** `Faker`-driven management command

## Project Structure

```
backend/
├── manage.py
├── requirements.txt
├── medalert_api/                # Django project package
│   ├── settings.py              # Installed apps, JWT config, CORS, DRF, spectacular & channel layer
│   ├── urls.py                  # Root URLconf — mounts each app under /api/v1/
│   ├── wsgi.py
│   └── asgi.py                  # ProtocolTypeRouter: HTTP → Django, WebSocket → sync consumers
│
├── core/                        # Auth, users, digital medical ID
│   ├── models.py                # MedicalProfile (1:1 with User)
│   ├── serializers.py           # Register / login / medical profile / public share serializers
│   ├── views.py                 # RegisterView, LoginIdentifierView, MedicalProfileView, SharedProfileView
│   ├── urls.py
│   └── admin.py
│
├── pharmacy/                    # Pharmacies, medicines, stock
│   ├── models.py                # Pharmacy, Medicine, PharmacyMedicineStock, PharmacyOwner
│   ├── serializers.py
│   ├── views.py                 # MedicineViewSet, PharmacyViewSet (+ /stock/ action)
│   ├── owner_views.py           # OwnerStockViewSet — the owner-only stock write API
│   ├── permissions.py           # IsPharmacyOwner
│   ├── filters.py               # Search & filter definitions
│   ├── services.py              # Haversine distance, proximity sorting, apply_stock_change()
│   ├── management/commands/
│   │   └── seed_pharmacies.py   # Faker-based sample data generator
│   ├── urls.py
│   └── admin.py
│
├── emergency/                   # Blood banks & ambulance providers
│   ├── models.py                # BloodBank, BloodStock, AmbulanceProvider
│   ├── serializers.py
│   ├── views.py                 # BloodBankViewSet, AmbulanceViewSet
│   ├── filters.py
│   ├── urls.py
│   └── admin.py
│
└── sync/                        # Real-time pharmacy stock sync & WebSocket push
    ├── models.py                # POSIntegrationKey, StockTransaction (append-only audit log)
    ├── serializers.py           # StockSyncSerializer + medicine lookup
    ├── authentication.py        # POSKeyAuthentication (X-POS-API-Key header)
    ├── views.py                 # StockSyncView — POS stock ingestion endpoint
    ├── signals.py               # post_save → on_commit → low-stock broadcast
    ├── apps.py                  # ready() imports signals so the receiver registers
    ├── consumers.py             # StockConsumer (Channels WebSocket)
    ├── middleware.py            # JWTAuthMiddleware for WebSocket handshakes
    ├── routing.py               # WebSocket URL routing
    ├── urls.py
    ├── management/commands/
    │   └── simulate_pos.py      # Fake POS terminal for exercising the pipeline
    └── tests/                   # Consumer, signal & ingestion test suites
```

## Setup

```bash
cd backend
python -m venv venv
source venv/bin/activate        # macOS/Linux
# venv\Scripts\activate         # Windows

pip install -r requirements.txt
cp .env.example .env            # then fill in your own values
python manage.py migrate
python manage.py createsuperuser   # optional, for /admin/
python manage.py seed_pharmacies   # optional, populates sample pharmacies/medicines/stock
python manage.py seed_emergency    # optional, populates sample ambulances/blood banks
python manage.py runserver
```

For emulator and desktop work the defaults are enough: `ALLOWED_HOSTS` covers `127.0.0.1`, `localhost`, and `10.0.2.2` (the Android emulator's alias for the host machine).

### Running against physical phones

Testing on real devices needs two extra steps, and skipping either produces the same symptom — the app behaves as though the server is down.

1. **Bind to all interfaces.** `python manage.py runserver` listens on `127.0.0.1` only, which no other device can reach:

   ```bash
   python manage.py runserver 0.0.0.0:8000
   ```

2. **Add your LAN IP to `ALLOWED_HOSTS`** in `.env`. A phone hitting `http://192.168.1.64:8000` sends `Host: 192.168.1.64:8000`; any host not listed is rejected with **400 DisallowedHost**. Find the IP with `ipconfig` (Windows) or `ifconfig` / `ip addr` (macOS, Linux).

Also allow inbound TCP 8000 through the firewall on the private network profile — on Windows the first run usually raises a prompt, and dismissing it silently blocks every phone.

Point the app at the same address either at build time (`flutter build apk --dart-define=MEDALERT_HOST=192.168.1.64:8000`) or at runtime via the app's **Server settings** screen, reachable from the login screen. Its "Test connection" button reports which of these steps is wrong.

Note that this address changes whenever the router assigns a different lease, so re-check it before any demo on an unfamiliar network.

## Environment Variables

Defined in `backend/.env.example` and read via `python-decouple` / `dj-database-url`:

```
SECRET_KEY=your_secure_key_here
DEBUG=True
ALLOWED_HOSTS=            # Comma-separated; must include your LAN IP for device testing
CORS_ALLOWED_ORIGINS=     # Comma-separated allowed origins, e.g. http://localhost:3000 (only used when DEBUG=False)
DATABASE_NAME=medalert_api
DATABASE_USER=postgres
DATABASE_PASSWORD=your_db_password
DATABASE_HOST=localhost
DATABASE_PORT=5432
```

While `DEBUG=True`, CORS is wide open (`CORS_ALLOW_ALL_ORIGINS = True`) to simplify local development against the Flutter app on any platform. Set `DEBUG=False` and populate `CORS_ALLOWED_ORIGINS` for anything resembling a production deployment.

## Apps & Responsibilities

| App | Responsibility |
|---|---|
| `core` | User authentication (register, login by username/email/phone, JWT refresh) and the digital Medical ID (`MedicalProfile`) |
| `pharmacy` | Pharmacy directory, medicine catalog, per-pharmacy stock levels, search & proximity sorting |
| `emergency` | Blood bank directory with per-blood-group stock levels, ambulance provider directory |
| `sync` | Real-time pharmacy stock synchronization: POS ingestion endpoint, append-only `StockTransaction` audit log, and WebSocket push of low-stock alerts. **Implemented and covered by tests** — see [Real-Time Stock Sync](#real-time-stock-sync) |

## API Reference

Base path: `/api/v1/`. Interactive docs: `/api/v1/docs/` (Swagger UI), raw schema at `/api/v1/schema/`.

### Authentication (`core`)

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/auth/register/` | Create a new user (`username`, `email`, `password`, optional `phone`) |
| `POST` | `/auth/login/` | Standard SimpleJWT login by username + password |
| `POST` | `/auth/login-identifier/` | Login by `identifier` (username, email, **or** phone number) + password |
| `POST` | `/auth/refresh/` | Exchange a refresh token for a new access token (refresh token rotation is enabled) |
| `GET`/`PUT` | `/auth/medical-id/` | Get or update the authenticated user's own medical profile *(auth required)* |
| `GET` | `/auth/medical-id/share/<uuid:share_token>/` | Public, read-only, identity-stripped view of a medical profile for first responders *(no auth required)* |

### Pharmacies & Medicines (`pharmacy`)

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/medicines/` | List medicines. Query params: `search`, `category`, `dosage_form`, `is_essential`, `requires_prescription` |
| `GET` | `/pharmacies/` | List pharmacies. Query params: `search`, `district`, `is_24_hour`, `is_verified`, `lat`, `lng`, `radius_km` (proximity sort/filter when `lat`/`lng` given) |
| `GET` | `/pharmacies/<id>/stock/` | Full medicine stock list for one pharmacy |

### Owner Stock Management (`pharmacy`)

Writes go through `apply_stock_change()` rather than plain field assignment, so every change produces a `StockTransaction` row and triggers the low-stock alert. *(Auth required; caller must have a `PharmacyOwner` link, created by staff in Django admin.)*

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/my-pharmacy/stock/` | The signed-in owner's own stock rows |
| `POST` | `/my-pharmacy/stock/` | Add a medicine the pharmacy doesn't stock yet |
| `PATCH` | `/my-pharmacy/stock/<id>/` | Update `quantity`, `price` and/or `low_threshold` |
| `DELETE` | `/my-pharmacy/stock/<id>/` | Remove a stock row |

### Emergency Services (`emergency`)

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/blood-banks/` | List blood banks. Query params: `district`, `blood_group`, `lat`, `lng`, `radius_km` |
| `GET` | `/blood-banks/districts/` | Distinct districts that have blood bank rows, for the app's filter chips |
| `GET` | `/ambulances/` | List ambulance providers. Query params: `district`, `has_icu`, `has_oxygen`, `is_24_hour`, `service_type` |
| `GET` | `/ambulances/districts/` | Distinct districts that have ambulance rows |

### Real-Time Stock Sync (`sync`)

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/stock/sync/` | POS stock ingestion. Authenticated with an `X-POS-API-Key` header, **not** JWT. Body: `medicine_barcode_or_name`, `quantity_delta`, `transaction_type` (`DISPENSED`/`RESTOCKED`/`ADJUSTED`), `timestamp` |
| `WS` | `/ws/stock/<pharmacy_id>/` | Live low-stock alerts for one pharmacy. Auth via `?token=<access token>` on the handshake |

## Authentication Flow

1. Client calls `POST /auth/register/` or `POST /auth/login/` (or `/auth/login-identifier/`) and receives a JWT **access** token (30-minute lifetime) and **refresh** token (7-day lifetime, rotates on use).
2. The Flutter `ApiClient` stores both tokens in `flutter_secure_storage` and attaches the access token as `Authorization: Bearer <token>` on authenticated requests.
3. On a `401` response, `ApiClient` transparently calls `/auth/refresh/`, stores the new token pair, and retries the original request once before giving up.

## Sample Data

`python manage.py seed_pharmacies` uses `Faker` to generate realistic pharmacies, medicines, and stock entries clustered around six districts (Kathmandu, Lalitpur, Bhaktapur, Pokhara, Chitwan, Biratnagar) with real-looking coordinates, so proximity search can be exercised locally without a production dataset.

## Notes on Proximity Search

Distance calculations (`pharmacy/services.py`) use a plain-Python haversine formula applied after the queryset is fetched, since the development database is SQLite and has no PostGIS extension. This is adequate at the current target scale but should move to a PostGIS `ST_Distance` query if the dataset grows substantially — see the project report for the relevant non-functional requirement.

## Real-Time Stock Sync

The `sync` app is built and working end to end, from POS ingestion through to a live push into the Flutter search screen. The pipeline:

1. A pharmacy's POS terminal `POST`s a stock movement to `/api/v1/stock/sync/`, authenticating with its `X-POS-API-Key` header. `POSKeyAuthentication` resolves the key to a `Pharmacy` and sets it as `request.user` — there is no Django user behind a POS request.
2. `apply_stock_change()` (in `pharmacy/services.py`) applies the delta inside a row lock and writes an append-only `StockTransaction` audit row. The same function backs the owner dashboard's manual edits, so both paths produce identical audit trails.
3. A `post_save` receiver on `StockTransaction` defers to `transaction.on_commit()`, then re-reads the committed stock row. If the quantity is at or below `low_threshold`, it broadcasts a `stock_alert` to the `pharmacy_<id>` channel group. Deferring matters: broadcasting from inside the atomic block would announce quantities that a later rollback erases, and there is no un-send.
4. `StockConsumer` pushes that JSON to every client watching `ws://<host>/ws/stock/<pharmacy_id>/`. The Flutter client (`lib/services/stock_alert_service.dart`) subscribes to the top search result and updates its stock chips in place.

**WebSocket authentication.** Browsers can't set custom headers on a WebSocket handshake, so `JWTAuthMiddleware` reads the access token from the query string (`?token=…`) rather than an `Authorization` header. An unauthenticated connection is accepted and then closed with code `4401`, which the Dart client uses as its cue to refresh the token and reconnect once. The trade-off — tokens can land in server access logs — is documented in `sync/middleware.py`.

**Running it.** `daphne` is first in `INSTALLED_APPS`, so `python manage.py runserver` already serves ASGI and handles WebSocket upgrades; no separate process is needed for local development.

**Channel layer.** `CHANNEL_LAYERS` currently uses `InMemoryChannelLayer`, which is correct for a single-process dev server but does not carry messages between workers. The `channels-redis` dependency is installed and the `RedisChannelLayer` config is present but commented out in `settings.py` — swapping it in is the one remaining step for a multi-worker deployment.

**Exercising it without a POS.** `python manage.py simulate_pos` posts realistic dispensing/restocking events to the real endpoint at a configurable interval, weighted so it actually crosses `low_threshold` and triggers alerts. A `POSIntegrationKey` must exist for the target pharmacy (create one in Django admin).

## Testing

```bash
python manage.py test          # 84 tests
```

The `sync` suite covers the consumer (group delivery, cross-pharmacy isolation, and rejection of absent/garbage/expired/deleted-user/deactivated-user tokens), the signal receiver (threshold boundaries, payload shape, rollback safety), and the ingestion endpoint (auth failures, unknown medicines, concurrency).

**A note on `test_concurrent_requests_do_not_lose_updates`.** `apply_stock_change()` guards its read-modify-write with `select_for_update()`, which is a documented no-op on SQLite (Django's backend sets `has_select_for_update = False`). That test used to fail for exactly this reason. It passes now because `OPTIONS['transaction_mode'] = 'IMMEDIATE'` in `settings.py` makes every atomic block take SQLite's write lock up front, serialising the writers. **Do not remove `select_for_update()`** — it is what provides the same guarantee on PostgreSQL, which is the specified production database. The test is also a `TransactionTestCase` against a file-backed test database on purpose; the shared-cache in-memory default would fail it for reasons unrelated to the application.

## Roadmap

- [x] Real-time pharmacy stock synchronization via Django Channels (`sync/` app) — **done**
- [ ] Swap the in-memory channel layer for Redis (`channels-redis`) so alerts survive multiple workers
- [ ] PostgreSQL + PostGIS for production and large-scale proximity queries
- [ ] Push notifications for emergency/stock alerts
- [ ] Real-time ambulance dispatch status — availability is currently approximated by the `is_24_hour` boolean, not a live status field (see the placeholder note in `lib/services/emergency_service.dart`)
- [ ] Barcode lookup for `medicine_barcode_or_name`, which currently matches on name only
- [ ] Dedupe strategy for retried POS events (today two identical posts apply twice, by design and under test)
- [ ] Rate limiting & production-hardened CORS/security settings
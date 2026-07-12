# MedAlert Backend

The Django REST Framework API that powers the MedAlert Nepal Flutter app: authentication, digital medical IDs, pharmacy/medicine data, and emergency services (blood banks, ambulances).

> Part of the **MedAlert Nepal** minor project. See the [project root README](../README.md) for the overall system overview, architecture, and frontend setup.

## Stack

- **Framework:** Django 6 + Django REST Framework
- **Auth:** `djangorestframework-simplejwt` (JWT access/refresh tokens)
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
│   ├── settings.py              # Installed apps, JWT config, CORS, DRF & spectacular settings
│   ├── urls.py                  # Root URLconf — mounts each app under /api/v1/
│   ├── wsgi.py
│   └── asgi.py
│
├── core/                        # Auth, users, digital medical ID
│   ├── models.py                # MedicalProfile (1:1 with User)
│   ├── serializers.py           # Register / login / medical profile / public share serializers
│   ├── views.py                 # RegisterView, LoginIdentifierView, MedicalProfileView, SharedProfileView
│   ├── urls.py
│   └── admin.py
│
├── pharmacy/                    # Pharmacies, medicines, stock
│   ├── models.py                # Pharmacy, Medicine, PharmacyMedicineStock
│   ├── serializers.py
│   ├── views.py                 # MedicineViewSet, PharmacyViewSet (+ /stock/ action)
│   ├── filters.py               # Search & filter definitions
│   ├── services.py              # Haversine distance & proximity sorting
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
└── sync/                        # Reserved for real-time pharmacy stock sync (planned)
    ├── models.py                # Not yet implemented
    ├── views.py                 # Not yet implemented
    └── admin.py
```

## Setup

```bash
cd backend
python -m venv venv
source venv/bin/activate        # macOS/Linux
# venv\Scripts\activate         # Windows

pip install -r requirements.txt
cp ../.env.example .env         # then fill in your own values
python manage.py migrate
python manage.py createsuperuser   # optional, for /admin/
python manage.py seed_pharmacies   # optional, populates sample pharmacies/medicines/stock
python manage.py runserver
```

The server listens on `http://127.0.0.1:8000/` by default. `ALLOWED_HOSTS` in `settings.py` already includes `127.0.0.1`, `localhost`, and `10.0.2.2` (the Android emulator's alias for the host machine), so no extra config is needed to talk to the Flutter app out of the box.

## Environment Variables

Defined in `.env.example` at the project root and read via `python-decouple` / `dj-database-url`:

```
CORS_ALLOWED_ORIGINS=      # Comma-separated allowed origins, e.g. http://localhost:3000 (only used when DEBUG=False)
SECRET_KEY=your_secure_key_here
DATABASE_NAME=medalert_api
DATABASE_USER=postgres
DATABASE_PASSWORD=your_db_password
DATABASE_HOST=localhost
DATABASE_PORT=5432
DEBUG=True
```

While `DEBUG=True`, CORS is wide open (`CORS_ALLOW_ALL_ORIGINS = True`) to simplify local development against the Flutter app on any platform. Set `DEBUG=False` and populate `CORS_ALLOWED_ORIGINS` for anything resembling a production deployment.

## Apps & Responsibilities

| App | Responsibility |
|---|---|
| `core` | User authentication (register, login by username/email/phone, JWT refresh) and the digital Medical ID (`MedicalProfile`) |
| `pharmacy` | Pharmacy directory, medicine catalog, per-pharmacy stock levels, search & proximity sorting |
| `emergency` | Blood bank directory with per-blood-group stock levels, ambulance provider directory |
| `sync` | Scaffolded but not yet implemented — intended for real-time pharmacy stock synchronization |

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

### Emergency Services (`emergency`)

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/blood-banks/` | List blood banks. Query params: `district`, `blood_group`, `lat`, `lng`, `radius_km` |
| `GET` | `/ambulances/` | List ambulance providers. Query params: `district`, `has_icu`, `has_oxygen`, `is_24_hour`, `service_type` |

## Authentication Flow

1. Client calls `POST /auth/register/` or `POST /auth/login/` (or `/auth/login-identifier/`) and receives a JWT **access** token (30-minute lifetime) and **refresh** token (7-day lifetime, rotates on use).
2. The Flutter `ApiClient` stores both tokens in `flutter_secure_storage` and attaches the access token as `Authorization: Bearer <token>` on authenticated requests.
3. On a `401` response, `ApiClient` transparently calls `/auth/refresh/`, stores the new token pair, and retries the original request once before giving up.

## Sample Data

`python manage.py seed_pharmacies` uses `Faker` to generate realistic pharmacies, medicines, and stock entries clustered around six districts (Kathmandu, Lalitpur, Bhaktapur, Pokhara, Chitwan, Biratnagar) with real-looking coordinates, so proximity search can be exercised locally without a production dataset.

## Notes on Proximity Search

Distance calculations (`pharmacy/services.py`) use a plain-Python haversine formula applied after the queryset is fetched, since the development database is SQLite and has no PostGIS extension. This is adequate at the current target scale but should move to a PostGIS `ST_Distance` query if the dataset grows substantially — see the project report for the relevant non-functional requirement.

## Roadmap

- [ ] Real-time pharmacy stock synchronization via Django Channels + Redis (`sync/` app)
- [ ] PostgreSQL + PostGIS for production and large-scale proximity queries
- [ ] Push notifications for emergency/stock alerts
- [ ] Rate limiting & production-hardened CORS/security settings
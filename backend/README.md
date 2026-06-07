# MedAlert Backend

This folder contains the Django REST API for MedAlert Nepal.

## Setup

1. Create a virtual environment and install dependencies:

```bash
pip install -r requirements.txt
```

2. Create a PostgreSQL database:

```sql
CREATE DATABASE medalert;
```

3. Run migrations and create an admin user:

```bash
python manage.py migrate
python manage.py seed_data
python manage.py createsuperuser
python manage.py runserver
```

## API Entry Points

- `POST /api/v1/auth/register/` creates a user.
- `POST /api/v1/auth/token/` returns JWT access and refresh tokens.
- `GET /api/v1/pharmacies/` lists pharmacies and supports `search`, `district`, `lat`, `lon`, and `radius`.
- `GET /api/v1/pharmacies/stocks/` lists medicine stock by `pharmacy`, `medicine`, and `availability`.
- `GET /api/v1/medicines/` lists medicines and supports `search`, `category`, and essential/prescription filters.
- `GET /api/v1/medicines/categories/` lists medicine categories.
- `GET /api/v1/blood-banks/` lists blood banks and supports `search`, `district`, `blood_group`, `lat`, `lon`, and `radius`.
- `GET /api/v1/ambulances/` lists ambulance providers and supports `search`, `service_type`, `district`, `has_icu`, and `has_oxygen`.
- `GET|PATCH /api/v1/medical-id/me/` reads or updates the authenticated user's medical profile.

## Admin Entry Points

- Pharmacies: manual stock entry and location management.
- Blood banks: blood group inventory updates.
- Medicines: catalogue and essential medicine flags.
- Ambulances: service type and capability management.

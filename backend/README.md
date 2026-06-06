# MedAlert Backend

This folder contains the Django/GeoDjango backend scaffold for the MedAlert Nepal project.

## Setup

1. Create a virtual environment and install dependencies:

```bash
pip install -r requirements.txt
```

2. Create a PostgreSQL database and enable PostGIS:

```sql
CREATE DATABASE medalert;
\c medalert;
CREATE EXTENSION IF NOT EXISTS postgis;
```

3. Run migrations and create an admin user:

```bash
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

## Admin entry points

- Pharmacies: manual stock entry and location management.
- Blood banks: blood group inventory updates.
- Essential medicines: status updates for partner pharmacies.

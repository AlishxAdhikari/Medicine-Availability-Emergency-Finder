# MedAlert Backend

## Planned Stack

- **Framework:** Django (REST API via Django REST Framework)
- **Database:** PostgreSQL
- **Purpose:** Provides authentication, pharmacy/ambulance/blood-bank data, medical ID storage, and emergency services APIs for the MedAlert Flutter frontend.

## Setup (when ready)

```bash
cd backend
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS/Linux

pip install -r requirements.txt
django-admin startproject medalert_api .
python manage.py startapp core
python manage.py migrate
python manage.py runserver
```

## Planned Apps / Modules

| App | Responsibility |
|-----|----------------|
| `core` | User auth, profiles, medical IDs |
| `pharmacy` | Pharmacy listings, medicine inventory, search |
| `emergency` | Ambulance services, blood banks, SOS triggers |

## Environment Variables

The following will be needed (use a `.env` file):

```
SECRET_KEY=<django-secret-key>
DEBUG=True
DATABASE_URL=postgres://user:password@localhost:5432/medalert_db
ALLOWED_HOSTS=localhost,127.0.0.1
```

---

> **Note:** This directory is a placeholder. The Django project has not been initialized yet.

# MedAlert Nepal 🚑

**MedAlert Nepal** is a mobile-first emergency health resource application built for Nepal. It helps people quickly find nearby pharmacies with medicine in stock, locate blood banks by blood group, reach ambulance providers, and carry a digital medical ID that first responders can access in a crisis — even without the person being conscious or reachable.

The application is a full-stack system: a **Flutter** client (Android, iOS, Web, Windows, macOS, Linux) backed by a **Django REST Framework** API with JWT authentication and WebSocket stock alerts.

> **Minor Project — Department of Computer Engineering**
> Submitted in partial fulfillment of the requirements for the Bachelor's degree in Computer Engineering.
>
> | | |
> |---|---|
> | **Institution** | Himalaya College of Engineering (Tribhuvan University) |
> | **Project title** | MedAlert Nepal — Medicine Availability & Emergency Finder |
> | **Submitted by** | *[Alish Adhikari / HCE080BCT006]* ,*[Anurodh Parajuli / HCE080BCT010]* ,*[Nischal K.C. / HCE080BCT026]* ,*[Tushar Khatiwada / HCE080BCT046]* |
> | **Supervisor** | *[Er. Narayan Adhikari Chhetri]* |
> | **Academic year** | *[2083]* |

> **Project status:** Core system functional end-to-end. The Flutter UI is wired to a live Django REST API for authentication, pharmacy/medicine search, blood bank and ambulance lookup, the digital medical ID, the pharmacy-owner stock dashboard, and real-time low-stock alerts over WebSocket.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [System Architecture](#system-architecture)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [1. Clone the repository](#1-clone-the-repository)
  - [2. Backend setup (Django API)](#2-backend-setup-django-api)
  - [3. Frontend setup (Flutter app)](#3-frontend-setup-flutter-app)
  - [4. Pointing the app at the backend](#4-pointing-the-app-at-the-backend)
  - [5. Run tests](#5-run-tests)
- [User Guide: How to Use Features](#user-guide-how-to-use-features)
- [API Overview](#api-overview)
- [Roadmap](#roadmap)
- [License](#license)

---

## Features

- 🔐 **Authentication** — Registration and login (by username, email, *or* phone number), JWT access/refresh tokens with automatic silent refresh on the client, and optional **biometric unlock** (fingerprint / face) for returning users on mobile.
- 💊 **Pharmacy & Medicine Search** — Search by medicine name, generic name, brand, district, or search radius; live stock indicators (availability chips, or exact quantities if you prefer), call a pharmacy, or open driving directions.
- 🗺️ **Map View & Location** — Results are sorted by real distance from your current position, with an in-app map of nearby pharmacies, blood banks, and ambulance providers.
- 📡 **Real-Time Stock Alerts** — The app opens a WebSocket to the backend and updates stock chips in place when a pharmacy's POS reports a dispense or restock.
- 🩸 **Blood Bank Lookup** — Blood banks by district and blood group, with live stock levels (adequate / low / critical / unavailable) and proximity sorting.
- 🚑 **Ambulance Directory** — Government, private, and NGO providers, filterable by district, ICU/oxygen availability, and 24-hour service. Availability is labelled honestly as "24-hour service", not as a live dispatch status the backend does not yet have.
- 🆘 **SOS: countdown and contact alerts** — A persistent SOS button on every tab starts a **cancellable countdown** before dialling **102**, and an *Alert my contacts* action texts your emergency contacts with your location.
- 🆔 **Digital Medical ID & Emergency QR Code** — Blood group, height, weight, severe allergies, current medications, address, and emergency contacts, plus an offline-scannable QR code carrying the whole profile so any responder with a phone camera can read it.
- 🏪 **Pharmacy Owner Dashboard** — Verified owners manage their own stock (add, adjust, remove), see sales analytics, and export PDF/Excel reports. Every change is written through the same audited path as POS sync.
- ⚙️ **Server Settings Screen** — Point the app at any backend host at runtime, with a "Test connection" button that names which step is misconfigured.
- 🌗 **Light & Dark Themes** — Full Material 3 theming across the app.
- 📖 **Auto-Generated API Docs** — Interactive Swagger UI and OpenAPI schema via `drf-spectacular`.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart), Material 3 |
| Frontend State Management | Custom `ValueNotifier`-based app state (`lib/state.dart`) |
| Location & Maps | `geolocator`, `flutter_map` + `latlong2` |
| Device Integration | `url_launcher` (dial / SMS / directions), `local_auth` (biometrics) |
| Secure Storage | `flutter_secure_storage` (JWT tokens, server host, preferences) |
| QR & Reports | `qr_flutter`, `share_plus`, `pdf` + `printing`, `excel`, `barcode` |
| Backend Framework | Django 6 + Django REST Framework |
| Authentication | `djangorestframework-simplejwt` (JWT access/refresh) + `X-POS-API-Key` for POS terminals |
| Database | PostgreSQL (no SQLite fallback — see `backend/README.md`) |
| Real-time Layer | Django Channels (ASGI/Daphne) + WebSocket push for live stock alerts |
| Platforms | Android, iOS, Web, Windows, macOS, Linux |

---

## System Architecture

```
┌─────────────────────┐        JWT REST  +  WebSocket alerts        ┌──────────────────────────┐
│   Flutter Client    │ ─────────────────────────────────────────▶│   Django REST API        │
│  (lib/)             │◀───────────────────────────────────────── │  (backend/)              │
│  screens ▸ services │    /api/v1/...   ws://…/ws/stock/<id>/     │  core ▸ pharmacy ▸       │
│  ▸ widgets ▸ state  │                                            │  emergency ▸ sync        │
└──────────┬──────────┘                                            └───────────┬──────────────┘
                                                                               │
                                                                               ▼
                                                                          PostgreSQL
                                                                               ▲
                                                                               │
                                                                    Pharmacy POS terminals
                                                                    (X-POS-API-Key ingestion)
```

---

## Project Structure

```
Medicine-Availability-Emergency-Finder/
├── lib/                              # Flutter application
│   ├── main.dart                     # App entry point & route definitions
│   ├── theme.dart                    # Light/dark theme definitions
│   ├── state.dart                    # App state & UserProfile model
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── login_screen.dart
│   │   ├── create_account_screen.dart
│   │   ├── home_screen.dart             # App shell, tabs & SOS button
│   │   ├── pharmacy_search_screen.dart  # Pharmacy list & medicine search
│   │   ├── emergency_screen.dart        # Blood banks, ambulances, contact alerts
│   │   ├── medical_id_screen.dart       # Medical ID display & emergency QR generator
│   │   ├── edit_medical_id_screen.dart  # Medical profile editor
│   │   ├── owner_dashboard_screen.dart  # Pharmacy owner stock & sales dashboard
│   │   └── server_settings_screen.dart  # Runtime backend host + connection test
│   ├── widgets/
│   │   ├── emergency_call.dart          # SOS countdown, dialling, contact SMS
│   │   ├── service_map.dart             # Map of nearby services
│   │   ├── location_notice.dart
│   │   ├── medalert_mark.dart           # Logo painter (also renders the launcher icon)
│   │   └── initials_avatar.dart
│   └── services/
│       ├── api_client.dart                  # Shared HTTP client, JWT storage & refresh
│       ├── server_config.dart               # Backend host resolution (--dart-define / runtime)
│       ├── auth_service.dart                # Register / login / logout
│       ├── biometric_service.dart           # Fingerprint / face unlock
│       ├── pharmacy_service.dart            # Pharmacy & medicine search
│       ├── stock_alert_service.dart         # WebSocket low-stock subscription
│       ├── emergency_service.dart           # Blood bank & ambulance lookup
│       ├── medical_profile_service.dart     # Medical ID profile fetch & save
│       ├── location_service.dart            # Permissions & position fixes
│       ├── launcher_service.dart            # tel: / sms: / directions launching
│       ├── display_preferences.dart         # Persisted display settings
│       ├── owner_*.dart                     # Owner stock, customers & sales log
│       └── sales_report_pdf.dart            # PDF sales report generation
│
├── backend/                          # Django REST API — see backend/README.md
│   ├── manage.py
│   ├── requirements.txt
│   ├── medalert_api/                 # Project settings, root URLconf, WSGI/ASGI
│   ├── core/                         # Auth, users, medical ID profiles
│   ├── pharmacy/                     # Pharmacies, medicines, stock, search, owner API
│   ├── emergency/                    # Blood banks, blood stock, ambulances
│   └── sync/                         # POS ingestion, audit log, WebSocket alerts
│
├── test/                             # Flutter widget & unit tests
├── tool/generate_app_icon.dart       # Renders launcher icons from MedAlertMark
├── pubspec.yaml                      # Flutter dependencies
└── README.md                         # This file
```

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (channel: stable, Dart SDK `^3.12.0`)
- Python 3.11+
- PostgreSQL 14+ (the backend has no SQLite fallback)

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/Medicine-Availability-Emergency-Finder.git
cd Medicine-Availability-Emergency-Finder
```

### 2. Backend setup (Django API)

Start the Django backend first. Create an empty PostgreSQL database, then:

```bash
cd backend
python -m venv venv
source venv/bin/activate        # macOS/Linux
# venv\Scripts\activate         # Windows

pip install -r requirements.txt
cp .env.example .env                # then fill in DATABASE_* and SECRET_KEY
python manage.py migrate
python manage.py seed_pharmacies    # sample pharmacies, medicines & stock
python manage.py seed_emergency     # sample blood banks & ambulances

# Bind to 0.0.0.0, not the default 127.0.0.1, or phones on the same wifi
# cannot reach the server. Add your LAN IP to ALLOWED_HOSTS in .env too.
python manage.py runserver 0.0.0.0:8000
```

`DEBUG` defaults to **False**, so keep `DEBUG=True` in your local `.env`; with it off the server refuses to start without a real `SECRET_KEY`. Full details in [`backend/README.md`](backend/README.md).

### 3. Frontend setup (Flutter app)

In a separate terminal, from the project root:

```bash
flutter pub get

# Run on a connected device or browser
flutter run
# Or run on web
flutter run -d chrome
```

### 4. Pointing the app at the backend

The app resolves its backend host in this order:

1. A build-time define — `flutter run --dart-define=MEDALERT_HOST=192.168.1.64:8000`
2. A value saved at runtime in the app's **Server settings** screen (reachable from the login screen), whose *Test connection* button reports exactly which step is misconfigured
3. The built-in default (`127.0.0.1:8000` on desktop/web, `10.0.2.2:8000` on the Android emulator)

### 5. Run tests

```bash
flutter test                    # Flutter widget & unit tests

cd backend
python manage.py test           # Django API, signal & WebSocket consumer tests
```

---

## User Guide: How to Use Features

### 1. Using the Digital Medical ID & Emergency QR Code

1. Navigate to the **Medical ID** tab.
2. Tap the **Edit** (pencil) icon to update personal details, blood group, height, weight, home address, **severe allergies**, current medications, and emergency contacts.
3. Tap **Save Changes** to sync your profile.
4. A **Responder Scan** QR code is generated automatically on the Medical ID screen.
5. Responders can scan it with **any standard camera or QR reader** — even offline — to read your full emergency profile.
6. Tap **Download QR Code** to save or share the image.

### 2. Searching Pharmacies & Medicine Availability

1. Go to the **Pharmacy** tab.
2. Type any medicine or pharmacy name, or adjust the **Search Radius** slider (5 km to 20 km).
3. Cards show **Open Now** / **Closed** and stock indicators, refreshed live when a pharmacy's POS reports a change.
4. Tap **Directions** for the route, **Call** to phone the pharmacy, or open the map view to see everything nearby.

### 3. Emergency SOS

1. The red **SOS** button sits on every tab.
2. A countdown appears before the call is placed — tap **Cancel** to stop it, so an accidental tap never dials.
3. On the **Emergency** tab, **Alert my contacts** texts your saved emergency contacts a message including your current location.
4. The same tab lists blood banks by blood group and ambulance providers by district, ICU/oxygen, and 24-hour service.

### 4. Pharmacy Owner Dashboard

Staff link a user account to a pharmacy in Django admin (`PharmacyOwner`). That user then sees the **owner dashboard**, where they can add, adjust, or remove stock rows, review sales analytics, and export PDF or Excel reports. Edits go through the audited stock path, so they appear to customers immediately and produce the same low-stock alerts as POS traffic.

---

## API Overview

All endpoints are versioned under `/api/v1/`. Interactive docs are available when the backend is running:

- Swagger UI: `http://127.0.0.1:8000/api/v1/docs/`
- OpenAPI schema: `http://127.0.0.1:8000/api/v1/schema/`
- Health check: `http://127.0.0.1:8000/api/v1/health/` (unauthenticated; also verifies the database)

The full endpoint table lives in [`backend/README.md`](backend/README.md#api-reference).

---

## Roadmap

- [x] Real-time pharmacy stock synchronization over WebSocket
- [x] PostgreSQL as the production database
- [x] SOS with a cancellable countdown and emergency-contact SMS
- [ ] Redis channel layer so alerts survive multiple workers
- [ ] PostGIS for database-side proximity queries at larger scale
- [ ] Push notifications for emergency and stock alerts
- [ ] Live ambulance dispatch status (today only 24-hour service is known)
- [ ] Barcode lookup for POS medicine matching
- [ ] Rate limiting and production-hardened deployment settings

---

## License

No license has been specified yet for this project. All rights reserved by the authors.

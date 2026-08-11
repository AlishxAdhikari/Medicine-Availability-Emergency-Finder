# MedAlert Nepal 🚑

**MedAlert Nepal** is a mobile-first emergency health resource application built for Nepal. It helps people quickly find nearby pharmacies with medicine in stock, locate blood banks by blood group, reach ambulance providers, scan prescription photos using AI to search exact medicines, and carry a digital medical ID that first responders can access in a crisis — even without the person being conscious or reachable.

The application is a full-stack system: a **Flutter** client (Android, iOS, Web, Windows, macOS, Linux) backed by a **Django REST Framework** API with JWT authentication and **Google Gemini AI** vision integration.

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

> **Project status:** Core system functional end-to-end. Flutter UI is wired to a live Django REST API for authentication, pharmacy/medicine search, blood bank and ambulance lookup, AI prescription OCR, and digital medical ID.

---

## Table of Contents

- [MedAlert Nepal 🚑](#medalert-nepal-)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Tech Stack](#tech-stack)
  - [System Architecture](#system-architecture)
  - [Project Structure](#project-structure)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [1. Clone the repository](#1-clone-the-repository)
    - [2. Backend setup (Django API)](#2-backend-setup-django-api)
    - [3. Frontend setup (Flutter app)](#3-frontend-setup-flutter-app)
    - [4. Run tests](#4-run-tests)
  - [User Guide: How to Use Features](#user-guide-how-to-use-features)
    - [1. Scanning Prescriptions with AI](#1-scanning-prescriptions-with-ai)
    - [2. Using the Digital Medical ID & Emergency QR Code](#2-using-the-digital-medical-id--emergency-qr-code)
    - [3. Searching Pharmacies & Medicine Availability](#3-searching-pharmacies--medicine-availability)
  - [API Overview](#api-overview)
  - [Roadmap](#roadmap)
  - [Contributing](#contributing)
  - [License](#license)

---

## Features

- 🔐 **Authentication** — Registration and login (by username, email, *or* phone number), JWT access/refresh tokens with automatic silent refresh on the client.
- 📷 **AI Prescription Photo Scanner (Google Gemini)** — Take a photo of any doctor's prescription or upload from gallery. Google Gemini AI vision analyzes the photo, extracts prescribed medicine names, and searches matching pharmacies in your area.
- 💊 **Pharmacy & Medicine Search** — Search pharmacies and medicines by name, generic name, brand, district, or search radius; view live stock indicators (In Stock vs Out of Stock), call pharmacies directly, or get driving directions.
- 🩸 **Blood Bank Lookup** — Find blood banks by district and blood group, with live stock levels (adequate / low / critical / unavailable) and proximity sorting.
- 🚑 **Ambulance Directory** — Government, private, and NGO ambulance providers, filterable by district, ICU/oxygen availability, and 24-hour service.
- 🆔 **Digital Medical ID & Complete QR Code** — Store blood group, height, weight, severe allergies, current medications, address, and emergency contacts. Generates an offline-scannable QR code containing your complete emergency medical profile so first responders can read it instantly with any QR reader.
- 🌗 **Light & Dark Themes** — Full Material 3 theming across the app.
- 📖 **Auto-Generated API Docs** — Interactive Swagger UI and OpenAPI schema via `drf-spectacular`.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart), Material 3 |
| Frontend State Management | Custom `ValueNotifier`-based app state (`lib/state.dart`) |
| AI Vision / OCR | Google Gemini API (`gemini-1.5-flash`) via `http` |
| Image Capture | `image_picker` package |
| Secure Storage | `flutter_secure_storage` (stores JWT tokens & Gemini API key) |
| QR Code Generation | `qr_flutter` & `share_plus` |
| Backend Framework | Django 6 + Django REST Framework |
| Authentication | `djangorestframework-simplejwt` (JWT access/refresh) |
| Database | SQLite (development) — swappable via `DATABASE_URL` for PostgreSQL |
| Real-time Layer | Django Channels (ASGI/Daphne) + WebSocket push for live stock alerts |
| Platforms | Android, iOS, Web, Windows, macOS, Linux |

---

## System Architecture

```
┌─────────────────────┐        JWT REST / Gemini AI Vision         ┌──────────────────────────┐
│   Flutter Client    │ ────────────────────────────────────────▶│   Django REST API        │
│  (lib/)             │◀──────────────────────────────────────── │  (backend/)              │
│  screens ▸ services │        /api/v1/...                        │  core ▸ pharmacy ▸       │
│  ▸ state ▸ theme    │                                           │  emergency ▸ sync        │
└──────────┬──────────┘                                           └───────────┬──────────────┘
           │                                                                  │
           ▼                                                                  ▼
  Google Gemini API                                                  SQLite / PostgreSQL
 (Prescription OCR)
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
│   │   ├── login_screen.dart
│   │   ├── create_account_screen.dart
│   │   ├── home_screen.dart
│   │   ├── pharmacy_search_screen.dart # Pharmacy list, search & prescription scanner
│   │   ├── emergency_screen.dart
│   │   ├── medical_id_screen.dart      # Medical ID display & emergency QR generator
│   │   └── edit_medical_id_screen.dart # Medical profile editor
│   └── services/
│       ├── api_client.dart                 # Shared HTTP client, JWT storage & refresh
│       ├── auth_service.dart               # Register / login / logout
│       ├── pharmacy_service.dart           # Pharmacy & medicine search
│       ├── emergency_service.dart          # Blood bank & ambulance lookup
│       ├── medical_profile_service.dart    # Medical ID profile fetch & save
│       └── gemini_prescription_service.dart # Gemini AI prescription photo OCR
│
├── backend/                          # Django REST API — see backend/README.md
│   ├── manage.py
│   ├── requirements.txt
│   ├── medalert_api/                 # Project settings, root URLconf, WSGI/ASGI
│   ├── core/                         # Auth, users, medical ID profiles
│   ├── pharmacy/                     # Pharmacies, medicines, stock, search
│   └── emergency/                    # Blood banks, blood stock, ambulances
│
├── pubspec.yaml                      # Flutter dependencies
└── README.md                         # This file
```

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (channel: stable, Dart SDK `^3.12.0`)
- Python 3.11+
- Free Google Gemini API Key (obtain from [Google AI Studio](https://aistudio.google.com/))

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/Medicine-Availability-Emergency-Finder.git
cd Medicine-Availability-Emergency-Finder
```

### 2. Backend setup (Django API)

Start the Django backend first:

```bash
cd backend
python -m venv venv
source venv/bin/activate        # macOS/Linux
# venv\Scripts\activate         # Windows

pip install -r requirements.txt
cp .env.example .env
python manage.py migrate
python manage.py seed_pharmacies   # populate sample pharmacies, medicines & stock

# Bind to 0.0.0.0, not the default 127.0.0.1, or phones on the same wifi
# cannot reach the server. Add your LAN IP to ALLOWED_HOSTS in .env too.
python manage.py runserver 0.0.0.0:8000
```

### 3. Frontend setup (Flutter app)

In a separate terminal, from the project root:

```bash
flutter pub get

# Run on a connected device or browser
flutter run
# Or run on web
flutter run -d chrome
```

---

## User Guide: How to Use Features

### 1. Scanning Prescriptions with AI

1. Open the **Pharmacy** tab from the bottom navigation bar.
2. In the top search bar, tap the **Camera icon** (`📷`).
3. If using for the first time, tap **Set Free Gemini API Key** and paste your API key from [Google AI Studio](https://aistudio.google.com/). The key is stored securely on your device.
4. Choose **Take Photo with Camera** or **Choose from Gallery**.
5. The app analyzes the prescription photo using Gemini AI and displays a list of detected medicines with checkboxes.
6. Select the medicines you want to find and tap **Search Pharmacies**. The app populates the search query and displays local pharmacies carrying those medicines!

### 2. Using the Digital Medical ID & Emergency QR Code

1. Navigate to the **Medical ID** tab.
2. Tap the **Edit** (pencil) icon to update your personal details, blood group, height, weight, home address, **severe allergies**, current medications, and emergency contacts.
3. Tap **Save Changes** to sync your profile.
4. On the Medical ID screen, an emergency **Responder Scan** QR code is automatically generated.
5. First responders or hospital staff can scan this QR code using **any standard smartphone camera or QR reader** — even offline. It displays your complete emergency profile (Name, Medical ID, Blood Group, Height/Weight, Severe Allergies, Medications, and Emergency Contacts).
6. Tap **Download QR Code** to save or share the image.

### 3. Searching Pharmacies & Medicine Availability

1. Go to the **Pharmacy** tab.
2. Use the search bar to type any medicine or pharmacy name, or adjust the **Search Radius** slider (5 km to 20 km).
3. Pharmacy cards display whether the pharmacy is **Open Now** or **Closed**, along with real-time stock indicators for medicines.
4. Tap **Directions** to view the location or **Call** to phone the pharmacy directly.

---

## API Overview

All endpoints are versioned under `/api/v1/`. Interactive docs are available when the backend is running:

- Swagger UI: `http://127.0.0.1:8000/api/v1/docs/`
- OpenAPI schema: `http://127.0.0.1:8000/api/v1/schema/`

---

## License

No license has been specified yet for this project. All rights reserved by the authors.
# MedAlert Nepal

MedAlert Nepal is a medicine availability and emergency resource finder for Nepal. The project has a Django REST backend and a Flutter mobile app with tabs for medicines, blood banks, ambulance providers, emergency contacts, and a digital medical ID.

## Architecture

- `backend/` contains the Django API, DRF serializers/viewsets, JWT auth, filtering, seed data, and admin setup.
- `medalert_nepal/lib/models/` contains typed Flutter data models that match backend JSON.
- `medalert_nepal/lib/services/` contains Dio-based API clients.
- `medalert_nepal/lib/providers/` contains Riverpod state providers.
- `medalert_nepal/lib/screens/` contains the five-tab app UI.
- `medalert_nepal/lib/widgets/` contains reusable cards, search fields, badges, filters, and loading/empty states.

## Backend Setup

```bash
cd backend
pip install -r requirements.txt
copy .env.example .env
python manage.py migrate
python manage.py seed_data
python manage.py runserver
```

## Flutter Setup

```bash
cd medalert_nepal
flutter pub get
flutter analyze
flutter test
flutter run
```

The default API URL is `http://127.0.0.1:8000/api/v1` for desktop/web/iOS and `http://10.0.2.2:8000/api/v1` for Android emulators.

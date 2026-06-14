# MedAlert Nepal - User Guide

This guide explains how to set up and run the MedAlert Nepal application on an emulator for development and testing.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Backend Setup](#backend-setup)
- [Flutter App Setup](#flutter-app-setup)
- [Running on Android Emulator](#running-on-android-emulator)
- [Running on iOS Simulator](#running-on-ios-simulator)
- [App Usage](#app-usage)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Software

1. **Docker Desktop** - For running the PostgreSQL database and backend
   - Download from [docker.com](https://www.docker.com/products/docker-desktop)
   
2. **Flutter SDK** - For running the mobile app
   - Download from [flutter.dev](https://flutter.dev/docs/get-started/install)
   - Verify installation: `flutter doctor`

3. **Android Studio** - For Android emulator
   - Download from [developer.android.com](https://developer.android.com/studio)
   - Includes Android SDK and AVD (Android Virtual Device) Manager

4. **Xcode** - For iOS simulator (macOS only)
   - Install from Mac App Store
   - Requires Apple Developer Account for full features

### System Requirements

- **Windows/macOS/Linux**: 8GB RAM minimum (16GB recommended)
- **Disk Space**: 10GB free space
- **Network**: Internet connection for API calls and package downloads

## Backend Setup

The backend runs Django REST API with PostgreSQL database.

### Option 1: Using Docker (Recommended)

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Copy the environment file:
   ```bash
   copy .env.example .env
   ```

3. Start the backend with Docker Compose:
   ```bash
   docker-compose up --build
   ```

   This will:
   - Start PostgreSQL database on port 5432
   - Start Django backend on port 8000
   - Run database migrations automatically
   - Seed initial data

4. Verify the backend is running:
   - Open http://localhost:8000/api/v1/ in your browser
   - You should see the API root endpoint

### Option 2: Manual Setup

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Create a virtual environment:
   ```bash
   python -m venv .venv
   .venv\Scripts\activate  # Windows
   source .venv/bin/activate  # macOS/Linux
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Copy and configure environment file:
   ```bash
   copy .env.example .env
   ```
   Edit `.env` and set your PostgreSQL credentials.

5. Create PostgreSQL database:
   ```sql
   CREATE DATABASE medalert;
   ```

6. Run migrations and seed data:
   ```bash
   python manage.py migrate
   python manage.py seed_data
   python manage.py createsuperuser
   ```

7. Start the backend server:
   ```bash
   python manage.py runserver
   ```

## Flutter App Setup

1. Navigate to the Flutter app directory:
   ```bash
   cd medalert_nepal
   ```

2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Verify Flutter setup:
   ```bash
   flutter doctor
   ```
   Ensure all required tools are installed (Android SDK, Xcode, etc.)

4. Check available devices/emulators:
   ```bash
   flutter devices
   ```

## Running on Android Emulator

### Setting up Android Emulator

1. Open Android Studio
2. Go to **Tools > Device Manager**
3. Click **Create Device**
4. Select a device (e.g., Pixel 6)
5. Select a system image (API 33+ recommended)
6. Finish the setup

### Starting the Emulator

1. Start the emulator:
   ```bash
   # Option 1: Via command line
   flutter emulators
   flutter emulators --launch <emulator_id>
   
   # Option 2: Via Android Studio
   # Open Device Manager and click the Play button
   ```

2. Verify the emulator is running:
   ```bash
   flutter devices
   ```

### Running the App

1. Ensure the backend is running (see [Backend Setup](#backend-setup))

2. Run the Flutter app on the emulator:
   ```bash
   flutter run
   ```

3. The app will:
   - Build and install on the emulator
   - Connect to the backend at `http://10.0.2.2:8000/api/v1` (Android emulator's localhost alias)
   - Open the app automatically

### Hot Reload

While the app is running, you can use hot reload for faster development:
- Press `r` in the terminal for hot reload
- Press `R` for hot restart
- Press `q` to quit

## Running on iOS Simulator

### Setting up iOS Simulator (macOS Only)

1. Install Xcode from Mac App Store
2. Install Xcode command line tools:
   ```bash
   xcode-select --install
   ```

3. Open iOS Simulator:
   ```bash
   open -a Simulator
   ```

4. Or via Flutter:
   ```bash
   flutter devices
   # Select an iOS simulator from the list
   ```

### Running the App

1. Ensure the backend is running (see [Backend Setup](#backend-setup))

2. Run the Flutter app on the simulator:
   ```bash
   flutter run -d ios
   ```

3. The app will:
   - Build and install on the simulator
   - Connect to the backend at `http://127.0.0.1:8000/api/v1`
   - Open the app automatically

### CocoaPods Setup (First Time Only)

If you encounter CocoaPods errors:
```bash
cd ios
pod install
cd ..
flutter run
```

## App Usage

### First Time Setup

1. **Register an Account**
   - Tap "Register" on the login screen
   - Enter username, email, and password
   - Tap "Sign Up"

2. **Login**
   - Enter your credentials on the login screen
   - Tap "Login"

### Main Features

#### Home Screen
- View quick statistics (medicines, blood banks, ambulances)
- Quick action tiles to navigate to main features
- Emergency contacts with one-tap calling

#### Medicines Tab
- Search for medicines by name or generic name
- Filter by category
- View medicine availability at nearby pharmacies
- Tap a medicine to see pharmacy stock levels

#### Blood Banks Tab
- Search for blood banks by name or location
- Filter by blood group (A+, A-, B+, B-, AB+, AB-, O+, O-)
- View blood stock availability
- See distance from your location

#### Ambulances Tab
- Search for ambulance providers
- Filter by service type (Government, Private, NGO)
- Filter by capabilities (ICU, Oxygen)
- View contact information and services

#### Profile Tab
- Create and manage your medical ID
- Add blood group, height, weight, allergies
- Generate emergency QR code for medical responders
- Add emergency contacts
- View and edit profile information

### Location Services

The app uses your device location to:
- Find nearby pharmacies
- Calculate distances to blood banks and ambulances
- Provide location-based search results

**Note:** Grant location permissions when prompted for best results.

### Offline Mode

The app caches data locally for offline access:
- Medical profile is stored locally
- Emergency contacts are saved on device
- Some cached data may be available offline

## Troubleshooting

### Backend Issues

**Backend won't start**
```bash
# Check if ports are already in use
netstat -ano | findstr :8000
netstat -ano | findstr :5432

# Kill processes using the ports if needed
taskkill /PID <pid> /F
```

**Database connection errors**
- Ensure PostgreSQL is running in Docker
- Check `.env` file credentials match Docker Compose settings
- Restart Docker containers: `docker-compose restart`

### Flutter Issues

**No devices found**
```bash
# List available devices
flutter devices

# Start Android emulator manually
flutter emulators --launch <emulator_id>

# Start iOS simulator (macOS)
open -a Simulator
```

**Build failures**
```bash
# Clean Flutter build
flutter clean
flutter pub get
flutter run
```

**CocoaPods errors (iOS)**
```bash
cd ios
pod deintegrate
pod install
cd ..
```

### API Connection Issues

**App can't connect to backend**
- Ensure backend is running on port 8000
- Check firewall settings
- For Android emulator: The app uses `10.0.2.2:8000` (automatic)
- For iOS simulator: The app uses `127.0.0.1:8000` (automatic)

**Timeout errors**
- Check your internet connection
- Verify backend server is responsive
- Check API configuration in `lib/config/api_config.dart`

### Common Errors

**"Connection refused"**
- Backend is not running
- Wrong port number
- Firewall blocking connection

**"Authentication failed"**
- Invalid credentials
- Token expired (try logging out and back in)
- Backend auth endpoint down

**"No internet connection"**
- Check device/emulator network settings
- Ensure emulator has internet access
- Try toggling airplane mode on/off

## Development Tips

### Debug Mode

Run the app in debug mode for detailed logs:
```bash
flutter run --debug
```

View logs in the terminal or use Flutter DevTools:
```bash
flutter pub global activate devtools
flutter pub global run devtools
```

### Testing

Run widget tests:
```bash
flutter test
```

Run integration tests:
```bash
flutter test integration_test/
```

### Code Analysis

Analyze code for issues:
```bash
flutter analyze
```

Format code:
```bash
dart format .
```

## Additional Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Docker Documentation](https://docs.docker.com/)
- [Project README](./Project.md)
- [Backend README](./backend/README.md)

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review error logs in the terminal
3. Check backend logs in Docker containers
4. Open an issue on the project repository

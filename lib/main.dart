import 'package:flutter/material.dart';
import 'theme.dart';
import 'state.dart';
import 'screens/login_screen.dart';
import 'screens/create_account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/edit_medical_id_screen.dart';
import 'screens/owner_dashboard_screen.dart';
import 'screens/server_settings_screen.dart';
import 'services/display_preferences.dart';
import 'services/server_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must complete before the first screen can issue a request: ServerConfig's
  // URL getters are synchronous (they are read on every call), so the saved
  // host override has to be in memory by the time anything uses them.
  await ServerConfig.instance.load();
  // Same reasoning, one screen later: the search results read the stock
  // display mode synchronously while building, so loading it after runApp
  // would show every card in the default mode for a frame and then flip.
  await DisplayPreferences.instance.load();
  runApp(const MedAlertApp());
}

class MedAlertApp extends StatelessWidget {
  const MedAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateManager.instance;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: state.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'MedAlert',
          debugShowCheckedModeBanner: false,
          theme: MedAlertTheme.lightTheme,
          darkTheme: MedAlertTheme.darkTheme,
          themeMode: themeMode,
          initialRoute: '/',
          routes: {
            '/': (context) => const LoginScreen(),
            '/create_account': (context) => const CreateAccountScreen(),
            '/home': (context) => const AppShell(),
            '/edit_medical_id': (context) => const EditMedicalIdScreen(),
            '/owner': (context) => const OwnerDashboardScreen(),
            '/settings': (context) => const ServerSettingsScreen(),
          },
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'theme.dart';
import 'state.dart';
import 'screens/login_screen.dart';
import 'screens/create_account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/edit_medical_id_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
          },
        );
      },
    );
  }
}

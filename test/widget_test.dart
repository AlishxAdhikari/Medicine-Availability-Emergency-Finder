// Basic smoke test for MedAlert app.

import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MedAlertApp());

    // The splash screen holds the app for 1.6s before replacing itself with
    // the login route, so let that timer fire rather than leaving it pending.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Verify login screen renders
    expect(find.text('MedAlert'), findsWidgets);
  });
}

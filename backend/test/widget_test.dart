// Basic smoke test for MedAlert app.

import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MedAlertApp());
    await tester.pumpAndSettle();

    // Verify login screen renders
    expect(find.text('MedAlert'), findsWidgets);
  });
}

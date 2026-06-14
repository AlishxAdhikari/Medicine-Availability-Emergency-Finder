import 'package:flutter_test/flutter_test.dart';

import 'package:medalert_nepal/main.dart';

void main() {
  testWidgets('renders the main dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.pumpAndSettle();

    expect(find.text('MedAlert Nepal'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });
}

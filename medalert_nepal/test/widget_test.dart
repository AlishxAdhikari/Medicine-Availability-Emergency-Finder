// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medalert_nepal/main.dart';

void main() {
  testWidgets('renders MedAlert dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.pumpAndSettle();

    expect(find.text('MedAlert Nepal'), findsOneWidget);
    expect(find.text('Authentication & Medical ID Master'), findsOneWidget);
  });
}

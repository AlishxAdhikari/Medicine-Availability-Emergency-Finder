import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/widgets/emergency_call.dart';

/// Pumps a screen whose only job is a button that opens the countdown, so the
/// dialog is shown the way the shell shows it (with a real Navigator above it).
Future<int Function()> _openCountdown(WidgetTester tester) async {
  var dialled = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showSosCountdown(context, onExpire: (_) async {
            dialled++;
          }),
          child: const Text('shake'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('shake'));
  await tester.pump();
  return () => dialled;
}

void main() {
  testWidgets('opens on the full count and ticks down', (tester) async {
    await _openCountdown(tester);

    expect(find.text('${kSosCountdown.inSeconds}'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('${kSosCountdown.inSeconds - 1}'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Cancel closes it without dialling', (tester) async {
    final dialled = await _openCountdown(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing);
    // Well past the point the countdown would have expired.
    await tester.pump(kSosCountdown);
    expect(dialled(), 0);
  });

  testWidgets('dials once when the count runs out', (tester) async {
    final dialled = await _openCountdown(tester);

    await tester.pump(kSosCountdown);
    await tester.pumpAndSettle();

    expect(dialled(), 1);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a second shake does not stack a second countdown',
      (tester) async {
    await _openCountdown(tester);

    // The button is still mounted behind the barrier; tapping it stands in
    // for the next shake arriving mid-countdown.
    await tester.tap(find.text('shake'), warnIfMissed: false);
    await tester.pump();

    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('cannot be dismissed by tapping outside', (tester) async {
    await _openCountdown(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}

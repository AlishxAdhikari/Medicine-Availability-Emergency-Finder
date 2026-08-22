import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/widgets/emergency_call.dart';

/// Pumps a screen whose only job is a button that opens the countdown, so the
/// dialog is shown the way the shell shows it (with a real Navigator above it).
Future<({int Function() dialled, int Function() alerted})> _openCountdown(
  WidgetTester tester,
) async {
  var dialled = 0;
  var alerted = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showSosCountdown(
            context,
            onExpire: (_) async {
              dialled++;
            },
            onAlertContacts: (_) async {
              alerted++;
            },
          ),
          child: const Text('shake'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('shake'));
  await tester.pump();
  return (dialled: () => dialled, alerted: () => alerted);
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
    final counts = await _openCountdown(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing);
    // Well past the point the countdown would have expired.
    await tester.pump(kSosCountdown);
    expect(counts.dialled(), 0);
  });

  testWidgets('dials once when the count runs out', (tester) async {
    final counts = await _openCountdown(tester);

    await tester.pump(kSosCountdown);
    await tester.pumpAndSettle();

    expect(counts.dialled(), 1);
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

  testWidgets('texting the contacts stops the call', (tester) async {
    final counts = await _openCountdown(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Text my contacts instead'));
    await tester.pumpAndSettle();

    expect(counts.alerted(), 1);

    // Well past the point the countdown would have expired: choosing to text
    // must not also open the dialer on top of the composer.
    await tester.pump(kSosCountdown);
    expect(counts.dialled(), 0);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('letting it run out dials and texts nobody', (tester) async {
    final counts = await _openCountdown(tester);

    await tester.pump(kSosCountdown);
    await tester.pumpAndSettle();

    expect(counts.dialled(), 1);
    expect(counts.alerted(), 0);
  });
}

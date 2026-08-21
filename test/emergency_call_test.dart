import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/location_service.dart';
import 'package:medalert/state.dart';
import 'package:medalert/widgets/emergency_call.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

UserProfile _profile({
  String bloodGroup = '',
  List<String> allergies = const [],
}) =>
    UserProfile(
      fullName: 'Test Patient',
      dob: '',
      gender: '',
      phoneNumber: '',
      medicalId: 'MA-0001',
      bloodGroup: bloodGroup,
      height: '',
      weight: '',
      allergies: allergies,
      medications: const [],
      emergencyContacts: const [],
    );

const _preciseFix = UserLocation(
  latitude: 27.71725,
  longitude: 85.32396,
  isPrecise: true,
);

const _guessedFix = UserLocation(
  latitude: 27.7172,
  longitude: 85.324,
  isPrecise: false,
  status: LocationStatus.servicesDisabled,
);

void main() {
  final state = AppStateManager.instance;
  final originalProfile = state.userProfileNotifier.value;

  tearDown(() => state.userProfileNotifier.value = originalProfile);

  group('SOS button', () {
    testWidgets('names the number it will dial', (tester) async {
      // The label has to be the number itself: someone who cannot get the
      // dialer open still needs to know what to punch in.
      await tester.pumpWidget(_host(const SosCallButton()));
      expect(find.text('CALL $kNationalAmbulanceNumber'), findsOneWidget);
    });

    testWidgets('warns that the call is not placed automatically',
        (tester) async {
      await tester.pumpWidget(_host(const SosCallButton()));
      await tester.tap(find.byType(SosCallButton));
      await tester.pumpAndSettle();

      // dial() only pre-fills the dialer, so the dialog must not imply that
      // tapping through has already summoned an ambulance.
      expect(find.textContaining('You will still need to press call'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancelling dials nothing and closes', (tester) async {
      await tester.pumpWidget(_host(const SosCallButton()));
      await tester.tap(find.byType(SosCallButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Open dialer'), findsNothing);
    });
  });

  group('dispatcher card', () {
    testWidgets('shows blood group, allergies and coordinates', (tester) async {
      state.userProfileNotifier.value =
          _profile(bloodGroup: 'O+', allergies: ['Penicillin', 'Peanuts']);

      await tester.pumpWidget(
          _host(const DispatcherInfoCard(location: _preciseFix)));

      expect(find.text('O+'), findsOneWidget);
      expect(find.text('Penicillin, Peanuts'), findsOneWidget);
      expect(find.textContaining('27.71725'), findsOneWidget);
    });

    testWidgets('says so explicitly when no allergies are recorded',
        (tester) async {
      // Silence would read as "no allergies" to a responder. An empty profile
      // and a profile that records no allergies are different facts.
      state.userProfileNotifier.value = _profile(bloodGroup: 'B-');

      await tester.pumpWidget(
          _host(const DispatcherInfoCard(location: _preciseFix)));

      expect(find.text('None recorded'), findsOneWidget);
    });

    testWidgets('marks a fallback location as approximate', (tester) async {
      // A city-centre guess read out as though it were a GPS fix would send
      // the ambulance to the wrong place.
      state.userProfileNotifier.value = _profile(bloodGroup: 'A+');

      await tester.pumpWidget(
          _host(const DispatcherInfoCard(location: _guessedFix)));

      expect(find.textContaining('(approximate)'), findsOneWidget);
    });

    testWidgets('copies the same facts as a pasteable block', (tester) async {
      state.userProfileNotifier.value =
          _profile(bloodGroup: 'O+', allergies: ['Penicillin']);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(
          _host(const DispatcherInfoCard(location: _guessedFix)));
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, contains('Blood group: O+'));
      expect(copied, contains('Allergies: Penicillin'));
      expect(copied, contains('27.71720, 85.32400'));
      // The parenthetical on the card is too terse to survive being pasted
      // into a message on its own.
      expect(copied, contains('approximate -- GPS was unavailable'));
      expect(find.text('Emergency details copied'), findsOneWidget);
    });

    testWidgets('renders nothing when there is nothing worth saying',
        (tester) async {
      // Blank profile, no location: a card whose only line is "Allergies:
      // None recorded" is a box that costs space and tells the user nothing.
      state.userProfileNotifier.value = _profile();

      await tester.pumpWidget(_host(const DispatcherInfoCard(location: null)));

      expect(find.text('Tell the dispatcher'), findsNothing);
    });
  });
}

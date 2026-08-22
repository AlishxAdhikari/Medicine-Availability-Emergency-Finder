import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/launcher_service.dart';
import 'package:medalert/services/location_service.dart';
import 'package:medalert/state.dart';
import 'package:medalert/widgets/emergency_call.dart';

UserProfile _profile({
  String fullName = 'Test Patient',
  String bloodGroup = 'O+',
  List<String> allergies = const ['Penicillin'],
  List<EmergencyContact> contacts = const [],
}) =>
    UserProfile(
      fullName: fullName,
      dob: '',
      gender: '',
      phoneNumber: '',
      medicalId: 'MA-0001',
      bloodGroup: bloodGroup,
      height: '',
      weight: '',
      allergies: allergies,
      medications: const [],
      emergencyContacts: contacts,
    );

EmergencyContact _contact(String phone) => EmergencyContact(
      name: 'Ram',
      relationship: 'Brother',
      phoneNumber: phone,
    );

const _fix = UserLocation(
  latitude: 27.71725,
  longitude: 85.32396,
  isPrecise: true,
);

const _guess = UserLocation(
  latitude: 27.7172,
  longitude: 85.324,
  isPrecise: false,
  status: LocationStatus.servicesDisabled,
);

void main() {
  group('emergencyAlertMessage', () {
    test('leads with a plain request for help', () {
      final text = emergencyAlertMessage(profile: _profile(), location: _fix);
      expect(text.split('\n').first, contains('need help'));
    });

    test('carries name, blood group and allergies', () {
      final text = emergencyAlertMessage(profile: _profile(), location: _fix);
      expect(text, contains('Test Patient'));
      expect(text, contains('O+'));
      expect(text, contains('Penicillin'));
    });

    test('includes a map link to the fix', () {
      final text = emergencyAlertMessage(profile: _profile(), location: _fix);
      expect(text, contains('27.71725'));
      expect(text, contains('85.32396'));
      expect(text, contains('https://www.google.com/maps'));
    });

    test('says so when the fix is only approximate', () {
      final text = emergencyAlertMessage(profile: _profile(), location: _guess);
      expect(text.toLowerCase(), contains('approximate'));
    });

    test('omits the location block entirely when there is no fix', () {
      final text = emergencyAlertMessage(profile: _profile(), location: null);
      expect(text, isNot(contains('maps')));
      expect(text, contains('Test Patient'));
    });

    test('records no allergies rather than staying silent', () {
      final text = emergencyAlertMessage(
        profile: _profile(allergies: const []),
        location: _fix,
      );
      expect(text, contains('None recorded'));
    });
  });

  group('smsUri', () {
    test('addresses every contact with a dialable number', () {
      final uri = LauncherService.smsUriForTest(
        ['+977 98-1234567', '01-4429345'],
        'help',
      );
      expect(uri, isNotNull);
      expect(uri!.path, '+977981234567,014429345');
    });

    test('drops numbers with nothing dialable in them', () {
      final uri = LauncherService.smsUriForTest(
        ['n/a', '', '014429345'],
        'help',
      );
      expect(uri!.path, '014429345');
    });

    test('is null when no contact has a usable number', () {
      expect(LauncherService.smsUriForTest(const ['n/a', ''], 'help'), isNull);
      expect(LauncherService.smsUriForTest(const [], 'help'), isNull);
    });

    test('encodes the body, newlines included', () {
      final uri = LauncherService.smsUriForTest(['014429345'], 'a b\nc');
      expect(uri.toString(), contains('?body=a%20b%0Ac'));
    });

    test('keeps one copy of a number listed twice', () {
      final uri = LauncherService.smsUriForTest(
        ['014429345', '01-4429345'],
        'help',
      );
      expect(uri!.path, '014429345');
    });
  });

  group('contactsWithNumbers', () {
    test('keeps only contacts that can actually be texted', () {
      final contacts = [
        _contact('014429345'),
        _contact('   '),
        _contact('n/a'),
      ];
      expect(contactsWithNumbers(contacts), hasLength(1));
    });
  });

  group('AlertContactsButton', () {
    final state = AppStateManager.instance;
    final original = state.userProfileNotifier.value;
    tearDown(() => state.userProfileNotifier.value = original);

    Future<void> pumpWith(
      WidgetTester tester,
      List<EmergencyContact> contacts,
    ) async {
      state.userProfileNotifier.value = _profile(contacts: contacts);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AlertContactsButton(location: _fix)),
      ));
    }

    testWidgets('names the one person it will text', (tester) async {
      await pumpWith(tester, [_contact('014429345')]);
      expect(find.text('Alert Ram'), findsOneWidget);
    });

    testWidgets('counts them when there is more than one', (tester) async {
      await pumpWith(tester, [_contact('014429345'), _contact('9812345678')]);
      expect(find.text('Alert my 2 contacts'), findsOneWidget);
    });

    testWidgets('stays generic when none can be texted', (tester) async {
      await pumpWith(tester, [_contact('n/a')]);
      expect(find.text('Alert my contacts'), findsOneWidget);
    });
  });
}

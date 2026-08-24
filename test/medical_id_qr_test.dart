import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/screens/medical_id_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:medalert/state.dart';

/// The QR carries the whole profile as plain text so any camera can read it
/// offline. That payload has a hard ceiling -- QR version 40 at error
/// correction M holds about 2330 bytes -- and every emergency contact, every
/// allergy and every medication makes it longer.
///
/// This matters more now that the profile can hold any number of contacts.
/// It used to persist exactly one, so the payload could not grow much; the
/// list is now unbounded and the screen builds a QrImageView with no
/// errorStateBuilder, so an over-long payload throws during build and takes
/// the whole Medical ID tab down rather than degrading.
UserProfile _profile({
  required int contacts,
  required int allergies,
  required int medications,
}) => UserProfile(
  fullName: 'Tushar Bahadur Khatiwada Chhetri',
  dob: '2003-05-11',
  gender: 'Male',
  phoneNumber: '9841234567',
  medicalId: 'MA-0001',
  bloodGroup: 'O+',
  height: '174',
  weight: '68',
  address: 'Ward 10, Sankhamul Marg, Lalitpur Metropolitan City, Bagmati',
  allergies: [
    for (var i = 0; i < allergies; i++)
      'Severe allergy number $i (anaphylaxis)',
  ],
  medications: [
    for (var i = 0; i < medications; i++)
      Medication(
        name: 'Medication number $i',
        dosage: '500mg',
        frequency: 'Twice daily after meals',
      ),
  ],
  emergencyContacts: [
    for (var i = 0; i < contacts; i++)
      EmergencyContact(
        name: 'Emergency Contact Number $i',
        relationship: 'Immediate family member',
        phoneNumber: '984111111$i',
      ),
  ],
);

Future<void> _pumpMedicalId(WidgetTester tester, UserProfile profile) async {
  AppStateManager.instance.updateProfile(profile);
  await tester.pumpWidget(const MaterialApp(home: MedicalIdScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the QR for a realistically full profile', (
    tester,
  ) async {
    await _pumpMedicalId(
      tester,
      _profile(contacts: 5, allergies: 5, medications: 5),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('too long'), findsNothing);
  });

  testWidgets('explains itself instead of crashing on an extreme profile', (
    tester,
  ) async {
    // Nobody sensible stores this much, but nothing in the editor stops them,
    // and the failure mode used to be a crashed tab rather than a message.
    await _pumpMedicalId(
      tester,
      _profile(contacts: 25, allergies: 25, medications: 25),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('too long for an offline QR'), findsOneWidget);
  });
  testWidgets('download is disabled when there is no QR to download', (
    tester,
  ) async {
    await _pumpMedicalId(
      tester,
      _profile(contacts: 25, allergies: 25, medications: 25),
    );

    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.textContaining('Download'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}

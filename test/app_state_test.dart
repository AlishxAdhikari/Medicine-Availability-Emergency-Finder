import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/state.dart';

void main() {
  test('builds a profile from authentication details using the supplied name', () {
    final profile = AppStateManager.instance.buildProfileFromAuth(
      fullName: 'Anurodh',
      email: 'anurodh@example.com',
      phoneNumber: '9812345678',
      dob: '1990-01-01',
    );

    expect(profile.fullName, 'Anurodh');
    expect(profile.phoneNumber, '9812345678');
    expect(profile.dob, '1990-01-01');
    expect(profile.medicalId, isNotEmpty);
  });

  test('falls back to the email prefix when no display name is available', () {
    final profile = AppStateManager.instance.buildProfileFromAuth(
      email: 'anurodh@example.com',
    );

    expect(profile.fullName, 'anurodh');
  });
}

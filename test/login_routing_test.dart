import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/screens/login_screen.dart';
import 'package:medalert/state.dart';

void main() {
  group('applyRoleFromUser', () {
    setUp(() => AppStateManager.instance.clearOwnerRole());

    test('records the pharmacy an owner is linked to', () {
      applyRoleFromUser({
        'role': 'pharmacy_owner',
        'pharmacy': {'id': 7, 'name': 'My Pharmacy'},
      });

      expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isTrue);
      expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, 7);
      expect(
        AppStateManager.instance.ownedPharmacyNameNotifier.value,
        'My Pharmacy',
      );
    });

    test('demotes on a user whose ownership was revoked server-side', () {
      // GET /auth/me/ answering 'user' has to undo a role restored from a
      // stale biometric snapshot moments earlier, not just fail to add one.
      AppStateManager.instance.setOwnerRole(
        isOwner: true, pharmacyId: 7, pharmacyName: 'My Pharmacy',
      );

      applyRoleFromUser({'role': 'user', 'pharmacy': null});

      expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isFalse);
      expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, isNull);
      expect(AppStateManager.instance.ownedPharmacyNameNotifier.value, '');
    });

    test('survives a missing role or pharmacy without throwing', () {
      // An older backend, or a response that lost the key.
      applyRoleFromUser({});

      expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isFalse);
    });

    test('accepts a pharmacy id that arrived as a double', () {
      applyRoleFromUser({
        'role': 'pharmacy_owner',
        'pharmacy': {'id': 7.0, 'name': 'My Pharmacy'},
      });

      expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, 7);
    });
  });

  group('routeForRole', () {
    test('sends a pharmacy owner to the dashboard', () {
      final route = routeForRole({
        'role': 'pharmacy_owner',
        'pharmacy': {'id': 7, 'name': 'My Pharmacy'},
      });

      expect(route, '/owner');
    });

    test('sends a plain user home', () {
      expect(routeForRole({'role': 'user', 'pharmacy': null}), '/home');
    });

    test('falls back to home when the server sends no role', () {
      // An older backend, or a response shape change -- default to the
      // read-only experience rather than opening an editor the account may
      // have no permission to use.
      expect(routeForRole({}), '/home');
    });
  });
}

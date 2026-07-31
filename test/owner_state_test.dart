import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/state.dart';

void main() {
  setUp(() {
    AppStateManager.instance.clearOwnerRole();
  });

  test('owner role is recorded and exposed', () {
    AppStateManager.instance.setOwnerRole(
      isOwner: true,
      pharmacyId: 7,
      pharmacyName: 'My Pharmacy',
    );

    expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isTrue);
    expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, 7);
    expect(AppStateManager.instance.ownedPharmacyNameNotifier.value, 'My Pharmacy');
  });

  test('clearing the role resets every owner field', () {
    AppStateManager.instance.setOwnerRole(
      isOwner: true,
      pharmacyId: 7,
      pharmacyName: 'My Pharmacy',
    );

    AppStateManager.instance.clearOwnerRole();

    expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isFalse);
    expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, isNull);
    expect(AppStateManager.instance.ownedPharmacyNameNotifier.value, '');
  });

  test('owner role survives a snapshot round trip', () {
    // The biometric login path restores from a snapshot rather than a login
    // response, so without this an owner unlocking with a fingerprint lands
    // on the user home screen instead of their dashboard.
    AppStateManager.instance.setOwnerRole(
      isOwner: true,
      pharmacyId: 7,
      pharmacyName: 'My Pharmacy',
    );
    final profile = AppStateManager.instance.userProfileNotifier.value;

    final snapshot = profileToSnapshot(profile);
    AppStateManager.instance.clearOwnerRole();
    applyOwnerRoleFromSnapshot(snapshot);

    expect(AppStateManager.instance.isPharmacyOwnerNotifier.value, isTrue);
    expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, 7);
    expect(AppStateManager.instance.ownedPharmacyNameNotifier.value, 'My Pharmacy');
  });
}

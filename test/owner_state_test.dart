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

  test('a snapshot id that came back as a double still restores', () {
    // Snapshots are persisted as JSON, and a whole number can come back as a
    // double. A hard `as int?` cast would throw here and take down the whole
    // biometric-unlock path, where every sibling field degrades gracefully.
    applyOwnerRoleFromSnapshot({
      'isPharmacyOwner': true,
      'ownedPharmacyId': 7.0,
      'ownedPharmacyName': 'My Pharmacy',
    });

    expect(AppStateManager.instance.ownedPharmacyIdNotifier.value, 7);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/launcher_service.dart';
import 'package:medalert/services/location_service.dart';

void main() {
  group('phone sanitising', () {
    // These are the shapes that actually appear in the seeded data and in
    // hand-entered admin rows. A tel: URI takes digits (optionally with a
    // leading +), so anything that survives formatting has to be stripped
    // before launch -- otherwise the dialer opens on a number that can't be
    // called, which looks identical to the old fake "Calling..." SnackBar.
    test('strips spaces, dashes and brackets', () {
      expect(LauncherService.sanitizePhoneForTest('01-4429345'), '014429345');
      expect(LauncherService.sanitizePhoneForTest('(01) 442 9345'), '014429345');
    });

    test('keeps a leading + so international numbers still dial', () {
      expect(LauncherService.sanitizePhoneForTest('+977 1-4429345'), '+97714429345');
    });

    test('takes the first number when a row holds several', () {
      // Concatenating both would produce a number that belongs to nobody.
      expect(LauncherService.sanitizePhoneForTest('014429345 / 014429346'), '014429345');
      expect(LauncherService.sanitizePhoneForTest('014429345, 014429346'), '014429345');
    });

    test('returns null for nothing dialable', () {
      // `phone` is blank=True on Pharmacy and BloodBank, so this is a real row
      // state, not a defensive hypothetical. Null is what makes the caller say
      // "no number on file" instead of opening an empty dialer.
      expect(LauncherService.sanitizePhoneForTest(null), isNull);
      expect(LauncherService.sanitizePhoneForTest(''), isNull);
      expect(LauncherService.sanitizePhoneForTest('   '), isNull);
      expect(LauncherService.sanitizePhoneForTest('n/a'), isNull);
    });
  });

  group('location status reporting', () {
    test('a real fix has nothing to report', () {
      expect(LocationStatus.ok.message, isNull);
    });

    test('every fallback reason carries a message the UI can show', () {
      // LocationNotice renders `status.message`, so a reason with no message
      // would produce a silent fallback -- exactly the failure this whole
      // change exists to remove.
      for (final status in LocationStatus.values) {
        if (status == LocationStatus.ok) continue;
        expect(status.message, isNotNull, reason: '$status has no message');
      }
    });

    test('only re-runnable failures are offered a retry', () {
      // Re-requesting a permanently denied permission returns immediately
      // without prompting, so a "Try again" there is a button that cannot
      // work. Those states get a settings link instead.
      expect(LocationStatus.deniedForever.isRetryable, isFalse);
      expect(LocationStatus.unsupported.isRetryable, isFalse);
      expect(LocationStatus.servicesDisabled.isRetryable, isTrue);
      expect(LocationStatus.timedOut.isRetryable, isTrue);
    });

    test('the fallback point is never labelled as precise', () {
      // Everything downstream keys off isPrecise to decide whether to warn the
      // user that the distances are nominal.
      expect(LocationService.fallback.isPrecise, isFalse);
    });
  });
}

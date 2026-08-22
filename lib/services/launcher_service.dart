import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Why a launch didn't happen, so the caller can show something more useful
/// than a generic failure. [LaunchFailure.none] means it did.
enum LaunchFailure {
  none,
  /// The record we were handed has no phone number / no coordinates at all.
  /// Nothing to launch; not the device's fault.
  missingData,
  /// No installed app claims this URL scheme (a tablet with no dialer, a
  /// device with no maps app).
  noHandler,
  /// The handler exists but refused or errored on the way out.
  failed,
}

/// Opens the phone dialer and external maps apps.
///
/// Everything here hands off to another app rather than doing the thing
/// itself. That is deliberate for the dialer: these are ambulance and blood
/// bank numbers, and `ACTION_DIAL` (pre-fill, user presses call) means a
/// mis-tap on the big red SOS button cannot ring an emergency line on its
/// own. Placing the call directly would need the CALL_PHONE permission, which
/// the manifest deliberately does not request.
class LauncherService {
  LauncherService._internal();
  static final LauncherService instance = LauncherService._internal();

  /// Opens the dialer with [rawNumber] pre-filled.
  ///
  /// Returns [LaunchFailure.missingData] for an empty or unusable number,
  /// which happens for real: `phone` is `blank=True` on Pharmacy and
  /// BloodBank, so a seeded row can genuinely have nothing to dial and the
  /// button needs to say so rather than fail mysteriously.
  Future<LaunchFailure> dial(String? rawNumber) async {
    final number = _sanitizePhone(rawNumber);
    if (number == null) return LaunchFailure.missingData;
    return _launch(Uri(scheme: 'tel', path: number));
  }

  /// Opens the SMS composer addressed to [rawNumbers] with [body] filled in.
  ///
  /// Composes rather than sends, for the same reason [dial] only pre-fills:
  /// the message goes out when the user presses send, so a mis-tap cannot
  /// text someone's family that they are in an emergency. Sending it
  /// ourselves would need SEND_SMS, which the manifest does not request.
  ///
  /// Returns [LaunchFailure.missingData] when none of [rawNumbers] holds a
  /// usable number -- a profile whose emergency contacts were saved without
  /// phone numbers, which the UI needs to report rather than open a blank
  /// composer.
  Future<LaunchFailure> sms(List<String?> rawNumbers, String body) async {
    final uri = smsUriForTest(rawNumbers, body);
    if (uri == null) return LaunchFailure.missingData;
    return _launch(uri);
  }

  /// Opens turn-by-turn directions to [lat]/[lng] in the platform's maps app.
  ///
  /// [label] is passed through so the destination shows the pharmacy's name
  /// instead of a bare coordinate pair.
  ///
  /// Tries the platform-native scheme first and falls back to a Google Maps
  /// https URL. The fallback is not redundant: `geo:` has no handler on iOS,
  /// and on a device with no maps app at all the https URL still opens in a
  /// browser, which is a worse experience but not a dead button.
  Future<LaunchFailure> openDirections({
    required double? lat,
    required double? lng,
    String? label,
  }) async {
    if (lat == null || lng == null) return LaunchFailure.missingData;

    final coords = '$lat,$lng';
    final webUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$coords',
    );

    final Uri native;
    if (!kIsWeb && Platform.isIOS) {
      // Apple Maps. `daddr` with `dirflg=d` asks for driving directions
      // rather than just dropping a pin.
      native = Uri.parse('https://maps.apple.com/?daddr=$coords&dirflg=d');
    } else if (!kIsWeb && Platform.isAndroid) {
      // `google.navigation:` starts navigation immediately, which is too
      // aggressive for a list row; `geo:` with a query opens the map centred
      // on the destination with a Directions button, and works with any maps
      // app the user has set as default, not just Google's.
      final query = label == null || label.isEmpty
          ? coords
          : '$coords(${Uri.encodeComponent(label)})';
      native = Uri.parse('geo:$coords?q=$query');
    } else {
      native = webUrl;
    }

    final result = await _launch(native);
    if (result == LaunchFailure.none || native == webUrl) return result;
    return _launch(webUrl);
  }

  Future<LaunchFailure> _launch(Uri uri) async {
    try {
      // canLaunchUrl is checked first so "no dialer installed" can be reported
      // as its own thing. It depends on the platform allowlists --
      // AndroidManifest <queries> and iOS LSApplicationQueriesSchemes -- so a
      // false here can also mean those went missing; both surface as
      // noHandler, which is the honest answer either way.
      if (!await canLaunchUrl(uri)) return LaunchFailure.noHandler;
      final launched = await launchUrl(
        uri,
        // The dialer and maps are separate apps, not web content to embed.
        mode: LaunchMode.externalApplication,
      );
      return launched ? LaunchFailure.none : LaunchFailure.failed;
    } catch (_) {
      return LaunchFailure.failed;
    }
  }

  /// Strips formatting a human typed into the admin ("+977 1-4429345",
  /// "01-4429345 / 4429346") down to something `tel:` accepts. Keeps a leading
  /// `+` for international numbers.
  ///
  /// Returns null when nothing dialable is left, so callers get one clear
  /// "no number on file" branch instead of launching `tel:` with an empty
  /// path, which opens a blank dialer and looks like a bug.
  static String? _sanitizePhone(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // A record holding two numbers separated by / or , is common in this
    // dataset. Dial the first: a tel: URI addresses one number, and silently
    // concatenating the digits of both would dial neither.
    final first = trimmed.split(RegExp(r'[/,;]')).first;

    final hasPlus = first.trimLeft().startsWith('+');
    final digits = first.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    return hasPlus ? '+$digits' : digits;
  }

  /// Builds the `sms:` URI [sms] launches, or null when no recipient survives
  /// sanitising. Exposed because the recipient list and the encoded body are
  /// the parts worth asserting on.
  ///
  /// Recipients are comma-separated, which both Android and iOS accept for a
  /// group composer, and de-duplicated so a number saved twice in different
  /// formats does not appear twice in the To field.
  static Uri? smsUriForTest(List<String?> rawNumbers, String body) {
    final numbers = <String>{
      for (final raw in rawNumbers) ?_sanitizePhone(raw),
    };
    if (numbers.isEmpty) return null;

    // Built by hand rather than with Uri's queryParameters, which encodes a
    // space as "+" -- literal plus signs in a text message body.
    return Uri.parse(
      'sms:${numbers.join(',')}?body=${Uri.encodeComponent(body)}',
    );
  }

  /// Exposed for tests -- the sanitizer is the part with real edge cases.
  static String? sanitizePhoneForTest(String? raw) => _sanitizePhone(raw);
}

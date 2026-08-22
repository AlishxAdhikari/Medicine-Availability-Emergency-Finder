import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/launcher_service.dart';
import '../services/location_service.dart';
import '../state.dart';
import 'location_notice.dart';

/// Nepal's national ambulance number.
///
/// Lives here rather than on the emergency screen because the SOS action is
/// now reachable from every tab -- the screen is no longer the only caller,
/// and two copies of an emergency number is one copy too many.
const String kNationalAmbulanceNumber = '102';

/// Hands [number] to the system dialer and reports the failure if there is
/// one. Silent on success: the dialer is now in front of the user, and a
/// SnackBar over the top of it says nothing they can't already see.
///
/// [subject] names who the number belongs to, so a record with no number on
/// file produces "No phone number on file for Ram (Brother)" rather than a
/// generic failure.
Future<void> dialEmergencyNumber(
  BuildContext context,
  String? number, {
  required String subject,
}) async {
  final result = await LauncherService.instance.dial(number);
  if (!context.mounted) return;
  final shown = (number ?? '').trim();
  showLaunchFailure(
    context,
    result,
    missingDataMessage: 'No phone number on file for $subject.',
    noHandlerMessage: shown.isEmpty
        ? 'No dialer is available on this device.'
        : 'No dialer is available on this device. Dial $shown manually.',
    failedMessage: shown.isEmpty
        ? 'Could not open the dialer.'
        : 'Could not open the dialer. Dial $shown manually.',
  );
}

/// Confirms, then opens the dialer on [kNationalAmbulanceNumber].
///
/// The confirmation stays deliberately: `LauncherService.dial` only pre-fills
/// the number (see its doc comment), but the SOS control is now a persistent
/// button on every tab, so the odds of a pocket tap went up rather than down.
Future<void> showEmergencyCallDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Color(0xFFBA1A1A)),
            SizedBox(width: 8),
            Text('Emergency Call'),
          ],
        ),
        content: const Text(
          'This opens your phone\'s dialer with $kNationalAmbulanceNumber '
          '(National Ambulance Service) entered. You will still need to '
          'press call.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              dialEmergencyNumber(
                context,
                kNationalAmbulanceNumber,
                subject: 'the national ambulance service',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Open dialer'),
          ),
        ],
      );
    },
  );
}

/// The big red block at the top of the emergency screen.
class SosCallButton extends StatelessWidget {
  const SosCallButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => showEmergencyCallDialog(context),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFBA1A1A),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFBA1A1A).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            const Icon(
              Icons.emergency,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            const Text(
              'CALL $kNationalAmbulanceNumber',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'National Ambulance Service',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sits under the SOS block: the same emergency, told to the people who would
/// come for you rather than to a dispatcher.
class AlertContactsButton extends StatelessWidget {
  const AlertContactsButton({super.key, required this.location});

  /// The fix the emergency screen has already resolved, so the message does
  /// not wait on a second lookup.
  final UserLocation? location;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile>(
      valueListenable: AppStateManager.instance.userProfileNotifier,
      builder: (context, profile, _) {
        final reachable = contactsWithNumbers(profile.emergencyContacts);
        final subject = switch (reachable.length) {
          0 => 'Alert my contacts',
          1 => 'Alert ${reachable.first.name}',
          final count => 'Alert my $count contacts',
        };

        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => alertEmergencyContacts(
              context,
              location: location,
            ),
            icon: const Icon(Icons.sms_outlined),
            label: Text(subject),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFBA1A1A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xFFBA1A1A), width: 1.4),
            ),
          ),
        );
      },
    );
  }
}

/// The small SOS button carried on the app shell, so the emergency call is one
/// tap from every tab instead of a tab switch plus a scroll.
class SosFloatingButton extends StatelessWidget {
  const SosFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showEmergencyCallDialog(context),
      backgroundColor: const Color(0xFFBA1A1A),
      foregroundColor: Colors.white,
      tooltip: 'Call $kNationalAmbulanceNumber, the national ambulance service',
      icon: const Icon(Icons.emergency),
      label: const Text(
        'SOS',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
      ),
    );
  }
}

/// The facts a dispatcher or a relative needs, as lines of text.
///
/// Shared by the "Copy" button on [DispatcherInfoCard] and by
/// [emergencyAlertMessage] so a copied block and a texted one can never
/// disagree about the patient.
String emergencyDetailsText(UserProfile profile) {
  final buffer = StringBuffer();

  final name = profile.fullName.trim();
  if (name.isNotEmpty) buffer.write('Name: $name\n');

  final bloodGroup = profile.bloodGroup.trim();
  if (bloodGroup.isNotEmpty) buffer.write('Blood group: $bloodGroup\n');

  final allergies =
      profile.allergies.where((a) => a.trim().isNotEmpty).toList();
  buffer.write(
    'Allergies: ${allergies.isEmpty ? 'None recorded' : allergies.join(', ')}',
  );

  return buffer.toString();
}

/// The message sent to the user's own emergency contacts.
///
/// Written to be read by a frightened relative on a lock screen, so it opens
/// with the request rather than a header, and ends with a tappable map link
/// instead of coordinates they would have to retype. An approximate fix is
/// spelled out in words: sending someone to a city-centre guess as though it
/// were a street address is worse than telling them to call.
String emergencyAlertMessage({
  required UserProfile profile,
  required UserLocation? location,
}) {
  final buffer = StringBuffer('I need help. Sent from MedAlert.\n\n')
    ..write(emergencyDetailsText(profile));

  if (location != null) {
    buffer
      ..write('\n\nMy location: ')
      ..write('${location.latitude.toStringAsFixed(5)}, '
          '${location.longitude.toStringAsFixed(5)}')
      ..write('\nhttps://www.google.com/maps/search/?api=1&query='
          '${location.latitude},${location.longitude}');
    if (!location.isPrecise) {
      buffer.write(
        '\n(This position is approximate -- GPS was unavailable. Please call '
        'me to find out where I am.)',
      );
    }
  }

  return buffer.toString();
}

/// Opens the SMS composer to the user's emergency contacts, pre-filled with
/// who they are, what a paramedic needs to know, and where they are.
///
/// Calling 102 and telling your family are both things that have to happen,
/// and only one of them can be done while unconscious. This is the other one.
///
/// [location] is passed in where the screen already has a fix (the emergency
/// screen resolves one for its blood-bank distances); a shake has none, so
/// this falls back to [LocationService], which returns a labelled Kathmandu
/// guess rather than nothing when GPS is unavailable -- and the message says
/// which of the two it is.
Future<void> alertEmergencyContacts(
  BuildContext context, {
  UserLocation? location,
}) async {
  final profile = AppStateManager.instance.userProfileNotifier.value;
  final contacts = contactsWithNumbers(profile.emergencyContacts);

  if (contacts.isEmpty) {
    // Not a launch failure -- there is nothing wrong with the device. The
    // profile is missing something only the user can add, so say that.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No emergency contact has a phone number yet. Add one on your '
          'Medical ID.',
        ),
      ),
    );
    return;
  }

  final where = location ?? await LocationService.instance.current();
  if (!context.mounted) return;

  final result = await LauncherService.instance.sms(
    [for (final contact in contacts) contact.phoneNumber],
    emergencyAlertMessage(profile: profile, location: where),
  );
  if (!context.mounted) return;

  showLaunchFailure(
    context,
    result,
    missingDataMessage: 'No emergency contact has a usable phone number.',
    noHandlerMessage: 'No messaging app is available on this device.',
    failedMessage: 'Could not open your messaging app.',
  );
}

/// The subset of [contacts] that can actually be reached by text.
///
/// A contact saved without a phone number is real in this app -- the editor
/// allows it -- and silently addressing a message to nobody is the failure
/// this filter exists to make visible.
List<EmergencyContact> contactsWithNumbers(List<EmergencyContact> contacts) {
  return contacts
      .where((c) => LauncherService.sanitizePhoneForTest(c.phoneNumber) != null)
      .toList();
}

/// What the dispatcher will ask for, on screen at the moment of the call.
///
/// Every field here is already in memory -- the profile is fetched when the
/// shell loads and [location] is resolved for the blood-bank distances -- so
/// this costs no request and works offline. That matters: the call happens
/// whether or not the backend is reachable.
class DispatcherInfoCard extends StatelessWidget {
  const DispatcherInfoCard({super.key, required this.location});

  /// The reading the emergency screen is already using. Null before the first
  /// load resolves.
  final UserLocation? location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder<UserProfile>(
      valueListenable: AppStateManager.instance.userProfileNotifier,
      builder: (context, profile, _) {
        final rows = <Widget>[];

        final bloodGroup = profile.bloodGroup.trim();
        if (bloodGroup.isNotEmpty) {
          rows.add(_row(theme, Icons.bloodtype, 'Blood group', bloodGroup));
        }

        final allergies =
            profile.allergies.where((a) => a.trim().isNotEmpty).toList();
        rows.add(_row(
          theme,
          Icons.warning_amber,
          'Allergies',
          allergies.isEmpty ? 'None recorded' : allergies.join(', '),
        ));

        final where = location;
        if (where != null) {
          rows.add(_row(
            theme,
            Icons.location_on,
            'Your location',
            '${where.latitude.toStringAsFixed(5)}, '
                '${where.longitude.toStringAsFixed(5)}'
                // An approximate fix is worth reading out, but the dispatcher
                // needs to know it is a city-centre guess and not where the
                // patient is.
                '${where.isPrecise ? '' : ' (approximate)'}',
          ));
        }

        // Nothing but the "None recorded" allergies line would be an empty
        // promise of a card. It only earns its space once there is something
        // real on it.
        if (rows.length < 2) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1D2024)
                : const Color(0xFFFFDAD6).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFBA1A1A).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tell the dispatcher',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Reading coordinates off the screen mid-call is error-prone
                  // and the numbers are the part that must not be wrong. Copy
                  // lets the user paste them into a message instead.
                  TextButton.icon(
                    onPressed: () => _copySummary(context, profile),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...rows,
            ],
          ),
        );
      },
    );
  }

  /// The same facts the card shows, as one pasteable block.
  ///
  /// Separate from the card's own rows because this is read by a person on the
  /// other end of a message, not scanned on screen: it names the patient and
  /// spells out an approximate fix in words rather than a parenthetical.
  String summaryText(UserProfile profile) {
    final buffer = StringBuffer('MedAlert emergency details\n')
      ..write(emergencyDetailsText(profile));

    final where = location;
    if (where != null) {
      buffer.write('\nLocation: ${where.latitude.toStringAsFixed(5)}, '
          '${where.longitude.toStringAsFixed(5)}');
      if (!where.isPrecise) {
        buffer.write(' (approximate -- GPS was unavailable)');
      }
    }

    return buffer.toString();
  }

  Future<void> _copySummary(BuildContext context, UserProfile profile) async {
    await Clipboard.setData(ClipboardData(text: summaryText(profile)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency details copied')),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How long the shake countdown gives the user to cancel before the dialer
/// opens. Long enough to notice and stop a pocket shake, short enough that
/// someone who meant it isn't standing there watching a number tick.
const Duration kSosCountdown = Duration(seconds: 5);

/// True while a countdown is on screen, so a shake that is still producing
/// jolts -- or a second one arriving mid-count -- cannot stack a second
/// dialog on top of the first.
bool _countdownVisible = false;

/// Shows the shake-triggered countdown to [kNationalAmbulanceNumber].
///
/// The gesture is unlike the SOS button in one way that matters: nobody
/// aimed at it. So the confirmation is inverted -- the call proceeds on its
/// own and the user acts to *stop* it, which is what someone who is hurt and
/// shaking the phone one-handed needs, while still giving a phone jostled in
/// a bag five seconds to be caught.
///
/// [onExpire] and [onAlertContacts] exist so tests can observe the outcome
/// without a dialer or an SMS app; the defaults are the same
/// [dialEmergencyNumber] and [alertEmergencyContacts] paths the buttons on the
/// emergency screen use.
Future<void> showSosCountdown(
  BuildContext context, {
  Future<void> Function(BuildContext context)? onExpire,
  Future<void> Function(BuildContext context)? onAlertContacts,
}) async {
  if (_countdownVisible) return;
  _countdownVisible = true;

  final expire = onExpire ??
      (BuildContext ctx) => dialEmergencyNumber(
            ctx,
            kNationalAmbulanceNumber,
            subject: 'the national ambulance service',
          );
  final alert = onAlertContacts ?? alertEmergencyContacts;

  try {
    final outcome = await showDialog<SosOutcome>(
      context: context,
      // Neither a stray tap on the barrier nor a back press should be able to
      // cancel: cancelling is a decision, and the button says so.
      barrierDismissible: false,
      builder: (dialogContext) => const PopScope(
        canPop: false,
        child: _SosCountdownDialog(),
      ),
    );

    if (!context.mounted) return;
    switch (outcome) {
      case SosOutcome.dial:
        await expire(context);
      case SosOutcome.alertContacts:
        await alert(context);
      case SosOutcome.cancelled:
      case null:
        break;
    }
  } finally {
    _countdownVisible = false;
  }
}

/// How a countdown ended.
///
/// [alertContacts] stops the call: the composer is another app, and letting
/// the dialer open on top of a half-written message would lose the message.
/// Texting instead of calling is a choice, so the button says "instead".
enum SosOutcome { dial, cancelled, alertContacts }

/// The countdown itself. Pops a [SosOutcome] saying how it ended.
class _SosCountdownDialog extends StatefulWidget {
  const _SosCountdownDialog();

  @override
  State<_SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<_SosCountdownDialog> {
  static const _red = Color(0xFFBA1A1A);

  int _remaining = kSosCountdown.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining > 1) {
        setState(() => _remaining--);
        return;
      }
      _timer?.cancel();
      Navigator.of(context).pop(SosOutcome.dial);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: _red,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emergency, size: 56, color: Colors.white),
            const SizedBox(height: 12),
            const Text(
              'Calling $kNationalAmbulanceNumber',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '$_remaining',
              style: const TextStyle(
                fontSize: 72,
                height: 1,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Detected a shake. Your dialer will open with '
              '$kNationalAmbulanceNumber entered.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop(SosOutcome.cancelled);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // Someone who cannot speak needs the other half of an emergency:
            // telling the people who would come for them. It stops the clock,
            // because the composer is a different app and the dialer opening
            // over a half-written message would lose it.
            TextButton(
              onPressed: () {
                _timer?.cancel();
                Navigator.of(context).pop(SosOutcome.alertContacts);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text(
                'Text my contacts instead',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

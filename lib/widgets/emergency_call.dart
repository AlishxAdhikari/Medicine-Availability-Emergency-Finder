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
    final buffer = StringBuffer('MedAlert emergency details');

    final name = profile.fullName.trim();
    if (name.isNotEmpty) buffer.write('\nName: $name');

    final bloodGroup = profile.bloodGroup.trim();
    if (bloodGroup.isNotEmpty) buffer.write('\nBlood group: $bloodGroup');

    final allergies =
        profile.allergies.where((a) => a.trim().isNotEmpty).toList();
    final allergyText =
        allergies.isEmpty ? 'None recorded' : allergies.join(', ');
    buffer.write('\nAllergies: $allergyText');

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

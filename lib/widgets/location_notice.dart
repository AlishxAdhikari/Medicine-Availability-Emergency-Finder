import 'package:flutter/material.dart';

import '../services/launcher_service.dart';
import '../services/location_service.dart';

/// A banner shown when results are being sorted around the fallback point
/// rather than the user's real position.
///
/// This exists because the fallback itself is not the problem -- a
/// distance-sorted search needs an origin, and searching around Kathmandu
/// beats refusing to search. The problem is a fallback the user can't see:
/// every card would still read "1.2km away" and mean "1.2km from the middle of
/// the capital", which is indistinguishable from a working feature until
/// somebody drives to the wrong pharmacy.
///
/// Renders nothing at all when the location is real, so it can be dropped
/// unconditionally into a layout.
class LocationNotice extends StatelessWidget {
  const LocationNotice({super.key, required this.location, this.onRetry});

  /// Null while the first fix is still resolving -- nothing is claimed yet, so
  /// nothing is shown.
  final UserLocation? location;

  /// Re-runs the location request. Only offered for states where that could
  /// actually change the answer; a permanently denied permission gets a link
  /// to system settings instead, because re-requesting it returns immediately
  /// without ever prompting.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final current = location;
    if (current == null || current.isPrecise) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final message = current.status.message ??
        'Using an approximate location. Distances are estimates.';

    final Widget? action;
    switch (current.status) {
      case LocationStatus.deniedForever:
        action = TextButton(
          onPressed: () => LocationService.instance.openPermissionSettings(),
          child: const Text('Settings'),
        );
      case LocationStatus.servicesDisabled:
        action = TextButton(
          onPressed: () => LocationService.instance.openLocationSettings(),
          child: const Text('Turn on'),
        );
      case LocationStatus.denied:
      case LocationStatus.timedOut:
        action = onRetry == null
            ? null
            : TextButton(onPressed: onRetry, child: const Text('Try again'));
      // Nothing the user can do about a device that has no location support.
      case LocationStatus.unsupported:
      case LocationStatus.ok:
        action = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.fromLTRB(12, 8, action == null ? 12 : 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.location_disabled,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Reports a failed dial/directions launch, and stays silent on success --
/// the user is already looking at the dialer or the maps app, and a SnackBar
/// confirming what they can see would be the same theatre as the old
/// "Calling 102..." message that never placed a call.
///
/// Each caller supplies its own wording because the useful message depends on
/// the record ("no phone number on file for Bir Hospital") rather than on the
/// failure mode alone.
void showLaunchFailure(
  BuildContext context,
  LaunchFailure failure, {
  required String missingDataMessage,
  required String noHandlerMessage,
  required String failedMessage,
}) {
  final String message;
  switch (failure) {
    case LaunchFailure.none:
      return;
    case LaunchFailure.missingData:
      message = missingDataMessage;
    case LaunchFailure.noHandler:
      message = noHandlerMessage;
    case LaunchFailure.failed:
      message = failedMessage;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

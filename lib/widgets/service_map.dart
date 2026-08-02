import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';

/// One pin on [ServiceMap].
class MapPlace {
  const MapPlace({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.subtitle,
    this.isPrimary = false,
    this.onTap,
  });

  final String label;
  final double latitude;
  final double longitude;

  /// Second line in the pin's tap sheet -- an address, or a district.
  final String? subtitle;

  /// Highlights the nearest/most relevant pin (the top search result).
  final bool isPrimary;

  /// Tapping the pin. Null makes the pin non-interactive rather than
  /// pretending to be a button.
  final VoidCallback? onTap;

  LatLng get point => LatLng(latitude, longitude);
}

/// A real, interactive map.
///
/// Replaces the static remote image both search screens used to render behind
/// hand-positioned `Positioned(top: 200, left: 250)` pins -- that showed the
/// same street layout and the same two fake labels no matter what the search
/// returned, in whatever city the user was actually in.
///
/// Tiles come from OpenStreetMap, which needs no API key. That is the reason
/// for the choice: the project has no map key configured on any platform, and
/// a google_maps_flutter widget without one renders a blank grey rectangle --
/// which would be a different kind of fake map, not a fix.
class ServiceMap extends StatefulWidget {
  const ServiceMap({
    super.key,
    required this.places,
    this.origin,
    this.onRecenter,
    this.emptyMessage = 'No locations to show on the map',
  });

  /// Pins to plot. Callers filter out records with no coordinates before
  /// building these -- see `Pharmacy.hasCoordinates`.
  final List<MapPlace> places;

  /// Where the user is. Drawn as its own marker and used as the recenter
  /// target. A non-precise location (the Kathmandu fallback) is deliberately
  /// NOT drawn as a "you are here" dot -- see [_buildUserMarker].
  final UserLocation? origin;

  /// Invoked by the recenter button before the camera moves, so the screen can
  /// force a fresh GPS read. Should resolve to the location to centre on.
  final Future<UserLocation?> Function()? onRecenter;

  final String emptyMessage;

  @override
  State<ServiceMap> createState() => _ServiceMapState();
}

class _ServiceMapState extends State<ServiceMap> {
  final MapController _controller = MapController();

  /// fitCamera needs a laid-out map; calling it before FlutterMap reports
  /// ready throws. Early requests are dropped rather than queued -- onMapReady
  /// fits unconditionally, so the newest state gets framed anyway.
  bool _mapReady = false;

  /// Whether the user has panned/zoomed by hand. Once they have, refitting the
  /// camera on every search result would yank the view out from under them, so
  /// auto-fit stops and the recenter button becomes the way back.
  bool _userMovedCamera = false;

  /// The pin whose details card is open, if any.
  MapPlace? _selected;

  @override
  void didUpdateWidget(covariant ServiceMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A cleared selection has to be dropped too -- holding a MapPlace from the
    // previous result set would keep a card open for a pharmacy that is no
    // longer in the list.
    if (_selected != null && !widget.places.contains(_selected)) {
      _selected = null;
    }

    if (!_samePoints(oldWidget.places, widget.places)) {
      // New results are a new answer to a new question, so the camera follows
      // them even if the user had panned -- otherwise searching a different
      // medicine leaves them staring at the old neighbourhood with the pins
      // off-screen.
      _userMovedCamera = false;
      _fitCamera();
    }
  }

  bool _samePoints(List<MapPlace> a, List<MapPlace> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  List<LatLng> get _allPoints => [
        for (final place in widget.places) place.point,
        // The user's own position is only worth fitting into view when it's
        // real. Including the Kathmandu fallback would zoom the map out to
        // span from the capital to wherever the results actually are.
        if (widget.origin?.isPrecise == true)
          LatLng(widget.origin!.latitude, widget.origin!.longitude),
      ];

  void _fitCamera() {
    if (!_mapReady || _userMovedCamera) return;

    final points = _allPoints;
    if (points.isEmpty) return;

    if (points.length == 1) {
      // CameraFit on a zero-area bounds resolves to the maximum zoom, which
      // lands the user on a rooftop. A single pin gets a fixed
      // neighbourhood-level zoom instead.
      _controller.move(points.first, 15);
      return;
    }

    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(48),
        // Two pharmacies in the same building would otherwise fit to street
        // level, where the map is all one grey block and gives no context.
        maxZoom: 16,
      ),
    );
  }

  Future<void> _handleRecenter() async {
    final resolved = await widget.onRecenter?.call() ?? widget.origin;
    if (!mounted) return;

    setState(() => _userMovedCamera = false);

    if (resolved != null && resolved.isPrecise) {
      _controller.move(LatLng(resolved.latitude, resolved.longitude), 14);
      return;
    }
    // No real fix to centre on -- fall back to framing the results, which is
    // still a more useful "reset the view" than jumping to a guessed point.
    _fitCamera();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = _allPoints;
    final initialCenter = points.isNotEmpty
        ? points.first
        : LatLng(
            widget.origin?.latitude ?? LocationService.fallback.latitude,
            widget.origin?.longitude ?? LocationService.fallback.longitude,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 13,
                minZoom: 3,
                maxZoom: 18,
                onMapReady: () {
                  _mapReady = true;
                  _fitCamera();
                },
                onPositionChanged: (position, hasGesture) {
                  // Only a real gesture counts. Our own fitCamera/move calls
                  // also fire this, and treating those as user intent would
                  // disable auto-fit after the very first frame.
                  if (hasGesture && !_userMovedCamera) {
                    setState(() => _userMovedCamera = true);
                  }
                },
                // Tapping empty map dismisses an open pin card.
                onTap: (_, _) {
                  if (_selected != null) setState(() => _selected = null);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // Required by the OSM tile usage policy: anonymous requests
                  // get rate-limited or blocked outright.
                  userAgentPackageName: 'com.medalert.medalert',
                  maxNativeZoom: 19,
                ),
                if (widget.origin != null) _buildUserMarker(context),
                MarkerLayer(
                  markers: [
                    for (final place in widget.places) _buildPlaceMarker(context, place),
                  ],
                ),
                // OSM's licence requires visible attribution wherever its
                // tiles are shown.
                const SimpleAttributionWidget(
                  source: Text('© OpenStreetMap contributors'),
                ),
              ],
            ),

            if (widget.places.isEmpty)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _Pill(
                  icon: Icons.location_off,
                  text: widget.emptyMessage,
                  background: theme.colorScheme.surface,
                  foreground: theme.colorScheme.onSurfaceVariant,
                ),
              ),

            if (widget.origin != null && !widget.origin!.isPrecise)
              Positioned(
                bottom: 12,
                left: 12,
                child: _Pill(
                  icon: Icons.gps_off,
                  text: 'Approximate area',
                  background: theme.colorScheme.errorContainer,
                  foreground: theme.colorScheme.onErrorContainer,
                ),
              ),

            if (_selected != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _PlaceCard(
                  place: _selected!,
                  onClose: () => setState(() => _selected = null),
                ),
              ),

            Positioned(
              top: 12,
              right: 12,
              child: FloatingActionButton(
                mini: true,
                heroTag: null, // several maps can be alive across tabs
                tooltip: 'Recenter on my location',
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                onPressed: _handleRecenter,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The user's position. Drawn as a solid "you are here" dot only for a real
  /// fix; a fallback gets a hollow, dashed-looking marker so the map never
  /// asserts the user is standing in the middle of Kathmandu when it simply
  /// doesn't know where they are.
  Widget _buildUserMarker(BuildContext context) {
    final theme = Theme.of(context);
    final origin = widget.origin!;
    final point = LatLng(origin.latitude, origin.longitude);

    return MarkerLayer(
      markers: [
        Marker(
          point: point,
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: origin.isPrecise
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
          ),
        ),
      ],
    );
  }

  Marker _buildPlaceMarker(BuildContext context, MapPlace place) {
    final theme = Theme.of(context);
    final isSelected = identical(place, _selected);
    final color =
        place.isPrimary ? theme.colorScheme.primary : theme.colorScheme.secondary;

    return Marker(
      point: place.point,
      width: 44,
      height: 44,
      // Puts the whole pin above the coordinate, so its tip -- not its middle
      // -- sits on the place. Default `center` would draw the pharmacy half a
      // pin-height north of where it is.
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => setState(() => _selected = isSelected ? null : place),
        child: Icon(
          Icons.location_on,
          size: isSelected ? 44 : 36,
          color: color,
          shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card shown when a pin is tapped: which place it is, and its action.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.onClose});

  final MapPlace place;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    place.label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (place.subtitle != null && place.subtitle!.isNotEmpty)
                    Text(
                      place.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (place.onTap != null)
              IconButton(
                tooltip: 'Directions',
                icon: const Icon(Icons.directions),
                color: theme.colorScheme.primary,
                onPressed: place.onTap,
              ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../state.dart';
import '../services/emergency_service.dart';
import '../services/launcher_service.dart';
import '../services/location_service.dart';
import '../widgets/location_notice.dart';
import '../widgets/service_map.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  // Used when /districts/ comes back empty or unreachable -- the chips still
  // need something to render, but the backend is the source of truth when it
  // answers.
  static const List<String> _fallbackDistricts = ['Kathmandu', 'Lalitpur', 'Bhaktapur', 'Pokhara'];

  List<Ambulance> _ambulances = [];
  List<BloodBank> _bloodBanks = [];
  List<String> _districts = _fallbackDistricts;
  // The district the lists currently hold data for, so the notifier listener
  // can tell a real user selection from our own corrective assignment below.
  String? _loadedDistrict;
  // Only the very first load has nothing to draw yet and takes over the whole
  // screen. Every load after that is scoped to the two list sections, so the
  // district chips and the emergency call button stay on screen and usable
  // while the lists reload.
  bool _bootstrapping = true;
  // Whether the districts came from the backend. _bootstrapping can't stand in
  // for this: it's cleared as soon as there is something to draw, including
  // when what got drawn is _fallbackDistricts. Keeping the two separate is what
  // lets Retry ask for the real districts again after an outage.
  bool _districtsLoaded = false;
  bool _loadingLists = true;
  String? _error;
  // Whether _error is worth pressing a button about. Not every failure is
  // transient, and a Retry that re-runs the same request against the same data
  // is a button that is guaranteed to fail -- worse than no button.
  bool _canRetry = true;
  // Bumped per load, so a response belonging to a superseded request (two chip
  // taps in quick succession) can't land on top of a newer one's. Without it
  // the lists can end up holding one district's rows while the chips and
  // _loadedDistrict name another -- and that disagreement is sticky, because
  // _onDistrictChanged early-returns on equality and re-tapping an already
  // selected ChoiceChip reports selected: false, which the chip's handler
  // drops.
  int _requestId = 0;

  /// The point the blood-bank list is distance-sorted around, shared with the
  /// map and the "location is off" banner so all three agree. Ambulances are
  /// matched by district and don't use it.
  UserLocation? _location;

  ValueNotifier<String> get _districtNotifier =>
      AppStateManager.instance.selectedDistrictNotifier;

  @override
  void initState() {
    super.initState();
    _districtNotifier.addListener(_onDistrictChanged);
    _loadData();
  }

  @override
  void dispose() {
    _districtNotifier.removeListener(_onDistrictChanged);
    super.dispose();
  }

  void _onDistrictChanged() {
    if (_districtNotifier.value == _loadedDistrict) return;
    _loadData();
  }

  // Fetches both lists from the real backend (emergency/views.py) and
  // replaces the old hardcoded state.mockAmbulances/mockBloodBanks reads.
  // Filtering is done by the API's own ?district= filter rather than
  // client-side: the endpoints are paginated, so filtering a single fetched
  // page client-side hid whole districts once the dataset passed 20 rows.
  Future<void> _loadData({bool refreshLocation = false}) async {
    final requestId = ++_requestId;
    setState(() {
      _loadingLists = true;
      _error = null;
      _canRetry = true;
    });
    try {
      // Resolved once, up front, and handed to searchBloodBanks below so the
      // map's "you are here" marker and the distances on the cards come from
      // the same reading. Failure here is already swallowed inside
      // LocationService (it returns the labelled fallback), so this cannot be
      // what takes the emergency screen down.
      final location = await LocationService.instance.current(
        forceRefresh: refreshLocation,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() => _location = location);

      // The set of districts comes from the data and doesn't change while the
      // screen is open, so it's fetched once. Refetching it per chip tap would
      // put a whole round trip in front of every list load, for an answer we
      // already have.
      if (!_districtsLoaded) {
        final fetched = await EmergencyService.instance.fetchDistricts();
        if (!mounted || requestId != _requestId) return;
        // Chips and the SOS button can render as soon as the districts are
        // known -- they don't need to wait on the lists below. Even a partial
        // answer is worth showing: real districts, however few, beat a
        // hardcoded list that may not match the data at all.
        setState(() {
          _districts =
              fetched.districts.isNotEmpty ? fetched.districts : _fallbackDistricts;
          // Only a whole, non-empty answer settles the district list. An empty
          // result means the backend was unreachable (fetchDistricts swallows
          // its own failures), and an incomplete one means we're showing a
          // truncated set -- pinning either would leave Retry nothing to
          // re-fetch once the backend is back, for the life of the screen.
          _districtsLoaded = fetched.complete && fetched.districts.isNotEmpty;
          _bootstrapping = false;
        });
      }

      // A district that no longer exists in the data (or the initial default,
      // if the backend doesn't have it) would filter every list to empty.
      var district = _districtNotifier.value;
      if (!_districts.contains(district)) {
        district = _districts.first;
        // Set _loadedDistrict first so the listener treats this as already
        // loaded and doesn't kick off a second, redundant _loadData().
        _loadedDistrict = district;
        // selectedDistrictNotifier is app-global, and this screen's State is
        // disposed on every tab switch (home_screen.dart builds
        // _tabs[_currentIndex], not an IndexedStack), so a load that outlives
        // the screen must not still be steering the rest of the app.
        if (!mounted) return;
        _districtNotifier.value = district;
      }
      _loadedDistrict = district;

      final ambulances = await EmergencyService.instance.searchAmbulances(district: district);
      final bloodBanks = await EmergencyService.instance.searchBloodBanks(
        district: district,
        origin: location,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _ambulances = ambulances;
        _bloodBanks = bloodBanks;
        _loadingLists = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        // _fetchAllPages throws StateError when it pages past its runaway cap
        // with the server still reporting more results. That's a data-volume
        // problem, not a connectivity one: retrying re-runs the same paging
        // over the same rows and fails identically every time. Reporting it as
        // a connection error would send the user to check their wifi, and
        // offering Retry would hand them a button that cannot work.
        _canRetry = e is! StateError;
        _error = _canRetry
            ? 'Could not load emergency services. Check your connection and try again.'
            : 'Too many emergency services in ${_loadedDistrict ?? 'this district'} '
                'to load at once. Pick another district above.';
        _loadingLists = false;
        // build() draws nothing but a spinner while _bootstrapping is set, so a
        // failure on the first load has to clear it too -- otherwise the error
        // and its Retry button are rendered behind a spinner that never stops.
        // The chips fall back to _fallbackDistricts, which is enough shell to
        // hang the error state off.
        _bootstrapping = false;
      });
    }
  }

  /// Nepal's national ambulance number.
  static const String _nationalAmbulanceNumber = '102';

  void _showSOSCallDialog(BuildContext context) {
    showDialog(
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
            'This opens your phone\'s dialer with 102 (National Ambulance '
            'Service) entered. You will still need to press call.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _dial(
                  _nationalAmbulanceNumber,
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

  /// Hands [number] to the system dialer. Silent on success -- the dialer is
  /// now in front of the user, and a SnackBar saying "Calling..." over the top
  /// of it is exactly the theatre this screen used to do instead of calling.
  Future<void> _dial(String number, {required String subject}) async {
    final result = await LauncherService.instance.dial(number);
    if (!mounted) return;
    showLaunchFailure(
      context,
      result,
      missingDataMessage: 'No phone number on file for $subject.',
      noHandlerMessage: 'No dialer is available on this device. '
          'Dial $number manually.',
      failedMessage: 'Could not open the dialer. Dial $number manually.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = AppStateManager.instance;

    // Nothing to draw at all yet -- not even the district chips. Every later
    // load keeps the shell below on screen and spins only the lists.
    if (_bootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // District Filter Chips
            ValueListenableBuilder<String>(
              valueListenable: state.selectedDistrictNotifier,
              builder: (context, activeDistrict, _) {
                final districts = _districts;
                return SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: districts.length,
                    itemBuilder: (context, index) {
                      final dist = districts[index];
                      final isSelected = dist == activeDistrict;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(dist),
                          selected: isSelected,
                          selectedColor: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? (isDark ? Colors.black : Colors.white)
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              state.selectedDistrictNotifier.value = dist;
                            }
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Blood banks are distance-sorted, so say so when that distance is
            // measured from a guessed point.
            LocationNotice(
              location: _location,
              onRetry: () => _loadData(refreshLocation: true),
            ),

            // SOS Ambulance Button
            GestureDetector(
              onTap: () => _showSOSCallDialog(context),
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
                      'CALL 102',
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
            ),
            const SizedBox(height: 24),

            // Split grid or vertical list -- or, when the load failed, the
            // error in their place. A failure only takes out the two lists;
            // the chips and the emergency call button above stay usable.
            if (_error != null)
              _buildErrorSection(context)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 700) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildAmbulancesSection(context),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildBloodBanksSection(context),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildAmbulancesSection(context),
                        const SizedBox(height: 24),
                        _buildBloodBanksSection(context),
                      ],
                    );
                  }
                },
              ),
            const SizedBox(height: 64), // Padding at bottom for navigation bar
          ],
        ),
      ),
    );
  }

  Widget _buildErrorSection(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          if (_canRetry) ...[
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }

  Widget _buildListLoader() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildAmbulancesSection(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppStateManager.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_taxi, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Ambulance Services',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<String>(
          valueListenable: state.selectedDistrictNotifier,
          builder: (context, district, _) {
            if (_loadingLists) return _buildListLoader();

            // Already filtered by the API's ?district= -- see _loadData().
            final filteredAmbulances = _ambulances;

            if (filteredAmbulances.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'No ambulance services found in $district.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              );
            }

            return Column(
              children: filteredAmbulances.map((amb) => _buildAmbulanceCard(context, amb)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAmbulanceCard(BuildContext context, Ambulance amb) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: isDark ? const Color(0xFF1D2024) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        amb.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${amb.location} (${amb.distance})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: amb.isAvailable
                        ? const Color(0xFF00897B).withValues(alpha: 0.12)
                        : theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        amb.isAvailable ? Icons.check_circle : Icons.cancel,
                        size: 14,
                        color: amb.isAvailable ? const Color(0xFF00897B) : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        amb.isAvailable ? 'Available' : 'Unavailable',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: amb.isAvailable ? const Color(0xFF00897B) : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: amb.phone.trim().isEmpty
                  ? null
                  : () => _dial(amb.phone, subject: amb.name),
              icon: const Icon(Icons.call, size: 16),
              label: const Text('Call Now', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBloodBanksSection(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppStateManager.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.bloodtype, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'Blood Banks',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            ValueListenableBuilder<bool>(
              valueListenable: state.isBloodBankMapViewNotifier,
              builder: (context, isMapMode, _) {
                return ToggleButtons(
                  isSelected: [!isMapMode, isMapMode],
                  onPressed: (index) {
                    state.isBloodBankMapViewNotifier.value = (index == 1);
                  },
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 28, minWidth: 56),
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.list, size: 14),
                        SizedBox(width: 2),
                        Text('List', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(Icons.map, size: 14),
                        SizedBox(width: 2),
                        Text('Map', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Radius Filters
        ValueListenableBuilder<int>(
          valueListenable: state.bloodBankRadiusNotifier,
          builder: (context, radius, _) {
            final radii = [5, 10, 20];
            return Row(
              children: [
                Text(
                  'Radius: ',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: radii.map((r) {
                        final isSelected = r == radius;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text('$r km'),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                state.bloodBankRadiusNotifier.value = r;
                              }
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Map View or List View
        ValueListenableBuilder<bool>(
          valueListenable: state.isBloodBankMapViewNotifier,
          builder: (context, isMapMode, _) {
            if (isMapMode) {
              return _buildBloodBankMap(context);
            }

            return ValueListenableBuilder<String>(
              valueListenable: state.selectedDistrictNotifier,
              builder: (context, district, _) {
                if (_loadingLists) return _buildListLoader();

                // Already filtered by the API's ?district= -- see _loadData().
                final filteredBanks = _bloodBanks;

                if (filteredBanks.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'No blood banks found in $district.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                  );
                }

                return Column(
                  children: filteredBanks.map((bank) => _buildBloodBankCard(context, bank)).toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// The blood-bank map. Real tiles, real markers at the banks' own
  /// coordinates -- the toggle used to switch to a static street photo with
  /// two icons nailed to fixed pixel offsets, which showed the same thing in
  /// every district.
  Widget _buildBloodBankMap(BuildContext context) {
    if (_loadingLists) return _buildListLoader();

    final plotted = _bloodBanks.where((b) => b.hasCoordinates).toList();

    return SizedBox(
      height: 260,
      child: ServiceMap(
        origin: _location,
        emptyMessage: _bloodBanks.isEmpty
            ? 'No blood banks in ${_loadedDistrict ?? 'this district'}'
            : 'These blood banks have no coordinates on file',
        places: [
          for (final bank in plotted)
            MapPlace(
              label: bank.name,
              subtitle: bank.distance.isEmpty
                  ? bank.location
                  : '${bank.location} • ${bank.distance}',
              latitude: bank.latitude!,
              longitude: bank.longitude!,
              // Matches the icon on the Blood Banks section header, so the
              // map and the list are obviously showing the same thing.
              icon: Icons.bloodtype,
              isPrimary: identical(bank, plotted.first),
              onTap: () => _openDirections(
                lat: bank.latitude,
                lng: bank.longitude,
                label: bank.name,
              ),
            ),
        ],
        onRecenter: () async {
          final location = await LocationService.instance.current(forceRefresh: true);
          if (!mounted) return location;
          setState(() => _location = location);
          // A newly-real fix changes the distance ordering, so the list behind
          // the map has to be re-fetched or it would keep describing distances
          // from the old point.
          if (location.isPrecise) _loadData();
          return location;
        },
      ),
    );
  }

  Future<void> _openDirections({
    required double? lat,
    required double? lng,
    required String label,
  }) async {
    final result = await LauncherService.instance.openDirections(
      lat: lat,
      lng: lng,
      label: label,
    );
    if (!mounted) return;
    showLaunchFailure(
      context,
      result,
      missingDataMessage: 'No location on file for $label.',
      noHandlerMessage: 'No maps app is available on this device.',
      failedMessage: 'Could not open directions.',
    );
  }

  Widget _buildBloodBankCard(BuildContext context, BloodBank bank) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: isDark ? const Color(0xFF1D2024) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bank.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${bank.location} (${bank.distance})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              childAspectRatio: 1.5,
              crossAxisSpacing: 8,
              children: bank.availability.map((stock) {
                Color statusColor;
                Color bgColor;
                if (stock.status == 'CRITICAL') {
                  statusColor = const Color(0xFFBA1A1A);
                  bgColor = const Color(0xFFFFDAD6).withValues(alpha: 0.4);
                } else if (stock.status == 'LOW') {
                  statusColor = const Color(0xFFB47A00);
                  bgColor = const Color(0xFFFDF3D9).withValues(alpha: 0.4);
                } else {
                  statusColor = const Color(0xFF00897B);
                  bgColor = const Color(0xFFE6F4E6).withValues(alpha: 0.4);
                }

                return Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        stock.type,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stock.status,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: bank.phone.trim().isEmpty
                        ? null
                        : () => _dial(bank.phone, subject: bank.name),
                    icon: const Icon(Icons.call, size: 16),
                    label: const Text('Call Center',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor:
                          isDark ? const Color(0xFF282A2F) : const Color(0xFFF1F3FC),
                      foregroundColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    // BloodBank does carry lat/lng, so unlike ambulances these
                    // can genuinely be navigated to.
                    onPressed: bank.hasCoordinates
                        ? () => _openDirections(
                              lat: bank.latitude,
                              lng: bank.longitude,
                              label: bank.name,
                            )
                        : null,
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Directions',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor:
                          isDark ? const Color(0xFF282A2F) : const Color(0xFFF1F3FC),
                      foregroundColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../services/gemini_prescription_service.dart';
import '../services/launcher_service.dart';
import '../services/location_service.dart';
import '../services/pharmacy_service.dart';
import '../services/stock_alert_service.dart';
import '../state.dart';
import '../widgets/location_notice.dart';
import '../widgets/service_map.dart';

class PharmacySearchScreen extends StatefulWidget {
  const PharmacySearchScreen({super.key});

  @override
  State<PharmacySearchScreen> createState() => _PharmacySearchScreenState();
}

class _PharmacySearchScreenState extends State<PharmacySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Pharmacy> _results = [];
  bool _isLoading = true;
  String? _error;

  /// Where the search is being run from. Resolved once per fetch and reused
  /// for the request origin, the map's "you are here" marker and the banner
  /// below -- three things that must agree, so they share one read rather than
  /// each asking the GPS separately.
  UserLocation? _location;

  // Live stock alerts (sync/ pipeline): connected to whichever pharmacy is
  // currently the top search result. Scope decision -- the app has no
  // per-pharmacy detail screen yet, and opening one WebSocket per visible
  // card would mean N connections per search. Watching just the nearest
  // result is enough to demonstrate the pipeline end-to-end; revisit this
  // once a pharmacy detail screen exists to watch whichever one the user
  // is actually looking at.
  final StockAlertService _alertService = StockAlertService();
  StreamSubscription<StockAlert>? _alertSubscription;
  int? _watchedPharmacyId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      AppStateManager.instance.pharmacySearchQueryNotifier.value = _searchController.text;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), _fetchPharmacies);
    });
    _fetchPharmacies();
  }

  Future<void> _openPrescriptionScanner() async {
    final apiKey = await GeminiPrescriptionService.instance.getApiKey();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Prescription Photo Scanner',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                'Scan a prescription to extract and search exact medicine names.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo with Camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndProcessImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndProcessImage(ImageSource.gallery);
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  apiKey == null || apiKey.isEmpty ? Icons.key_off : Icons.key,
                  color: apiKey == null || apiKey.isEmpty
                      ? theme.colorScheme.error
                      : const Color(0xFF00897B),
                ),
                title: Text(apiKey == null || apiKey.isEmpty
                    ? 'Set Free Gemini API Key'
                    : 'Change Gemini API Key'),
                subtitle: Text(
                  apiKey == null || apiKey.isEmpty
                      ? 'Required for prescription AI extraction'
                      : 'Key configured securely',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showApiKeyDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showApiKeyDialog() async {
    final currentKey = await GeminiPrescriptionService.instance.getApiKey() ?? '';
    final controller = TextEditingController(text: currentKey);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Google Gemini API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your free Gemini API key from Google AI Studio (aistudio.google.com) to analyze prescription photos.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'AIzaSy...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = controller.text.trim();
                await GeminiPrescriptionService.instance.setApiKey(text);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gemini API key saved successfully'),
                      backgroundColor: Color(0xFF00897B),
                    ),
                  );
                }
              },
              child: const Text('Save Key'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndProcessImage(ImageSource source) async {
    final apiKey = await GeminiPrescriptionService.instance.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      _showApiKeyDialog();
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (image == null) return;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Analyzing prescription with Gemini AI...',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );

      final bytes = await image.readAsBytes();
      final String mimeType = image.mimeType ?? 'image/jpeg';

      final medicines = await GeminiPrescriptionService.instance.analyzePrescriptionImage(
        bytes,
        mimeType: mimeType,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (medicines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No medicine names identified in the photo. Please try a clearer picture.'),
          ),
        );
        return;
      }

      _showDetectedMedicinesDialog(medicines);
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prescription scan failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showDetectedMedicinesDialog(List<String> medicines) {
    final selectedMap = {for (var m in medicines) m: true};

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF00897B)),
                  SizedBox(width: 8),
                  Text('Medicines Detected', style: TextStyle(fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select the medicines to search in local pharmacies:',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    ...medicines.map((med) {
                      return CheckboxListTile(
                        dense: true,
                        title: Text(med, style: const TextStyle(fontWeight: FontWeight.bold)),
                        value: selectedMap[med] ?? false,
                        onChanged: (val) {
                          setModalState(() {
                            selectedMap[med] = val ?? false;
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Search Pharmacies'),
                  onPressed: () {
                    final selected = medicines.where((m) => selectedMap[m] == true).toList();
                    if (selected.isEmpty) return;

                    Navigator.pop(ctx);
                    final queryText = selected.join(' ');
                    _searchController.text = queryText;
                    AppStateManager.instance.pharmacySearchQueryNotifier.value = queryText;
                    _fetchPharmacies();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Searching pharmacies for: ${selected.join(', ')}'),
                        backgroundColor: const Color(0xFF00897B),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _fetchPharmacies({bool refreshLocation = false}) async {
    setState(() => _isLoading = true);
    try {
      // Resolved here rather than inside PharmacyService so the map and the
      // banner get the exact point the results were sorted around -- a second
      // read could return a different (or newly permitted) position and leave
      // the pins disagreeing with the distances on the cards.
      final location = await LocationService.instance.current(
        forceRefresh: refreshLocation,
      );
      if (!mounted) return;
      setState(() => _location = location);

      final results = await PharmacyService.instance.search(
        query: AppStateManager.instance.pharmacySearchQueryNotifier.value,
        radiusKm: AppStateManager.instance.pharmacyRadiusNotifier.value,
        origin: location,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _error = null;
        _isLoading = false;
      });
      _watchTopResultForLiveStock();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server. Check your connection and try again.';
        _isLoading = false;
      });
    }
  }

  /// (Re)subscribes to the nearest result's stock-alert WebSocket. Safe to
  /// call after every search -- does nothing if the top result is already
  /// the one being watched, so a fresh search for the same area doesn't
  /// needlessly reconnect.
  Future<void> _watchTopResultForLiveStock() async {
    if (_results.isEmpty) {
      _alertSubscription?.cancel();
      _alertService.disconnect();
      _watchedPharmacyId = null;
      return;
    }

    final topPharmacy = _results.first;
    if (_watchedPharmacyId == topPharmacy.id) return; // already watching this one

    _alertSubscription?.cancel();
    _watchedPharmacyId = topPharmacy.id;
    final stream = await _alertService.connect(topPharmacy.id);
    if (!mounted) return;
    // A second search can start while the connect above is in flight. That
    // call moves _watchedPharmacyId on and reconnects the shared service,
    // which closes the stream we are holding. Without this check the
    // superseded call would resume and overwrite _alertSubscription with a
    // subscription to that dead stream, orphaning the live one and silently
    // ending stock updates. We never subscribe, so nothing is leaked.
    if (_watchedPharmacyId != topPharmacy.id) return;
    _alertSubscription = stream.listen(_onStockAlert);
  }

  void _onStockAlert(StockAlert alert) {
    if (!mounted) return;

    setState(() {
      // Update the matching medicine chip in place, if the watched
      // pharmacy's card is showing that medicine -- so the UI reflects
      // the new quantity without the user needing to re-search.
      final index = _results.indexWhere((p) => p.id == _watchedPharmacyId);
      if (index == -1) return;
      final pharmacy = _results[index];
      final itemIndex = pharmacy.items.indexWhere((i) => i['name'] == alert.medicineName);
      if (itemIndex != -1) {
        pharmacy.items[itemIndex]['inStock'] = alert.quantity > 0;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${alert.level == 'critical' ? '⚠️ Critical' : 'Low stock'}: '
          '${alert.medicineName} (${alert.quantity} left) at ${_results.first.name}',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _alertSubscription?.cancel();
    _alertService.disconnect();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    Widget leftPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search Bar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search pharmacies or meds...',
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.photo_camera,
                          color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                        ),
                        tooltip: 'Scan Prescription Photo',
                        onPressed: _openPrescriptionScanner,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.tune,
                          color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Says so when the distances below are measured from a guessed point
        // rather than the user's actual position, and offers the one action
        // that can fix it.
        LocationNotice(
          location: _location,
          onRetry: () => _fetchPharmacies(refreshLocation: true),
        ),

        // On phones the map doesn't get its own column, so it rides above the
        // results. Without this the map would only ever exist on tablets and
        // desktop, which is where it is least needed.
        if (!isWide && _results.any((p) => p.hasCoordinates)) ...[
          SizedBox(height: 220, child: _buildMap(context)),
          const SizedBox(height: 16),
        ],

        // Radius Filter
        ValueListenableBuilder<double>(
          valueListenable: AppStateManager.instance.pharmacyRadiusNotifier,
          builder: (context, radius, _) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF282A2F).withValues(alpha: 0.3) : const Color(0xFFE6E8F1).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Search Radius',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${radius.round()} km',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: radius,
                    min: 5.0,
                    max: 20.0,
                    activeColor: isDark ? const Color(0xFFAAC7FF) : theme.colorScheme.primary,
                    inactiveColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    onChanged: (val) {
                      AppStateManager.instance.pharmacyRadiusNotifier.value = val;
                    },
                    onChangeEnd: (val) => _fetchPharmacies(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('5km', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      Text('20km', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // Pharmacies List
        Expanded(
          child: Builder(
            builder: (context) {
              if (_isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (_error != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off, size: 32, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _fetchPharmacies,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (_results.isEmpty) {
                final query = AppStateManager.instance.pharmacySearchQueryNotifier.value;
                return Center(
                  child: Text(
                    query.isEmpty
                        ? 'No pharmacies found in this radius'
                        : 'No pharmacies found matching "$query"',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final pharmacy = _results[index];
                  return _buildPharmacyCard(context, pharmacy);
                },
              );
            },
          ),
        ),
      ],
    );

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: isWide
            ? Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: leftPanel,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 8,
                    child: _buildMap(context),
                  ),
                ],
              )
            : leftPanel,
      ),
    );
  }

  Widget _buildPharmacyCard(BuildContext context, Pharmacy pharmacy) {
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
                        pharmacy.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${pharmacy.distance} away • ${pharmacy.address}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: pharmacy.isOpen
                        ? const Color(0xFF00897B).withValues(alpha: 0.12)
                        : theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: pharmacy.isOpen ? const Color(0xFF00897B) : theme.colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        pharmacy.isOpen ? 'Open Now' : 'Closed',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: pharmacy.isOpen ? const Color(0xFF00897B) : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Stock indicators
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pharmacy.items.map((item) {
                final inStock = item['inStock'] as bool;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: inStock
                        ? const Color(0xFF00897B).withValues(alpha: 0.08)
                        : theme.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: inStock
                          ? const Color(0xFF00897B).withValues(alpha: 0.2)
                          : theme.colorScheme.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        inStock ? Icons.check_circle : Icons.cancel,
                        size: 14,
                        color: inStock ? const Color(0xFF00897B) : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${item['name']} (${inStock ? 'In Stock' : 'Out'})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: inStock ? const Color(0xFF00897B) : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Actions Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    // Disabled rather than silently no-op when there is
                    // nothing to navigate to -- a button that looks live and
                    // does nothing is what this screen had before.
                    onPressed: pharmacy.hasCoordinates
                        ? () => _openDirections(pharmacy)
                        : null,
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Directions', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: isDark ? const Color(0xFF282A2F) : const Color(0xFFF1F3FC),
                      foregroundColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    // `phone` is blank=True on the model, so plenty of real
                    // rows have nothing to dial.
                    onPressed: pharmacy.phone.trim().isEmpty
                        ? null
                        : () => _callPharmacy(pharmacy),
                    icon: const Icon(Icons.call, size: 16),
                    label: const Text('Call', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: isDark ? const Color(0xFF282A2F) : const Color(0xFFF1F3FC),
                      foregroundColor: theme.colorScheme.primary,
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

  /// The real map. Pins are the actual search results at their actual
  /// coordinates, so the view changes with the query and with where the user
  /// is standing -- unlike the static image and two fixed labels this
  /// replaced.
  Widget _buildMap(BuildContext context) {
    return ServiceMap(
      origin: _location,
      emptyMessage: _results.isEmpty
          ? 'No pharmacies in this radius'
          : 'These pharmacies have no coordinates on file',
      places: [
        for (final pharmacy in _results)
          if (pharmacy.hasCoordinates)
            MapPlace(
              label: pharmacy.name,
              subtitle: pharmacy.address,
              latitude: pharmacy.latitude!,
              longitude: pharmacy.longitude!,
              icon: Icons.local_pharmacy,
              // The nearest result -- results come back distance-sorted, so
              // it's the first one with a position.
              isPrimary: pharmacy.id ==
                  _results.firstWhere((p) => p.hasCoordinates).id,
              onTap: () => _openDirections(pharmacy),
            ),
      ],
      onRecenter: () async {
        final location = await LocationService.instance.current(forceRefresh: true);
        if (!mounted) return location;
        setState(() => _location = location);
        // A recenter that finally gets a real fix should also re-sort the
        // results around it; otherwise the map moves to the user and the list
        // underneath still describes distances from somewhere else.
        if (location.isPrecise) _fetchPharmacies();
        return location;
      },
    );
  }

  Future<void> _openDirections(Pharmacy pharmacy) async {
    final result = await LauncherService.instance.openDirections(
      lat: pharmacy.latitude,
      lng: pharmacy.longitude,
      label: pharmacy.name,
    );
    if (!mounted) return;
    showLaunchFailure(
      context,
      result,
      missingDataMessage: 'No location on file for ${pharmacy.name}.',
      noHandlerMessage: 'No maps app is available on this device.',
      failedMessage: 'Could not open directions.',
    );
  }

  Future<void> _callPharmacy(Pharmacy pharmacy) async {
    final result = await LauncherService.instance.dial(pharmacy.phone);
    if (!mounted) return;
    showLaunchFailure(
      context,
      result,
      missingDataMessage: 'No phone number on file for ${pharmacy.name}.',
      noHandlerMessage: 'No dialer is available on this device.',
      failedMessage: 'Could not open the dialer.',
    );
  }
}
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../services/gemini_prescription_service.dart';
import '../services/pharmacy_service.dart';
import '../services/stock_alert_service.dart';
import '../state.dart';

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

  Future<void> _fetchPharmacies() async {
    setState(() => _isLoading = true);
    try {
      final results = await PharmacyService.instance.search(
        query: AppStateManager.instance.pharmacySearchQueryNotifier.value,
        radiusKm: AppStateManager.instance.pharmacyRadiusNotifier.value,
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
  void _watchTopResultForLiveStock() {
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
    _alertSubscription = _alertService.connect(topPharmacy.id).listen(_onStockAlert);
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
                    child: _buildMapViewPlaceholder(context),
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
                    onPressed: () {},
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
                    onPressed: () {},
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

  Widget _buildMapViewPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191C20) : const Color(0xFFF1F3FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Styled Map Graphic using CustomPainter or background pattern
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.15 : 0.85,
              child: Image.network(
                'https://lh3.googleusercontent.com/aida-public/AB6AXuAHFlpvqnskCcVaoItUBd64zJn12fJXR5PQl-GZ8RdEHD2VbvzQgQbC_g7jmWZ8FyC0Zs0Bakvmi-WDzua3QyG0y38yJEbnyhQFyaBGVeGe5E73Ap62KfNTa_cwqQSPOn4uNI-CBJ-r9FhcEsm6OEZawmT5MjotGpEnKz1JQrMn55H5jJPkvRbkRj5YG6dWNBRksBQA9wbV7jBXAFrsvuphyqe7zqqaL6Xgyf1uV8ZzCbCkD_2TAd0C7wTojMIYtJwrNhSvonHWWjIh',
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (isDark)
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.65)),
            ),

          // Map Pins
          Positioned(
            top: 200,
            left: 250,
            child: _buildMapPin(context, 'City Central', isPrimary: true),
          ),
          Positioned(
            top: 120,
            left: 100,
            child: _buildMapPin(context, 'MediQuick 24/7', isPrimary: false),
          ),

          // Recenter FAB
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: const Icon(Icons.my_location),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPin(BuildContext context, String label, {required bool isPrimary}) {
    final theme = Theme.of(context);


    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isPrimary ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isPrimary ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Icon(
          Icons.location_on,
          size: 28,
          color: isPrimary ? theme.colorScheme.primary : theme.colorScheme.secondary,
        ),
      ],
    );
  }
}
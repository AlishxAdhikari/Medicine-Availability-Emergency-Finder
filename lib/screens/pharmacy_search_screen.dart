import 'package:flutter/material.dart';
import '../state.dart';

class PharmacySearchScreen extends StatefulWidget {
  const PharmacySearchScreen({super.key});

  @override
  State<PharmacySearchScreen> createState() => _PharmacySearchScreenState();
}

class _PharmacySearchScreenState extends State<PharmacySearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      AppStateManager.instance.pharmacySearchQueryNotifier.value = _searchController.text;
    });
  }

  @override
  void dispose() {
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
                        tooltip: 'Scan Prescription',
                        onPressed: () {},
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
          child: ValueListenableBuilder<String>(
            valueListenable: AppStateManager.instance.pharmacySearchQueryNotifier,
            builder: (context, query, _) {
              final filtered = AppStateManager.instance.mockPharmacies.where((p) {
                if (query.isEmpty) return true;
                return p.name.toLowerCase().contains(query.toLowerCase()) ||
                    p.items.any((item) => (item['name'] as String).toLowerCase().contains(query.toLowerCase()));
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No pharmacies found matching "$query"',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final pharmacy = filtered[index];
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
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: pharmacy.isOpen && pharmacy.items.any((i) => i['inStock'] as bool)
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Order requested from ${pharmacy.name}'),
                                backgroundColor: const Color(0xFF00897B),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.shopping_cart, size: 16),
                    label: const Text('Order', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
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

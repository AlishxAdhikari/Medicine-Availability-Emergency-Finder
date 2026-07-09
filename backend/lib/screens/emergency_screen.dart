import 'package:flutter/material.dart';
import '../state.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  void _showSOSCallDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Color(0xFFBA1A1A)),
              SizedBox(width: 8),
              Text('Emergency Call'),
            ],
          ),
          content: const Text(
            'Are you sure you want to place an emergency call to 102 (National Ambulance Service)?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Calling 102...'),
                    backgroundColor: Color(0xFFBA1A1A),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBA1A1A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Call'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = AppStateManager.instance;

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
                final districts = ['Kathmandu', 'Lalitpur', 'Bhaktapur', 'Pokhara'];
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

            // Split Grid or vertical list
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
            final filteredAmbulances = state.mockAmbulances.where((amb) {
              return amb.location.contains(district);
            }).toList();

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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Calling ${amb.name}...'),
                    backgroundColor: theme.colorScheme.primary,
                  ),
                );
              },
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
              return _buildBloodBankMapPlaceholder(context);
            }

            return ValueListenableBuilder<String>(
              valueListenable: state.selectedDistrictNotifier,
              builder: (context, district, _) {
                final filteredBanks = state.mockBloodBanks.where((bank) {
                  return bank.location.contains(district);
                }).toList();

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

  Widget _buildBloodBankMapPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15181C) : const Color(0xFFF1F3FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.2 : 0.8,
              child: Image.network(
                'https://lh3.googleusercontent.com/aida-public/AB6AXuAHFlpvqnskCcVaoItUBd64zJn12fJXR5PQl-GZ8RdEHD2VbvzQgQbC_g7jmWZ8FyC0Zs0Bakvmi-WDzua3QyG0y38yJEbnyhQFyaBGVeGe5E73Ap62KfNTa_cwqQSPOn4uNI-CBJ-r9FhcEsm6OEZawmT5MjotGpEnKz1JQrMn55H5jJPkvRbkRj5YG6dWNBRksBQA9wbV7jBXAFrsvuphyqe7zqqaL6Xgyf1uV8ZzCbCkD_2TAd0C7wTojMIYtJwrNhSvonHWWjIh',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map,
                  size: 48,
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Blood Banks Map View',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Markers
          Positioned(
            top: 60,
            left: 100,
            child: Icon(
              Icons.location_on,
              color: theme.colorScheme.error,
              size: 32,
            ),
          ),
          Positioned(
            top: 140,
            left: 180,
            child: Icon(
              Icons.location_on,
              color: theme.colorScheme.error,
              size: 32,
            ),
          ),
        ],
      ),
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
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Contacting ${bank.name} Transfusion Center...'),
                    backgroundColor: theme.colorScheme.primary,
                  ),
                );
              },
              icon: const Icon(Icons.call, size: 16),
              label: const Text('Call Center', style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF282A2F) : const Color(0xFFF1F3FC),
                foregroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

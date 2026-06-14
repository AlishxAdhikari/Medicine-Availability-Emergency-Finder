import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emergency_contact.dart';
import '../widgets/emergency_contact_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_tile.dart';
import 'app_shell.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static final _contacts = [
    EmergencyContact(id: '1', label: 'National Ambulance', phoneNumber: '102', icon: EmergencyContactIcon.phone),
    EmergencyContact(id: '2', label: 'Police Control', phoneNumber: '100', icon: EmergencyContactIcon.localPolice),
    EmergencyContact(id: '3', label: 'Fire Brigade', phoneNumber: '101', icon: EmergencyContactIcon.fireTruck),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            Text(
              'MedAlert Nepal',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Medicine availability, emergency contacts, blood banks, ambulances, and medical ID in one app.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
            ),
            const SizedBox(height: 20),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                StatTile(label: 'Medicines', value: '5', icon: Icons.medication_outlined),
                StatTile(label: 'Blood banks', value: '3', icon: Icons.bloodtype_outlined),
                StatTile(label: 'Ambulances', value: '4', icon: Icons.local_shipping_outlined),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader(
              title: 'Quick Actions',
              subtitle: 'Search nearby care resources faster.',
              icon: Icons.flash_on_outlined,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ActionTile(
                  icon: Icons.medication_outlined,
                  title: 'Find medicine',
                  color: const Color(0xFF0F766E),
                  onTap: () => ref.read(selectedTabProvider.notifier).state = 1,
                ),
                _ActionTile(
                  icon: Icons.bloodtype_outlined,
                  title: 'Check blood',
                  color: const Color(0xFFDC2626),
                  onTap: () => ref.read(selectedTabProvider.notifier).state = 2,
                ),
                _ActionTile(
                  icon: Icons.local_shipping_outlined,
                  title: 'Call ambulance',
                  color: const Color(0xFF2563EB),
                  onTap: () => ref.read(selectedTabProvider.notifier).state = 3,
                ),
                _ActionTile(
                  icon: Icons.badge_outlined,
                  title: 'Medical ID',
                  color: const Color(0xFF7C3AED),
                  onTap: () => ref.read(selectedTabProvider.notifier).state = 4,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader(
              title: 'Emergency Contacts',
              subtitle: 'Always available on the device.',
              icon: Icons.contact_phone_outlined,
            ),
            const SizedBox(height: 12),
            ..._contacts.map(
              (contact) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: EmergencyContactTile(contact: contact),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan Medical ID'),
                subtitle: const Text('Scan a patient\'s emergency QR code'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const QRScannerScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 155,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

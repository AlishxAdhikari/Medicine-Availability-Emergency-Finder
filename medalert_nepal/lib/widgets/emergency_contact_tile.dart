import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency_contact.dart';

class EmergencyContactTile extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const EmergencyContactTile({
    super.key,
    required this.contact,
    this.onTap,
    this.onDelete,
  });

  Future<void> _makeCall(String number) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: number.replaceAll(RegExp(r'[\s-]+'), ''),
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  IconData _getIconData(String iconName) {
    switch (iconName.toLowerCase().trim()) {
      case 'local_hospital':
      case 'hospital':
        return Icons.local_hospital_outlined;
      case 'local_police':
      case 'police':
        return Icons.local_police_outlined;
      case 'fire_truck':
      case 'fire':
        return Icons.fire_truck_outlined;
      case 'bloodtype':
      case 'blood':
        return Icons.bloodtype_outlined;
      case 'phone':
      default:
        return Icons.phone_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getIconData(contact.icon),
              color: theme.colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  contact.phoneNumber,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _makeCall(contact.phoneNumber),
            icon: const Icon(Icons.call_outlined),
            color: theme.colorScheme.primary,
            tooltip: 'Call Emergency Line',
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: Colors.red[400],
              tooltip: 'Delete Contact',
            ),
        ],
      ),
    );
  }
}

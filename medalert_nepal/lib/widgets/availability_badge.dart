import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class AvailabilityBadge extends StatelessWidget {
  final String status;

  const AvailabilityBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final cleanStatus = status.toLowerCase().trim();
    Color bgColor;
    Color textColor;
    String label;

    switch (cleanStatus) {
      case 'available':
      case 'adequate':
        bgColor = AppTheme.statusAvailable.withValues(alpha: 0.12);
        textColor = AppTheme.statusAvailable;
        label = 'Available';
        break;
      case 'low_stock':
      case 'low':
        bgColor = AppTheme.statusLowStock.withValues(alpha: 0.12);
        textColor = AppTheme.statusLowStock;
        label = 'Low Stock';
        break;
      case 'out_of_stock':
      case 'critical':
        bgColor = AppTheme.statusOutOfStock.withValues(alpha: 0.12);
        textColor = AppTheme.statusOutOfStock;
        label = 'Out of Stock';
        break;
      case 'unavailable':
      default:
        bgColor = AppTheme.statusUnavailable.withValues(alpha: 0.12);
        textColor = AppTheme.statusUnavailable;
        label = 'Unavailable';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
      ),
    );
  }
}

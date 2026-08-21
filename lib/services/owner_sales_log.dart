import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One line on a completed sale (medicine + qty + amounts).
class SaleLine {
  final String medicineName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const SaleLine({
    required this.medicineName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  Map<String, dynamic> toJson() => {
        'medicine_name': medicineName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'line_total': lineTotal,
      };

  factory SaleLine.fromJson(Map<String, dynamic> json) => SaleLine(
        medicineName: json['medicine_name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
      );
}

/// A completed POS sale with customer + line items (local audit log).
class SaleRecord {
  final String billNo;
  final DateTime time;
  final String pharmacyName;
  final String customerName;
  final String customerPhone;
  final String membership;
  final String membershipId;
  final List<SaleLine> lines;
  final double total;
  final String cashier;

  const SaleRecord({
    required this.billNo,
    required this.time,
    required this.pharmacyName,
    required this.customerName,
    required this.customerPhone,
    this.membership = 'NONE',
    this.membershipId = '',
    required this.lines,
    required this.total,
    this.cashier = '',
  });

  int get unitCount => lines.fold(0, (s, l) => s + l.quantity);

  Map<String, dynamic> toJson() => {
        'bill_no': billNo,
        'time': time.toIso8601String(),
        'pharmacy_name': pharmacyName,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'membership': membership,
        'membership_id': membershipId,
        'lines': lines.map((l) => l.toJson()).toList(),
        'total': total,
        'cashier': cashier,
      };

  factory SaleRecord.fromJson(Map<String, dynamic> json) => SaleRecord(
        billNo: json['bill_no'] as String? ?? '',
        time: DateTime.tryParse(json['time'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        pharmacyName: json['pharmacy_name'] as String? ?? '',
        customerName: json['customer_name'] as String? ?? '',
        customerPhone: json['customer_phone'] as String? ?? '',
        membership: json['membership'] as String? ?? 'NONE',
        membershipId: json['membership_id'] as String? ?? '',
        lines: ((json['lines'] as List?) ?? [])
            .map((e) => SaleLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        total: (json['total'] as num?)?.toDouble() ?? 0,
        cashier: json['cashier'] as String? ?? '',
      );
}

/// Persists completed sales so day/analytics reports can show who bought what.
class OwnerSalesLog {
  OwnerSalesLog._();
  static final OwnerSalesLog instance = OwnerSalesLog._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'owner_sales_log_v1';

  Future<List<SaleRecord>> loadAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SaleRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.time.compareTo(a.time));
    } catch (_) {
      return [];
    }
  }

  Future<void> add(SaleRecord sale) async {
    final all = await loadAll();
    all.insert(0, sale);
    // Keep last 500 sales
    final trimmed = all.take(500).toList();
    await _storage.write(
      key: _key,
      value: jsonEncode(trimmed.map((s) => s.toJson()).toList()),
    );
  }

  Future<List<SaleRecord>> forDay(DateTime dayStart) async {
    final dayEnd = dayStart.add(const Duration(days: 1));
    final all = await loadAll();
    return all
        .where((s) => !s.time.isBefore(dayStart) && s.time.isBefore(dayEnd))
        .toList();
  }
}

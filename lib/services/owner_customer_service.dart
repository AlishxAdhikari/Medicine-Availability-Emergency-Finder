import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// A pharmacy walk-in / regular customer with optional membership.
class PharmacyCustomer {
  final int? id;
  final String name;
  final String phone;
  final String membership; // NONE | SILVER | GOLD | PLATINUM
  final String membershipId;
  final String notes;
  final DateTime? createdAt;

  const PharmacyCustomer({
    this.id,
    required this.name,
    required this.phone,
    this.membership = 'NONE',
    this.membershipId = '',
    this.notes = '',
    this.createdAt,
  });

  bool get hasMembership => membership != 'NONE' && membership.isNotEmpty;

  String get membershipLabel {
    switch (membership) {
      case 'SILVER':
        return 'Silver';
      case 'GOLD':
        return 'Gold';
      case 'PLATINUM':
        return 'Platinum';
      default:
        return 'None';
    }
  }

  PharmacyCustomer copyWith({
    int? id,
    String? name,
    String? phone,
    String? membership,
    String? membershipId,
    String? notes,
    DateTime? createdAt,
  }) {
    return PharmacyCustomer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      membership: membership ?? this.membership,
      membershipId: membershipId ?? this.membershipId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory PharmacyCustomer.fromJson(Map<String, dynamic> json) {
    return PharmacyCustomer(
      id: json['id'] as int?,
      name: (json['name'] as String?)?.trim() ?? '',
      phone: (json['phone'] as String?)?.trim() ?? '',
      membership: (json['membership'] as String?) ?? 'NONE',
      membershipId: (json['membership_id'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'membership': membership,
        'membership_id': membershipId,
        'notes': notes,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}

/// Owner API + local cache for customers so billing works offline-ish.
class OwnerCustomerService {
  OwnerCustomerService._();
  static final OwnerCustomerService instance = OwnerCustomerService._();

  final ApiClient _client = ApiClient.instance;
  static const _storage = FlutterSecureStorage();
  static const _cacheKey = 'owner_customers_cache';

  Future<List<PharmacyCustomer>> fetchCustomers({String? query}) async {
    try {
      final data = await _client.get(
        '/my-pharmacy/customers/',
        query: query != null && query.isNotEmpty ? {'q': query} : null,
        auth: true,
      );
      final list = _parseList(data);
      if (query == null || query.isEmpty) {
        await _writeCache(list);
      }
      return list;
    } catch (_) {
      // Fall back to local cache when server is unreachable.
      final cached = await _readCache();
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        return cached
            .where((c) =>
                c.name.toLowerCase().contains(q) || c.phone.contains(q))
            .toList();
      }
      return cached;
    }
  }

  Future<PharmacyCustomer> createCustomer({
    required String name,
    required String phone,
    String membership = 'NONE',
    String membershipId = '',
    String notes = '',
  }) async {
    try {
      final data = await _client.post(
        '/my-pharmacy/customers/',
        {
          'name': name.trim(),
          'phone': phone.trim(),
          'membership': membership,
          'membership_id': membershipId.trim(),
          'notes': notes.trim(),
        },
        auth: true,
      );
      final customer =
          PharmacyCustomer.fromJson(Map<String, dynamic>.from(data as Map));
      await _upsertCache(customer);
      return customer;
    } catch (e) {
      // Local-only fallback so POS still works without backend.
      final local = PharmacyCustomer(
        id: DateTime.now().millisecondsSinceEpoch,
        name: name.trim(),
        phone: phone.trim(),
        membership: membership,
        membershipId: membershipId.trim(),
        notes: notes.trim(),
        createdAt: DateTime.now(),
      );
      await _upsertCache(local);
      return local;
    }
  }

  Future<PharmacyCustomer> updateCustomer(
    int id, {
    String? name,
    String? phone,
    String? membership,
    String? membershipId,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name.trim();
    if (phone != null) body['phone'] = phone.trim();
    if (membership != null) body['membership'] = membership;
    if (membershipId != null) body['membership_id'] = membershipId.trim();
    if (notes != null) body['notes'] = notes.trim();

    try {
      final data = await _client.patch(
        '/my-pharmacy/customers/$id/',
        body,
        auth: true,
      );
      final customer =
          PharmacyCustomer.fromJson(Map<String, dynamic>.from(data as Map));
      await _upsertCache(customer);
      return customer;
    } catch (_) {
      final cached = await _readCache();
      final idx = cached.indexWhere((c) => c.id == id);
      if (idx < 0) rethrow;
      final updated = cached[idx].copyWith(
        name: name,
        phone: phone,
        membership: membership,
        membershipId: membershipId,
        notes: notes,
      );
      await _upsertCache(updated);
      return updated;
    }
  }

  Future<void> deleteCustomer(int id) async {
    try {
      await _client.delete('/my-pharmacy/customers/$id/', auth: true);
    } catch (_) {}
    final cached = await _readCache();
    cached.removeWhere((c) => c.id == id);
    await _writeCache(cached);
  }

  List<PharmacyCustomer> _parseList(dynamic data) {
    final rows = switch (data) {
      List list => list,
      Map map when map['results'] is List => map['results'] as List,
      _ => <dynamic>[],
    };
    return rows
        .map((r) => PharmacyCustomer.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<PharmacyCustomer>> _readCache() async {
    final raw = await _storage.read(key: _cacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              PharmacyCustomer.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeCache(List<PharmacyCustomer> list) async {
    await _storage.write(
      key: _cacheKey,
      value: jsonEncode(list.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _upsertCache(PharmacyCustomer customer) async {
    final cached = await _readCache();
    final idx = cached.indexWhere((c) =>
        (customer.id != null && c.id == customer.id) ||
        c.phone == customer.phone);
    if (idx >= 0) {
      cached[idx] = customer;
    } else {
      cached.insert(0, customer);
    }
    await _writeCache(cached);
  }
}

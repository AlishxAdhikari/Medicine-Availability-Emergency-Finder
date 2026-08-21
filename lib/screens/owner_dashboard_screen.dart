import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/owner_customer_service.dart';
import '../services/owner_sales_log.dart';
import '../services/sales_report_pdf.dart';
import '../services/owner_stock_service.dart';
import '../services/pharmacy_service.dart';
import '../services/stock_alert_service.dart';
import '../state.dart';

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

bool priceHasChanged(String current, String edited) {
  final a = num.tryParse(current.trim());
  final b = num.tryParse(edited.trim());
  if (a != null && b != null) return a != b;
  return current.trim() != edited.trim();
}

String? validateQuantity(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Enter a quantity.';
  final value = int.tryParse(text);
  if (value == null) return 'Enter a whole number, e.g. 12.';
  if (value < 0) return 'Quantity cannot be negative.';
  return null;
}

bool isOwnershipRevoked(Object error) =>
    error is ApiException && error.statusCode == 403;

bool isSessionExpired(Object error) =>
    error is ApiException && error.statusCode == 401;

String? validateLowThreshold(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final value = int.tryParse(text);
  if (value == null) return 'Enter a whole number, e.g. 10.';
  if (value < 0) return 'The alert level cannot be negative.';
  return null;
}

String? validatePrice(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Enter a price.';
  final value = num.tryParse(text);
  if (value == null) return 'Enter an amount, e.g. 10.50.';
  if (value < 0) return 'Price cannot be negative.';
  return null;
}

// ─────────────────────────────────────────────
// Cart item
// ─────────────────────────────────────────────

class CartItem {
  final OwnerStock stock;
  int quantity;

  CartItem({required this.stock, this.quantity = 1});

  double get lineTotal {
    final price = double.tryParse(stock.price) ?? 0;
    return price * quantity;
  }
}

// ─────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<OwnerStock> _stock = [];
  bool _loading = true;
  String? _error;

  List<StockTransactionEntry> _transactions = [];
  bool _activityLoading = true;
  String? _activityError;
  final Map<int, String> _rowErrors = {};

  static const _offlineMessage =
      'Could not reach the server. Check your connection and try again.';

  final StockAlertService _alertService = StockAlertService();
  StreamSubscription<StockAlert>? _alertSubscription;
  StreamSubscription<StockTransactionEntry>? _transactionSubscription;

  // POS state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final List<CartItem> _cart = [];
  bool _selling = false;
  PharmacyCustomer? _selectedCustomer;

  // Customers tab state
  List<PharmacyCustomer> _customers = [];
  bool _customersLoading = true;
  String? _customersError;
  final TextEditingController _customerSearchController =
      TextEditingController();
  String _customerSearchQuery = '';

  static const Map<String, List<String>> _categoryKeywords = {
    'All': [],
    'Antibiotics': ['amoxicillin', 'azithromycin', 'ciprofloxacin', 'doxycycline'],
    'Pain / Fever': ['ibuprofen', 'paracetamol', 'diclofenac', 'nimesulide', 'aspirin'],
    'Cardiac': ['amlodipine', 'atenolol', 'losartan', 'atorvastatin', 'clopidogrel'],
    'Diabetes': ['metformin', 'glimepiride', 'insulin', 'sitagliptin'],
    'Gastric': ['omeprazole', 'pantoprazole', 'ranitidine', 'domperidone'],
    'Allergy': ['cetirizine', 'loratadine', 'fexofenadine', 'montelukast'],
    'Other': [],
  };

  void _onTabChanged() {
    // Intentionally empty: FAB visibility is driven by AnimatedBuilder
    // on _tabController so we never setState during tab animation/teardown.
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
  }

  void _onCustomerSearchChanged() {
    if (!mounted) return;
    setState(() =>
        _customerSearchQuery = _customerSearchController.text.trim().toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
    _loadTransactions();
    _loadCustomers();
    _subscribeToAlerts();
    _searchController.addListener(_onSearchChanged);
    _customerSearchController.addListener(_onCustomerSearchChanged);
  }

  @override
  void dispose() {
    // Remove listeners BEFORE disposing controllers to avoid
    // "_dependents.isEmpty is not true" during teardown.
    _tabController.removeListener(_onTabChanged);
    _searchController.removeListener(_onSearchChanged);
    _customerSearchController.removeListener(_onCustomerSearchChanged);
    _alertSubscription?.cancel();
    _alertSubscription = null;
    _transactionSubscription?.cancel();
    _transactionSubscription = null;
    _alertService.disconnect();
    _searchController.dispose();
    _customerSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // WebSocket + Loading
  // ─────────────────────────────────────────────

  Future<void> _subscribeToAlerts() async {
    final pharmacyId = AppStateManager.instance.ownedPharmacyIdNotifier.value;
    if (pharmacyId == null) return;

    try {
      final stream = await _alertService.connect(pharmacyId);
      if (!mounted) {
        _alertService.disconnect();
        return;
      }
      _alertSubscription = stream.listen(_onStockAlert);
      _transactionSubscription =
          _alertService.transactions.listen(_onStockTransaction);
    } catch (_) {}
  }

  void _onStockTransaction(StockTransactionEntry entry) {
    if (!mounted) return;
    setState(() {
      if (_transactions.any((t) => t.id == entry.id)) return;
      _transactions.insert(0, entry);
    });
  }

  void _onStockAlert(StockAlert alert) {
    if (!mounted) return;
    setState(() {
      final index = _stock.indexWhere((s) => s.medicineId == alert.medicineId);
      if (index != -1) {
        final row = _stock[index];
        _stock[index] = OwnerStock(
          id: row.id,
          medicineId: row.medicineId,
          medicineName: row.medicineName,
          quantity: alert.quantity,
          price: row.price,
          lowThreshold: row.lowThreshold,
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alert.level == 'critical'
              ? '${alert.medicineName} is out of stock.'
              : '${alert.medicineName} is running low (${alert.quantity} left).',
        ),
      ),
    );
  }

  void _leaveAsRevokedOwner() {
    AppStateManager.instance.clearOwnerRole();
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _leaveAsSignedOut() {
    AppStateManager.instance.clearOwnerRole();
    AppStateManager.instance.setLoggedIn(false);
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  void _replaceRow(OwnerStock updated) {
    final index = _stock.indexWhere((s) => s.id == updated.id);
    if (index != -1) _stock[index] = updated;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _rowErrors.clear();
    });
    try {
      final stock = await OwnerStockService.instance.fetchStock();
      if (!mounted) return;
      setState(() {
        _stock = stock;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isSessionExpired(e)) {
        _leaveAsSignedOut();
        return;
      }
      if (isOwnershipRevoked(e)) {
        _leaveAsRevokedOwner();
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on StateError {
      if (!mounted) return;
      setState(() {
        _error =
            'Your stock list is too long for this version of the app to show safely. Please update the app.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _offlineMessage;
        _loading = false;
      });
    }
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;
    setState(() {
      _activityLoading = true;
      _activityError = null;
    });
    try {
      final transactions = await OwnerStockService.instance.fetchTransactions();
      if (!mounted) return;
      setState(() {
        _transactions = transactions;
        _activityLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isSessionExpired(e)) {
        _leaveAsSignedOut();
        return;
      }
      if (isOwnershipRevoked(e)) {
        _leaveAsRevokedOwner();
        return;
      }
      setState(() {
        _activityError = e.message;
        _activityLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activityError = _offlineMessage;
        _activityLoading = false;
      });
    }
  }

  // ─────────────────────────────────────────────
  // Customers
  // ─────────────────────────────────────────────

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() {
      _customersLoading = true;
      _customersError = null;
    });
    try {
      final list = await OwnerCustomerService.instance.fetchCustomers();
      if (!mounted) return;
      setState(() {
        _customers = list;
        _customersLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isSessionExpired(e)) {
        _leaveAsSignedOut();
        return;
      }
      if (isOwnershipRevoked(e)) {
        _leaveAsRevokedOwner();
        return;
      }
      setState(() {
        _customersError = e.message;
        _customersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _customersError = _offlineMessage;
        _customersLoading = false;
      });
    }
  }

  List<PharmacyCustomer> get _filteredCustomers {
    if (_customerSearchQuery.isEmpty) return _customers;
    return _customers.where((c) {
      return c.name.toLowerCase().contains(_customerSearchQuery) ||
          c.phone.contains(_customerSearchQuery);
    }).toList();
  }

  Future<PharmacyCustomer?> _showCustomerForm({PharmacyCustomer? existing}) async {
    final nameController =
        TextEditingController(text: existing?.name ?? '');
    final phoneController =
        TextEditingController(text: existing?.phone ?? '');
    final membershipIdController =
        TextEditingController(text: existing?.membershipId ?? '');
    final notesController =
        TextEditingController(text: existing?.notes ?? '');
    String membership = existing?.membership ?? 'NONE';
    // Unique key per dialog open — avoids Duplicate GlobalKeys
    final formKey = GlobalKey<FormState>(debugLabel: 'customer_form_${existing?.id ?? 'new'}');

    try {
      final result = await showDialog<PharmacyCustomer>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                title: Text(existing == null ? 'New Customer' : 'Edit Customer'),
                content: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: nameController,
                            autofocus: true,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Customer Name *',
                              prefixIcon: Icon(Icons.person_outline, size: 20),
                              isDense: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number *',
                              prefixIcon: Icon(Icons.phone_outlined, size: 20),
                              hintText: '98XXXXXXXX',
                              isDense: true,
                            ),
                            validator: (v) {
                              final text = (v ?? '').trim();
                              if (text.isEmpty) return 'Phone is required';
                              if (text.length < 10) {
                                return 'Enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: membership,
                            decoration: const InputDecoration(
                              labelText: 'Membership',
                              prefixIcon: Icon(Icons.card_membership, size: 20),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'NONE', child: Text('None')),
                              DropdownMenuItem(
                                  value: 'SILVER', child: Text('Silver')),
                              DropdownMenuItem(
                                  value: 'GOLD', child: Text('Gold')),
                              DropdownMenuItem(
                                  value: 'PLATINUM', child: Text('Platinum')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => membership = v);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: membershipIdController,
                            decoration: const InputDecoration(
                              labelText: 'Membership ID (optional)',
                              prefixIcon: Icon(Icons.badge_outlined, size: 20),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: notesController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                              prefixIcon: Icon(Icons.notes, size: 20),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      final name = nameController.text.trim();
                      final phone = phoneController.text.trim();
                      final mid = membershipIdController.text.trim();
                      final notes = notesController.text.trim();
                      try {
                        PharmacyCustomer saved;
                        if (existing?.id != null) {
                          saved = await OwnerCustomerService.instance
                              .updateCustomer(
                            existing!.id!,
                            name: name,
                            phone: phone,
                            membership: membership,
                            membershipId: mid,
                            notes: notes,
                          );
                        } else {
                          saved = await OwnerCustomerService.instance
                              .createCustomer(
                            name: name,
                            phone: phone,
                            membership: membership,
                            membershipId: mid,
                            notes: notes,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx, saved);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(e is ApiException
                                ? e.message
                                : 'Could not save customer'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Text(existing == null ? 'Create' : 'Save'),
                  ),
                ],
              );
            },
          );
        },
      );
      return result;
    } finally {
      nameController.dispose();
      phoneController.dispose();
      membershipIdController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _createOrEditCustomer({PharmacyCustomer? existing}) async {
    final saved = await _showCustomerForm(existing: existing);
    if (saved == null || !mounted) return;
    setState(() {
      final idx = _customers.indexWhere((c) =>
          (saved.id != null && c.id == saved.id) || c.phone == saved.phone);
      if (idx >= 0) {
        _customers[idx] = saved;
      } else {
        _customers.insert(0, saved);
      }
      // Keep selection in sync if this was the selected customer
      if (_selectedCustomer != null &&
          ((_selectedCustomer!.id != null &&
                  _selectedCustomer!.id == saved.id) ||
              _selectedCustomer!.phone == saved.phone)) {
        _selectedCustomer = saved;
      }
    });
  }

  Future<void> _deleteCustomer(PharmacyCustomer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text('Remove ${customer.name} (${customer.phone})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || customer.id == null || !mounted) return;
    await OwnerCustomerService.instance.deleteCustomer(customer.id!);
    if (!mounted) return;
    setState(() {
      _customers.removeWhere((c) => c.id == customer.id);
      if (_selectedCustomer?.id == customer.id) {
        _selectedCustomer = null;
      }
    });
  }

  Future<void> _pickCustomerForBilling() async {
    final searchController = TextEditingController();
    List<PharmacyCustomer> results = List.from(_customers);

    final picked = await showDialog<PharmacyCustomer>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Select Customer'),
              content: SizedBox(
                width: 360,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search name or phone...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (v) {
                        final q = v.trim().toLowerCase();
                        setDialogState(() {
                          results = _customers.where((c) {
                            return c.name.toLowerCase().contains(q) ||
                                c.phone.contains(q);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: results.isEmpty
                          ? const Center(
                              child: Text('No customers found',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (_, i) {
                                final c = results[i];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    child: Text(
                                      c.name.isNotEmpty
                                          ? c.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  title: Text(c.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  subtitle: Text(
                                    c.hasMembership
                                        ? '${c.phone} · ${c.membershipLabel}'
                                        : c.phone,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: c.hasMembership
                                      ? Chip(
                                          label: Text(c.membershipLabel,
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                        )
                                      : null,
                                  onTap: () => Navigator.pop(ctx, c),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final created = await _showCustomerForm();
                    if (created != null && mounted) {
                      setState(() {
                        _customers.insert(0, created);
                        _selectedCustomer = created;
                      });
                    }
                  },
                  child: const Text('+ New'),
                ),
                if (_selectedCustomer != null)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _selectedCustomer = null);
                    },
                    child: const Text('Clear'),
                  ),
              ],
            );
          },
        );
      },
    );

    searchController.dispose();
    if (picked != null && mounted) {
      setState(() => _selectedCustomer = picked);
    }
  }

  // ─────────────────────────────────────────────
  // POS Logic
  // ─────────────────────────────────────────────

  List<OwnerStock> get _filteredStock {
    return _stock.where((item) {
      if (_searchQuery.isNotEmpty &&
          !item.medicineName.toLowerCase().contains(_searchQuery)) {
        return false;
      }

      if (_selectedCategory == 'All') return true;

      if (_selectedCategory == 'Other') {
        for (final entry in _categoryKeywords.entries) {
          if (entry.key == 'All' || entry.key == 'Other') continue;
          for (final keyword in entry.value) {
            if (item.medicineName.toLowerCase().contains(keyword)) return false;
          }
        }
        return true;
      }

      final keywords = _categoryKeywords[_selectedCategory] ?? [];
      for (final keyword in keywords) {
        if (item.medicineName.toLowerCase().contains(keyword)) return true;
      }
      return false;
    }).toList();
  }

  void _addToCart(OwnerStock stock) {
    if (stock.quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${stock.medicineName} is out of stock')),
      );
      return;
    }

    setState(() {
      final existing = _cart.indexWhere((c) => c.stock.id == stock.id);
      if (existing >= 0) {
        if (_cart[existing].quantity < stock.quantity) {
          _cart[existing].quantity++;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot add more than available stock')),
          );
        }
      } else {
        _cart.add(CartItem(stock: stock));
      }
    });
  }

  void _changeCartQty(CartItem item, int delta) {
    setState(() {
      item.quantity += delta;
      if (item.quantity <= 0) {
        _cart.remove(item);
      } else if (item.quantity > item.stock.quantity) {
        item.quantity = item.stock.quantity;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Max available stock reached')),
        );
      }
    });
  }

  double get _cartTotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);
  int get _cartItemCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  Future<void> _completeSale() async {
    if (_cart.isEmpty || _selling) return;

    // Prefer pre-selected customer; otherwise ask / create quickly
    PharmacyCustomer? customer = _selectedCustomer;
    if (customer == null) {
      final created = await _showCustomerForm();
      if (created == null || !mounted) return;
      customer = created;
      setState(() {
        final exists = _customers.any((c) =>
            (created.id != null && c.id == created.id) ||
            c.phone == created.phone);
        if (!exists) _customers.insert(0, created);
        _selectedCustomer = created;
      });
    }

    final saleCustomer = customer; // non-null after checks above
    setState(() => _selling = true);

    try {
      for (final item in List<CartItem>.from(_cart)) {
        final newQty = item.stock.quantity - item.quantity;
        final updated =
            await OwnerStockService.instance.setQuantity(item.stock.id, newQty);
        if (!mounted) return;
        setState(() => _replaceRow(updated));
      }

      final billItems = List<CartItem>.from(_cart);
      final total = _cartTotal;
      final billTime = DateTime.now();
      final billNo =
          'INV-${billTime.year}${billTime.month.toString().padLeft(2, '0')}${billTime.day.toString().padLeft(2, '0')}-${billTime.millisecondsSinceEpoch % 100000}';

      setState(() {
        _cart.clear();
        _selling = false;
      });

      // Persist sale with customer details for PDF / analytics reports
      final pharmacyName =
          AppStateManager.instance.ownedPharmacyNameNotifier.value;
      final profile = AppStateManager.instance.userProfileNotifier.value;
      final cashierName = [
        if ((profile.fullName).trim().isNotEmpty) profile.fullName.trim(),
      ].join();
      await OwnerSalesLog.instance.add(SaleRecord(
        billNo: billNo,
        time: billTime,
        pharmacyName: pharmacyName,
        customerName: saleCustomer.name,
        customerPhone: saleCustomer.phone,
        membership: saleCustomer.membership,
        membershipId: saleCustomer.membershipId,
        lines: billItems
            .map((item) => SaleLine(
                  medicineName: item.stock.medicineName,
                  quantity: item.quantity,
                  unitPrice: double.tryParse(item.stock.price) ?? 0,
                  lineTotal: item.lineTotal,
                ))
            .toList(),
        total: total,
        cashier: cashierName,
      ));

      if (!mounted) return;
      await _showBillDialog(
        items: billItems,
        total: total,
        time: billTime,
        billNo: billNo,
        customer: saleCustomer,
      );

      _loadTransactions();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _selling = false);
      if (isSessionExpired(e)) {
        _leaveAsSignedOut();
        return;
      }
      if (isOwnershipRevoked(e)) {
        _leaveAsRevokedOwner();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _selling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale failed. Check connection.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatBillText({
    required String pharmacyName,
    required String billNo,
    required DateTime time,
    required PharmacyCustomer customer,
    required List<CartItem> items,
    required double total,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('================================');
    buffer.writeln(pharmacyName.toUpperCase());
    buffer.writeln('================================');
    buffer.writeln('Bill No : $billNo');
    buffer.writeln(
        'Date    : ${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}  ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
    buffer.writeln('--------------------------------');
    buffer.writeln('Customer: ${customer.name}');
    buffer.writeln('Phone   : ${customer.phone}');
    if (customer.hasMembership) {
      buffer.writeln(
          'Member  : ${customer.membershipLabel}${customer.membershipId.isNotEmpty ? ' (${customer.membershipId})' : ''}');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('${'Medicine'.padRight(18)} Qty   Amount');
    buffer.writeln('--------------------------------');
    for (final item in items) {
      final name = item.stock.medicineName.length > 18
          ? '${item.stock.medicineName.substring(0, 16)}..'
          : item.stock.medicineName.padRight(18);
      final qty = 'x${item.quantity}'.padLeft(4);
      final amt = item.lineTotal.toStringAsFixed(2).padLeft(8);
      buffer.writeln('$name$qty $amt');
      final unit = double.tryParse(item.stock.price) ?? 0;
      buffer.writeln('  @ Rs ${unit.toStringAsFixed(2)} each');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('TOTAL               Rs ${total.toStringAsFixed(2)}');
    buffer.writeln('================================');
    buffer.writeln('  Thank you for your purchase!');
    buffer.writeln('     Get well soon.');
    buffer.writeln('================================');
    return buffer.toString();
  }

  Future<void> _showBillDialog({
    required List<CartItem> items,
    required double total,
    required DateTime time,
    required String billNo,
    required PharmacyCustomer customer,
  }) async {
    final pharmacyName =
        AppStateManager.instance.ownedPharmacyNameNotifier.value;
    final displayName = pharmacyName.isEmpty ? 'Pharmacy' : pharmacyName;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade400, width: 1.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          displayName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'TAX INVOICE / BILL',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _billMetaRow('Bill No', billNo),
                  _billMetaRow(
                    'Date',
                    '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}  ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  ),
                  const Divider(height: 16),
                  _billMetaRow('Customer', customer.name),
                  _billMetaRow('Phone', customer.phone),
                  if (customer.hasMembership)
                    _billMetaRow(
                      'Membership',
                      '${customer.membershipLabel}${customer.membershipId.isNotEmpty ? ' · ${customer.membershipId}' : ''}',
                    ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        flex: 5,
                        child: Text('Medicine',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const SizedBox(
                        width: 36,
                        child: Text('Qty',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const SizedBox(
                        width: 72,
                        child: Text('Amount',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...items.map((item) {
                    final unit = double.tryParse(item.stock.price) ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Text(
                                  item.stock.medicineName,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '${item.quantity}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  item.lineTotal.toStringAsFixed(2),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '  @ Rs ${unit.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 16, thickness: 1.2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        'Rs ${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Thank you for your purchase!\nGet well soon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final text = _formatBillText(
                  pharmacyName: displayName,
                  billNo: billNo,
                  time: time,
                  customer: customer,
                  items: items,
                  total: total,
                );
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bill copied to clipboard')),
                );
              },
              child: const Text('Copy text'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final profile =
                    AppStateManager.instance.userProfileNotifier.value;
                final cashier = profile.fullName.trim().isNotEmpty
                    ? profile.fullName.trim()
                    : 'Cashier';
                final member = customer.hasMembership
                    ? '${customer.membershipLabel}${customer.membershipId.isNotEmpty ? ' (${customer.membershipId})' : ''}'
                    : '';
                try {
                  await SalesReportPdf.instance.shareTaxInvoice(
                    pharmacyName: displayName,
                    address: 'Kathmandu, Nepal',
                    vatNumber: '',
                    billNo: billNo,
                    time: time,
                    cashier: cashier,
                    customerName: customer.name,
                    customerPhone: customer.phone,
                    membership: member,
                    lines: items
                        .map((item) => SaleLine(
                              medicineName: item.stock.medicineName,
                              quantity: item.quantity,
                              unitPrice:
                                  double.tryParse(item.stock.price) ?? 0,
                              lineTotal: item.lineTotal,
                            ))
                        .toList(),
                    discountPercent: 0,
                    vatPercent: 13,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('PDF failed: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('PDF Invoice'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Widget _billMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Edit Row (full original logic)
  // ─────────────────────────────────────────────

  Future<void> _editRow(OwnerStock row) async {
    final formKey = GlobalKey<FormState>(debugLabel: 'edit_stock_${row.id}');
    final quantityController =
        TextEditingController(text: row.quantity.toString());
    final priceController = TextEditingController(text: row.price);
    final thresholdController =
        TextEditingController(text: row.lowThreshold.toString());

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(row.medicineName),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    validator: validateQuantity,
                    decoration: const InputDecoration(
                      labelText: 'Quantity on shelf',
                      helperText: 'Enter the total count, not the change.',
                    ),
                  ),
                  TextFormField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    validator: validatePrice,
                    decoration: const InputDecoration(labelText: 'Price'),
                  ),
                  TextFormField(
                    controller: thresholdController,
                    keyboardType: TextInputType.number,
                    validator: validateLowThreshold,
                    decoration: const InputDecoration(
                      labelText: 'Alert me at or below',
                      helperText: 'Low-stock alerts fire at this count.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (saved != true || !mounted) return;

      final quantity = int.tryParse(quantityController.text.trim());
      final price = priceController.text.trim();
      final threshold = int.tryParse(thresholdController.text.trim());
      if (quantity == null) {
        setState(() => _rowErrors[row.id] = 'Quantity must be a whole number.');
        return;
      }

      setState(() => _rowErrors.remove(row.id));
      try {
        if (threshold != null && threshold != row.lowThreshold) {
          final updated = await OwnerStockService.instance
              .setLowThreshold(row.id, threshold);
          if (!mounted) return;
          setState(() => _replaceRow(updated));
        }
        if (quantity != row.quantity) {
          final updated =
              await OwnerStockService.instance.setQuantity(row.id, quantity);
          if (!mounted) return;
          setState(() => _replaceRow(updated));
        }
        if (priceHasChanged(row.price, price)) {
          final updated =
              await OwnerStockService.instance.setPrice(row.id, price);
          if (!mounted) return;
          setState(() => _replaceRow(updated));
        }
      } on ApiException catch (e) {
        if (!mounted) return;
        if (isSessionExpired(e)) {
          _leaveAsSignedOut();
          return;
        }
        if (isOwnershipRevoked(e)) {
          _leaveAsRevokedOwner();
          return;
        }
        setState(() => _rowErrors[row.id] = e.message);
      } catch (_) {
        if (!mounted) return;
        setState(() => _rowErrors[row.id] = _offlineMessage);
      }
    } finally {
      quantityController.dispose();
      priceController.dispose();
      thresholdController.dispose();
    }
  }

  // ─────────────────────────────────────────────
  // Add Medicine (full original logic)
  // ─────────────────────────────────────────────

  Future<void> _addMedicine() async {
    final formKey = GlobalKey<FormState>(debugLabel: 'add_medicine_form');
    final searchController = TextEditingController();
    final quantityController = TextEditingController(text: '0');
    final priceController = TextEditingController(text: '0.00');
    final thresholdController = TextEditingController();
    List<Map<String, dynamic>> results = [];
    int? selectedId;
    String? dialogError;
    bool searching = false;
    bool submitting = false;
    bool ownershipRevoked = false;
    bool sessionExpired = false;

    try {
      final added = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> runSearch(String value) async {
              setDialogState(() {
                searching = true;
                dialogError = null;
              });
              try {
                final found =
                    await PharmacyService.instance.searchMedicines(value.trim());
                if (!ctx.mounted) return;
                setDialogState(() {
                  results = found;
                  searching = false;
                  if (!found.any((m) => m['id'] == selectedId)) selectedId = null;
                });
              } catch (e) {
                if (!ctx.mounted) return;
                setDialogState(() {
                  searching = false;
                  dialogError = e is ApiException ? e.message : _offlineMessage;
                });
              }
            }

            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final quantity = int.tryParse(quantityController.text.trim());
              if (quantity == null) {
                setDialogState(
                    () => dialogError = 'Quantity must be a whole number.');
                return;
              }
              setDialogState(() {
                submitting = true;
                dialogError = null;
              });
              try {
                await OwnerStockService.instance.addMedicine(
                  medicineId: selectedId!,
                  quantity: quantity,
                  price: priceController.text.trim(),
                  lowThreshold: int.tryParse(thresholdController.text.trim()),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!ctx.mounted) return;
                if (isSessionExpired(e)) {
                  sessionExpired = true;
                  Navigator.pop(ctx, false);
                  return;
                }
                if (isOwnershipRevoked(e)) {
                  ownershipRevoked = true;
                  Navigator.pop(ctx, false);
                  return;
                }
                setDialogState(() {
                  submitting = false;
                  dialogError = e is ApiException ? e.message : _offlineMessage;
                });
              }
            }

            return AlertDialog(
              title: const Text('Add a medicine'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            labelText: 'Search the catalog',
                            helperText: 'Press enter to search.',
                          ),
                          onSubmitted: runSearch,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 160,
                          child: searching
                              ? const Center(child: CircularProgressIndicator())
                              : results.isEmpty
                                  ? const Center(
                                      child: Text('No medicines found yet.'))
                                  : ListView.builder(
                                      itemCount: results.length,
                                      itemBuilder: (context, index) {
                                        final medicine = results[index];
                                        final id = medicine['id'] as int;
                                        return RadioListTile<int>(
                                          value: id,
                                          groupValue: selectedId,
                                          title: Text('${medicine['name']}'),
                                          dense: true,
                                          onChanged: (value) => setDialogState(
                                              () => selectedId = value),
                                        );
                                      },
                                    ),
                        ),
                        TextFormField(
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          validator: validateQuantity,
                          decoration:
                              const InputDecoration(labelText: 'Quantity'),
                        ),
                        TextFormField(
                          controller: priceController,
                          keyboardType: TextInputType.number,
                          validator: validatePrice,
                          decoration: const InputDecoration(labelText: 'Price'),
                        ),
                        TextFormField(
                          controller: thresholdController,
                          keyboardType: TextInputType.number,
                          validator: validateLowThreshold,
                          decoration: const InputDecoration(
                            labelText: 'Alert me at or below (optional)',
                            helperText: 'Leave blank for the default of 10.',
                          ),
                        ),
                        if (dialogError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            dialogError!,
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      submitting ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      (selectedId == null || submitting) ? null : submit,
                  child: const Text('Add'),
                ),
              ],
            );
          },
        ),
      );

      if (!mounted) return;
      if (sessionExpired) {
        _leaveAsSignedOut();
        return;
      }
      if (ownershipRevoked) {
        _leaveAsRevokedOwner();
        return;
      }
      if (added == true) await _load();
    } finally {
      searchController.dispose();
      quantityController.dispose();
      priceController.dispose();
      thresholdController.dispose();
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _logout();
  }

  Future<void> _logout() async {
    final biometricOn = await BiometricService.instance.isEnabled;
    if (biometricOn) {
      final p = AppStateManager.instance.userProfileNotifier.value;
      await BiometricService.instance.saveUserSnapshot(profileToSnapshot(p));
    }
    await AuthService.instance.logout(keepBiometricSession: biometricOn);
    AppStateManager.instance.clearOwnerRole();
    AppStateManager.instance.setLoggedIn(false);
    if (!biometricOn) AppStateManager.instance.resetProfile();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────

  // Medicare-style green palette
  static const _posGreen = Color(0xFF0B6B4F);
  static const _posGreenLight = Color(0xFF0D9B6B);
  static const _posBg = Color(0xFFF4F7F6);
  static const _posCard = Colors.white;

  @override
  Widget build(BuildContext context) {
    final pharmacyName =
        AppStateManager.instance.ownedPharmacyNameNotifier.value;
    return Scaffold(
      backgroundColor: _posBg,
      appBar: AppBar(
        backgroundColor: _posGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_pharmacy, size: 22),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (pharmacyName.isEmpty ? 'PHARMACY POS' : pharmacyName)
                        .toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'OWNER DASHBOARD',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<UserProfile>(
            valueListenable: AppStateManager.instance.userProfileNotifier,
            builder: (context, profile, _) {
              return ValueListenableBuilder<String>(
                valueListenable: AppStateManager.instance.usernameNotifier,
                builder: (context, username, __) {
                  final fullName = profile.fullName.trim();
                  final displayName = fullName.isNotEmpty
                      ? fullName
                      : (username.trim().isNotEmpty ? username.trim() : 'Owner');
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, size: 8, color: Color(0xFF4ADE80)),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            displayName,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Main app',
            onPressed: () => Navigator.pushNamed(context, '/home'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _confirmLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.point_of_sale, size: 20), text: 'POS'),
            Tab(icon: Icon(Icons.inventory_2_outlined, size: 20), text: 'Stock'),
            Tab(icon: Icon(Icons.people_outline, size: 20), text: 'Customers'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 20), text: 'Activity'),
            Tab(icon: Icon(Icons.analytics_outlined, size: 20), text: 'Analytics'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_tabController.index != 1) return const SizedBox.shrink();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'import_excel',
                onPressed: _importStockFromExcel,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Excel/CSV'),
                backgroundColor: _posGreenLight,
                foregroundColor: Colors.white,
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'add_medicine',
                onPressed: _addMedicine,
                icon: const Icon(Icons.add),
                label: const Text('Add medicine'),
                backgroundColor: _posGreen,
                foregroundColor: Colors.white,
              ),
            ],
          );
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPosTab(),
          _buildStockTab(),
          _buildCustomersTab(),
          _buildActivityTab(),
          _buildAnalyticsTab(),
        ],
      ),
    );
  }

  Widget _buildPosTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Catalog ──
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search medicine, formula, or name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // Category chips
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: _categoryKeywords.keys.map((cat) {
                    final selected = cat == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat, style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? Colors.white : _posGreen,
                        )),
                        selected: selected,
                        selectedColor: _posGreen,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: selected ? _posGreen : Colors.grey.shade300),
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _filteredStock.isEmpty
                    ? const Center(child: Text('No medicines found', style: TextStyle(color: Colors.grey)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        gridDelegate: const
SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.92,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _filteredStock.length,
                        itemBuilder: (context, index) {
                          final item = _filteredStock[index];
                          final isLow = item.quantity <= item.lowThreshold;
                          final isOut = item.quantity <= 0;
                          return Material(
                            color: _posCard,
                            elevation: 1.5,
                            shadowColor: Colors.black12,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isOut ? null : () => _addToCart(item),
                              onLongPress: () => _editRow(item),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: _posGreen.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(Icons.medication_outlined,
                                              color: _posGreen, size: 20),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isOut
                                                ? Colors.red.shade50
                                                : isLow
                                                    ? const Color(0xFFFFF3CD)
                                                    : const Color(0xFFD1FAE5),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            isOut
                                                ? 'Out'
                                                : 'Stock: ${item.quantity}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isOut
                                                  ? Colors.red.shade700
                                                  : isLow
                                                      ? const Color(0xFF92400E)
                                                      : _posGreen,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      item.medicineName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isOut ? 'Unavailable' : 'In stock',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Rs ${item.price}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: _posGreen,
                                            ),
                                          ),
                                        ),
                                        if (!isOut)
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: _posGreen,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.add,
                                                color: Colors.white, size: 18),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        // ── Current Order panel ──
        Container(
          width: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(-2, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.shopping_bag_outlined, color: _posGreen, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Current Order',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                    if (_cart.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          _cart.clear();
                          _selectedCustomer = null;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Clear', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              // Customer chip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: InkWell(
                  onTap: _pickCustomerForBilling,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _posBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 18, color: _posGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _selectedCustomer == null
                              ? Text('Select customer',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_selectedCustomer!.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w700)),
                                    Text(
                                      _selectedCustomer!.hasMembership
                                          ? '${_selectedCustomer!.phone} · ${_selectedCustomer!.membershipLabel}'
                                          : _selectedCustomer!.phone,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                        ),
                        if (_selectedCustomer != null)
                          GestureDetector(
                            onTap: () => setState(() => _selectedCustomer = null),
                            child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                          )
                        else
                          Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: _cart.isEmpty
                    ? Center(
                        child: Text('Tap medicines to add',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _cart.length,
                        itemBuilder: (context, index) {
                          final item = _cart[index];
                          final unit = double.tryParse(item.stock.price) ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.stock.medicineName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600, fontSize: 13)),
                                      Text(
                                        'Rs ${unit.toStringAsFixed(0)} × ${item.quantity}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _qtyBtn(Icons.remove, () => _changeCartQty(item, -1)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text('${item.quantity}',
                                          style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                    _qtyBtn(Icons.add, () => _changeCartQty(item, 1)),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    'Rs ${item.lineTotal.toStringAsFixed(0)}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        Text('Rs ${_cartTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        Text(
                          'Rs ${_cartTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: _posGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _cart.isEmpty || _selling ? null : _completeSale,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _posGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: _selling
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.payments_outlined, size: 20),
                        label: Text(
                          _selling ? 'Processing...' : 'PROCESS PAYMENT',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: _posGreen),
      ),
    );
  }

  Widget _buildStockTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final query = _searchQuery;
    final rows = query.isEmpty
        ? _stock
        : _stock
            .where((s) => s.medicineName.toLowerCase().contains(query))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search stock...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '${rows.length} medicine${rows.length == 1 ? '' : 's'} in stock',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _importStockFromExcel,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import Excel/CSV'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _addMedicine,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: rows.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No stock yet.\nTap Add or Import Excel/CSV to load medicines.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      final isLow = item.quantity <= item.lowThreshold;
                      final isOut = item.quantity <= 0;
                      final err = _rowErrors[item.id];
                      return ListTile(
                        dense: true,
                        title: Text(
                          item.medicineName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          err ??
                              (isOut
                                  ? 'Out of stock · alert ≤ ${item.lowThreshold}'
                                  : isLow
                                      ? 'Low · Qty ${item.quantity} · alert ≤ ${item.lowThreshold}'
                                      : 'Qty ${item.quantity} · alert ≤ ${item.lowThreshold}'),
                          style: TextStyle(
                            fontSize: 12,
                            color: err != null || isOut || isLow
                                ? Theme.of(context).colorScheme.error
                                : Colors.grey.shade600,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Rs ${item.price}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Edit qty / price / alert',
                              onPressed: () => _editRow(item),
                            ),
                          ],
                        ),
                        onTap: () => _editRow(item),
                      );
                    },
                  ),
                ),
        ),
        const SizedBox(height: 72), // space for FABs
      ],
    );
  }

  /// Import stock by uploading an Excel (.xlsx) or CSV file.
  /// Expected columns (header row optional):
  ///   medicine_name, quantity, price, low_threshold
  Future<void> _importStockFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      withData: true, // needed on web; also works on mobile/desktop
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.single;
    final name = (file.name).toLowerCase();
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read the file. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String csvRaw;
    try {
      if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
        csvRaw = _excelBytesToCsv(bytes);
      } else {
        // CSV / text
        csvRaw = utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to read file: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (csvRaw.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is empty')),
      );
      return;
    }

    await _runCsvStockImport(csvRaw);
  }

  /// Convert first sheet of an .xlsx file into CSV text the importer understands.
  String _excelBytesToCsv(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return '';
    final sheet = excel.tables[excel.tables.keys.first]!;
    final buffer = StringBuffer();
    for (final row in sheet.rows) {
      final cells = row.map((cell) {
        if (cell == null || cell.value == null) return '';
        final v = cell.value;
        // Prefer numeric/text representation without type noise
        String s;
        try {
          s = (v as dynamic).toString().trim();
          // Strip TextCellValue("x") style if package toString is verbose
          if (s.startsWith('TextCellValue(') && s.endsWith(')')) {
            s = s.substring('TextCellValue('.length, s.length - 1);
            if (s.startsWith('"') && s.endsWith('"')) {
              s = s.substring(1, s.length - 1);
            }
          } else if (s.startsWith('IntCellValue(') && s.endsWith(')')) {
            s = s.substring('IntCellValue('.length, s.length - 1);
          } else if (s.startsWith('DoubleCellValue(') && s.endsWith(')')) {
            s = s.substring('DoubleCellValue('.length, s.length - 1);
          }
        } catch (_) {
          s = '$v'.trim();
        }
        if (s.contains(',') || s.contains('"') || s.contains('\n')) {
          return '"${s.replaceAll('"', '""')}"';
        }
        return s;
      }).toList();
      // Skip fully empty rows
      if (cells.every((c) => c.isEmpty)) continue;
      buffer.writeln(cells.join(','));
    }
    return buffer.toString();
  }

  Future<void> _runCsvStockImport(String raw) async {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to import')),
      );
      return;
    }

    // Detect header
    int start = 0;
    final firstLower = lines.first.toLowerCase();
    if (firstLower.contains('medicine') || firstLower.contains('name')) {
      start = 1;
    }

    int ok = 0;
    int failed = 0;
    final errors = <String>[];

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Importing stock...')),
          ],
        ),
      ),
    );

    try {
      for (var i = start; i < lines.length; i++) {
        final cols = _parseCsvLine(lines[i]);
        if (cols.isEmpty) continue;
        final name = cols[0].trim();
        if (name.isEmpty) continue;
        final qty = cols.length > 1 ? int.tryParse(cols[1].trim()) ?? 0 : 0;
        final price = cols.length > 2 ? cols[2].trim() : '0';
        final threshold =
            cols.length > 3 ? int.tryParse(cols[3].trim()) : null;

        try {
          // Prefer exact name already in THIS pharmacy's stock
          final existing = _stock.where((s) {
            return s.medicineName.toLowerCase() == name.toLowerCase();
          }).toList();

          if (existing.isNotEmpty) {
            final row = existing.first;
            if (qty != row.quantity) {
              await OwnerStockService.instance.setQuantity(row.id, qty);
            }
            if (priceHasChanged(row.price, price)) {
              await OwnerStockService.instance.setPrice(row.id, price);
            }
            if (threshold != null && threshold != row.lowThreshold) {
              await OwnerStockService.instance
                  .setLowThreshold(row.id, threshold);
            }
          } else {
            // Not in pharmacy stock yet:
            // 1) exact catalog match by full name → use id
            // 2) otherwise create NEW catalog entry with this exact name
            //    (Amoxicillin 250mg stays separate from Amoxicillin 500mg)
            final exact = await PharmacyService.instance.searchMedicines(name);
            Map<String, dynamic>? exactMatch;
            for (final m in exact) {
              final n = (m['name'] as String? ?? '').toLowerCase();
              if (n == name.toLowerCase()) {
                exactMatch = m;
                break;
              }
            }

            if (exactMatch != null) {
              await OwnerStockService.instance.addMedicine(
                medicineId: exactMatch['id'] as int,
                quantity: qty,
                price: price.isEmpty ? '0' : price,
                lowThreshold: threshold,
              );
            } else {
              await OwnerStockService.instance.addMedicineByName(
                medicineName: name,
                quantity: qty,
                price: price.isEmpty ? '0' : price,
                lowThreshold: threshold,
              );
            }
          }
          ok++;
        } catch (e) {
          failed++;
          errors.add(
              '$name — ${e is ApiException ? e.message : 'failed'}');
        }
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;
    await _load();
    if (!mounted) return;

    final msg = StringBuffer('Imported $ok row(s).');
    if (failed > 0) {
      msg.write(' $failed failed.');
      if (errors.isNotEmpty) {
        msg.write('\n${errors.take(5).join('\n')}');
        if (errors.length > 5) msg.write('\n…');
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.toString()),
        duration: Duration(seconds: failed > 0 ? 6 : 3),
        backgroundColor: failed > 0 ? Colors.orange.shade800 : null,
      ),
    );
  }

  /// Simple CSV line parser supporting quoted fields.
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          result.add(buf.toString());
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
    }
    result.add(buf.toString());
    return result;
  }

  Widget _buildCustomersTab() {
    if (_customersLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_customersError != null && _customers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_customersError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: _loadCustomers, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final list = _filteredCustomers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customerSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search customers...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _customerSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _customerSearchController.clear(),
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _createOrEditCustomer(),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('New'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadCustomers,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No customers yet.\nTap New to add one with membership.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadCustomers,
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = list[index];
                      final selected = _selectedCustomer?.id == c.id ||
                          (_selectedCustomer?.phone == c.phone &&
                              _selectedCustomer != null);
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: CircleAvatar(
                          radius: 18,
                          child: Text(
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          c.hasMembership
                              ? '${c.phone} · ${c.membershipLabel}${c.membershipId.isNotEmpty ? ' (${c.membershipId})' : ''}'
                              : c.phone,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (c.hasMembership)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Chip(
                                  label: Text(c.membershipLabel,
                                      style: const TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit',
                              onPressed: () =>
                                  _createOrEditCustomer(existing: c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              tooltip: 'Delete',
                              onPressed: () => _deleteCustomer(c),
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() => _selectedCustomer = c);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '${c.name} selected for billing'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildActivityTab() {
    if (_activityLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_activityError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_activityError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadTransactions, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayTx = _transactions.where((t) => !t.serverTimestamp.isBefore(todayStart)).toList();
    final todaySales = todayTx.where((t) => t.isDispense).toList();
    final todayUnits = todaySales.fold<int>(0, (s, t) => s + t.quantityDelta.abs());
    final todayRevenue = _estimateRevenue(todaySales);
    final todayRestock = todayTx.where((t) => !t.isDispense).length;

    return Column(
      children: [
        // Daily summary strip
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_posGreen, _posGreenLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Today's summary",
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _dayStat('Sales lines', '${todaySales.length}'),
                  _dayStat('Units sold', '$todayUnits'),
                  _dayStat('Est. revenue', 'Rs ${todayRevenue.toStringAsFixed(0)}'),
                  _dayStat('Restocks', '$todayRestock'),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showDayReport(todayStart),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Generate day report', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                'Full history (${_transactions.length})',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              TextButton(
                onPressed: _loadTransactions,
                child: const Text('Refresh', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _transactions.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadTransactions,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No stock movements yet.\nSales and restocks will appear here with time, user, and quantity.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTransactions,
                  child: ListView.separated(
                    itemCount: _transactions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _transactions[index];
                      final isDispense = entry.isDispense;
                      final price = _priceForMedicine(entry.medicineName);
                      final est = price * entry.quantityDelta.abs();
                      final who = entry.source == 'POS_SYNC'
                          ? 'POS terminal'
                          : (entry.changedByUsername ?? 'Manual');
                      final when = entry.serverTimestamp;
                      final timeStr =
                          '${when.day.toString().padLeft(2, '0')}/${when.month.toString().padLeft(2, '0')} '
                          '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        dense: true,
                        onTap: () => _showTransactionDetail(entry),
                        leading: CircleAvatar(
                          backgroundColor: (isDispense ? Colors.red : _posGreen)
                              .withValues(alpha: 0.12),
                          child: Icon(
                            isDispense ? Icons.shopping_cart_checkout : Icons.inventory,
                            color: isDispense ? Colors.red.shade700 : _posGreen,
                            size: 18,
                          ),
                        ),
                        title: Text(entry.medicineName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(
                          '${entry.transactionType} · by $who · $timeStr',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              entry.quantityDelta > 0
                                  ? '+${entry.quantityDelta}'
                                  : '${entry.quantityDelta}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: isDispense ? Colors.red.shade700 : _posGreen,
                              ),
                            ),
                            if (isDispense)
                              Text(
                                '≈ Rs ${est.toStringAsFixed(0)}',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _dayStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Future<void> _showTransactionDetail(StockTransactionEntry entry) async {
    final isDispense = entry.isDispense;
    final color = isDispense ? Colors.red.shade700 : _posGreen;
    final price = _priceForMedicine(entry.medicineName);
    final lineTotal = price * entry.quantityDelta.abs();
    final who = entry.source == 'POS_SYNC'
        ? 'POS terminal (auto-sync)'
        : (entry.changedByUsername ?? 'Manual entry');
    final when = entry.serverTimestamp;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final fullDate =
        '${weekdays[when.weekday - 1]}, ${when.day.toString().padLeft(2, '0')}/'
        '${when.month.toString().padLeft(2, '0')}/${when.year} at '
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}:'
        '${when.second.toString().padLeft(2, '0')}';

    // Current on-hand quantity for this medicine, if it's still stocked.
    OwnerStock? currentStock;
    for (final s in _stock) {
      if (s.medicineName.toLowerCase() == entry.medicineName.toLowerCase()) {
        currentStock = s;
        break;
      }
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 12,
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Icon(
                          isDispense
                              ? Icons.shopping_cart_checkout_rounded
                              : Icons.inventory_2_rounded,
                          color: color,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.medicineName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              entry.transactionType,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          entry.quantityDelta > 0
                              ? '+${entry.quantityDelta}'
                              : '${entry.quantityDelta}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close_rounded, color: Colors.grey.shade500),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                // Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      children: [
                        _detailRow(Icons.event_outlined, 'Date & time', fullDate),
                        _detailRow(Icons.person_outline, 'Performed by', who),
                        _detailRow(
                          Icons.sync_alt,
                          'Source',
                          entry.source == 'POS_SYNC'
                              ? 'POS sync'
                              : 'Manual (dashboard)',
                        ),
                        _detailRow(Icons.tag, 'Transaction ID', '#${entry.id}'),
                        _detailRow(
                          Icons.sell_outlined,
                          'Unit price',
                          'Rs ${price.toStringAsFixed(2)}',
                        ),
                        if (isDispense)
                          _detailRow(
                            Icons.payments_outlined,
                            'Line total (est.)',
                            'Rs ${lineTotal.toStringAsFixed(2)}',
                          ),
                        _detailRow(
                          Icons.inventory_2_outlined,
                          'Stock on hand now',
                          currentStock != null
                              ? '${currentStock.quantity} units'
                              : 'No longer stocked',
                        ),
                        if (currentStock != null)
                          _detailRow(
                            Icons.warning_amber_outlined,
                            'Low-stock alert level',
                            '${currentStock.lowThreshold} units',
                          ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _posBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isDispense
                                      ? 'This entry reduced shelf stock by ${entry.quantityDelta.abs()} unit(s), recorded by the source above.'
                                      : 'This entry added ${entry.quantityDelta.abs()} unit(s) back to shelf stock (restock/adjustment).',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade700,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  double _priceForMedicine(String name) {
    for (final s in _stock) {
      if (s.medicineName.toLowerCase() == name.toLowerCase()) {
        return double.tryParse(s.price) ?? 0;
      }
    }
    // fuzzy contains
    final lower = name.toLowerCase();
    for (final s in _stock) {
      if (s.medicineName.toLowerCase().contains(lower) ||
          lower.contains(s.medicineName.toLowerCase())) {
        return double.tryParse(s.price) ?? 0;
      }
    }
    return 0;
  }

  double _estimateRevenue(List<StockTransactionEntry> sales) {
    double total = 0;
    for (final t in sales) {
      total += _priceForMedicine(t.medicineName) * t.quantityDelta.abs();
    }
    return total;
  }

  Future<void> _showDayReport(DateTime dayStart) async {
    final pharmacy =
        AppStateManager.instance.ownedPharmacyNameNotifier.value;
    final dateStr =
        '${dayStart.day.toString().padLeft(2, '0')}/${dayStart.month.toString().padLeft(2, '0')}/${dayStart.year}';

    final sales = await OwnerSalesLog.instance.forDay(dayStart);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final dayTx = _transactions
        .where((t) =>
            !t.serverTimestamp.isBefore(dayStart) &&
            t.serverTimestamp.isBefore(dayEnd))
        .toList();
    final dispenseTx = dayTx.where((t) => t.isDispense).toList();

    // Stock-ledger totals for the day -- always populated from the server,
    // unlike the local completed-bills log below (which only knows about
    // sales checked out through this device's own POS tab).
    final stockRevenue = _estimateRevenue(dispenseTx);
    final stockUnits = dispenseTx.fold<int>(0, (s, t) => s + t.quantityDelta.abs());
    final medUnitsToday = <String, int>{};
    for (final t in dispenseTx) {
      medUnitsToday[t.medicineName] = (medUnitsToday[t.medicineName] ?? 0) + t.quantityDelta.abs();
    }
    final topMedsToday = medUnitsToday.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cashierUnitsToday = <String, int>{};
    final cashierRevenueToday = <String, double>{};
    for (final t in dispenseTx) {
      final who = t.changedByUsername ?? (t.source == 'POS_SYNC' ? 'POS' : 'Unknown');
      cashierUnitsToday[who] = (cashierUnitsToday[who] ?? 0) + t.quantityDelta.abs();
      cashierRevenueToday[who] =
          (cashierRevenueToday[who] ?? 0) + _priceForMedicine(t.medicineName) * t.quantityDelta.abs();
    }
    final cashierRevenueTodayRank = cashierRevenueToday.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 12,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_posGreen, _posGreenLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Generate Day Report',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_pharmacy_rounded,
                              size: 18, color: _posGreen),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pharmacy.isEmpty ? 'Pharmacy' : pharmacy,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Stats cards
                      Row(
                        children: [
                          Expanded(
                            child: _pdfStatCard(
                              icon: Icons.inventory_2_outlined,
                              label: 'Units sold',
                              value: '$stockUnits',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _pdfStatCard(
                              icon: Icons.payments_outlined,
                              label: 'Revenue',
                              value: 'Rs ${stockRevenue.toStringAsFixed(0)}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _pdfStatCard(
                              icon: Icons.receipt_long_outlined,
                              label: 'Dispense events',
                              value: '${dispenseTx.length}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _pdfStatCard(
                              icon: Icons.person_outline,
                              label: 'Bills with customer',
                              value: '${sales.length}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _posBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'PDF includes stock-ledger totals, units dispensed, cashier breakdown, and any completed bills (store name, bill time, customer details, medicines, amounts) logged on this device.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            try {
                              await SalesReportPdf.instance.shareDayReport(
                                pharmacyName: pharmacy,
                                dayStart: dayStart,
                                sales: sales,
                                stockRevenue: stockRevenue,
                                stockUnitsDispensed: stockUnits,
                                stockDispenseEvents: dispenseTx.length,
                                stockCashierRevenue: cashierRevenueTodayRank,
                                stockCashierUnits: cashierUnitsToday,
                                stockTopMedicines: topMedsToday,
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('PDF failed: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _posGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pdfStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _posGreen),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_activityLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // Last 7 days buckets
    final days = List.generate(7, (i) {
      final d = todayStart.subtract(Duration(days: 6 - i));
      return d;
    });
    final unitsPerDay = <DateTime, int>{};
    final revenuePerDay = <DateTime, double>{};
    for (final d in days) {
      unitsPerDay[d] = 0;
      revenuePerDay[d] = 0;
    }
    for (final t in _transactions) {
      if (!t.isDispense) continue;
      final day = DateTime(t.serverTimestamp.year, t.serverTimestamp.month, t.serverTimestamp.day);
      if (!unitsPerDay.containsKey(day)) continue;
      unitsPerDay[day] = unitsPerDay[day]! + t.quantityDelta.abs();
      revenuePerDay[day] = revenuePerDay[day]! +
          _priceForMedicine(t.medicineName) * t.quantityDelta.abs();
    }

    final todayUnits = unitsPerDay[todayStart] ?? 0;
    final todayRevenue = revenuePerDay[todayStart] ?? 0;
    final yesterday = todayStart.subtract(const Duration(days: 1));
    final yUnits = unitsPerDay[yesterday] ?? 0;
    final yRevenue = revenuePerDay[yesterday] ?? 0;

    // Cashiers ranking (all loaded history)
    final cashierUnits = <String, int>{};
    final cashierRevenue = <String, double>{};
    for (final t in _transactions.where((t) => t.isDispense)) {
      final who = t.changedByUsername ?? (t.source == 'POS_SYNC' ? 'POS' : 'Unknown');
      cashierUnits[who] = (cashierUnits[who] ?? 0) + t.quantityDelta.abs();
      cashierRevenue[who] = (cashierRevenue[who] ?? 0) +
          _priceForMedicine(t.medicineName) * t.quantityDelta.abs();
    }
    final cashierRank = cashierUnits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cashierRevenueRank = cashierRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Top medicines
    final medUnits = <String, int>{};
    final medRevenue = <String, double>{};
    for (final t in _transactions.where((t) => t.isDispense)) {
      medUnits[t.medicineName] = (medUnits[t.medicineName] ?? 0) + t.quantityDelta.abs();
      medRevenue[t.medicineName] = (medRevenue[t.medicineName] ?? 0) +
          _priceForMedicine(t.medicineName) * t.quantityDelta.abs();
    }
    final topMeds = medUnits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalStockRevenueAll =
        cashierRevenue.values.fold<double>(0, (a, b) => a + b);

    final maxDayUnits = unitsPerDay.values.fold<int>(1, (a, b) => a > b ? a : b);

    double pctChange(double cur, double prev) {
      if (prev == 0) return cur == 0 ? 0 : 100;
      return ((cur - prev) / prev) * 100;
    }

    final unitsChange = pctChange(todayUnits.toDouble(), yUnits.toDouble());
    final revChange = pctChange(todayRevenue, yRevenue);

    // Movement mix — dispensed vs restocked, across all loaded history.
    final dispenseUnits = _transactions
        .where((t) => t.isDispense)
        .fold<int>(0, (s, t) => s + t.quantityDelta.abs());
    final restockUnits = _transactions
        .where((t) => !t.isDispense)
        .fold<int>(0, (s, t) => s + t.quantityDelta.abs());

    // Sales activity by time of day (dispense events, all loaded history).
    final hourBuckets = List<int>.filled(4, 0);
    for (final t in _transactions.where((t) => t.isDispense)) {
      final h = t.serverTimestamp.hour;
      if (h >= 6 && h < 12) {
        hourBuckets[0]++;
      } else if (h >= 12 && h < 17) {
        hourBuckets[1]++;
      } else if (h >= 17 && h < 21) {
        hourBuckets[2]++;
      } else {
        hourBuckets[3]++;
      }
    }
    const hourLabels = ['Morning\n6–12', 'Afternoon\n12–5', 'Evening\n5–9', 'Night\n9–6'];
    final maxHourBucket = hourBuckets.fold<int>(1, (a, b) => a > b ? a : b);

    // Average revenue on days with sales, and the best day within the window.
    final activeDays = revenuePerDay.values.where((v) => v > 0).length;
    final avgDailyRevenue = activeDays == 0
        ? 0.0
        : revenuePerDay.values.fold<double>(0, (a, b) => a + b) / activeDays;
    DateTime bestDay = days.first;
    double bestDayRevenue = -1;
    for (final d in days) {
      final r = revenuePerDay[d] ?? 0;
      if (r > bestDayRevenue) {
        bestDayRevenue = r;
        bestDay = d;
      }
    }

    return RefreshIndicator(
      onRefresh: _loadTransactions,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Sales Analytics',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text('Based on actual stock movements from your pharmacy',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 16),

          // KPI cards
          Row(
            children: [
              Expanded(
                child: _kpiCard(
                  'Today units',
                  '$todayUnits',
                  unitsChange,
                  Icons.shopping_bag_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpiCard(
                  'Today revenue*',
                  'Rs ${todayRevenue.toStringAsFixed(0)}',
                  revChange,
                  Icons.payments_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '* Revenue estimated from current shelf prices × units dispensed.',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),

          // 7-day bar chart
          const Text('Last 7 days — units sold',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.map((d) {
                final u = unitsPerDay[d] ?? 0;
                final h = maxDayUnits == 0 ? 0.0 : (u / maxDayUnits) * 120;
                final isToday = d == todayStart;
                final label = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('$u', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: isToday ? _posGreen : Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        Container(
                          height: h.clamp(4, 120),
                          decoration: BoxDecoration(
                            color: isToday ? _posGreen : _posGreen.withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                              color: isToday ? _posGreen : Colors.grey.shade600,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Revenue row under chart
          Row(
            children: days.map((d) {
              final r = revenuePerDay[d] ?? 0;
              return Expanded(
                child: Text(
                  r == 0 ? '—' : r.toStringAsFixed(0),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
              );
            }).toList(),
          ),
          Text('Revenue (Rs) under each day',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),

          const SizedBox(height: 24),
          const Text('Revenue trend',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: _RevenueTrendPainter(
                days.map((d) => revenuePerDay[d] ?? 0).toList(),
                _posGreen,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: days.map((d) {
              final label = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
              return Expanded(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rs ${avgDailyRevenue.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      Text('Avg revenue / active day',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: Colors.grey.shade200),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bestDayRevenue <= 0
                            ? '—'
                            : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                                [bestDay.weekday - 1],
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      Text(
                        bestDayRevenue <= 0
                            ? 'Best day this week'
                            : 'Best day (Rs ${bestDayRevenue.toStringAsFixed(0)})',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text('Stock movement mix',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text('All loaded history — dispensed vs. restocked units',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    [dispenseUnits.toDouble(), restockUnits.toDouble()],
                    [Colors.red.shade400, _posGreenLight],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendRow(Colors.red.shade400, 'Dispensed', '$dispenseUnits units'),
                    const SizedBox(height: 10),
                    _legendRow(_posGreenLight, 'Restocked', '$restockUnits units'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Text('Sales activity by time of day',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          ...List.generate(4, (i) {
            final frac = maxHourBucket == 0 ? 0.0 : hourBuckets[i] / maxHourBucket;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(hourLabels[i],
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        color: _posGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 26,
                    child: Text('${hourBuckets[i]}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),
          const Text('Cashier / user ranking',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          if (cashierRank.isEmpty)
            Text('No sales recorded yet.',
                style: TextStyle(color: Colors.grey.shade600))
          else
            ...cashierRank.take(8).toList().asMap().entries.map((e) {
              final i = e.key;
              final name = e.value.key;
              final units = e.value.value;
              final rev = cashierRevenue[name] ?? 0;
              final maxU = cashierRank.first.value;
              final frac = maxU == 0 ? 0.0 : units / maxU;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: i == 0 ? _posGreen : Colors.grey.shade300,
                          child: Text('${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: i == 0 ? Colors.white : Colors.black87,
                              )),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                        Text('$units units · Rs ${rev.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        color: i == 0 ? _posGreen : _posGreenLight,
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 20),
          const Text('Top selling medicines',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          if (topMeds.isEmpty)
            Text('No sales yet.', style: TextStyle(color: Colors.grey.shade600))
          else
            ...topMeds.take(8).map((e) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.medication_outlined, color: _posGreen),
                title: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                trailing: Text('${e.value} units',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: _posGreen)),
              );
            }),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _showDayReport(todayStart),
            icon: const Icon(Icons.description_outlined),
            label: const Text("Today's day report (PDF)"),
            style: OutlinedButton.styleFrom(foregroundColor: _posGreen),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              final pharmacy =
                  AppStateManager.instance.ownedPharmacyNameNotifier.value;
              final all = await OwnerSalesLog.instance.loadAll();
              if (!mounted) return;
              try {
                await SalesReportPdf.instance.shareAnalyticsReport(
                  pharmacyName: pharmacy,
                  sales: all,
                  generatedAt: DateTime.now(),
                  stockRevenue: totalStockRevenueAll,
                  stockUnits: dispenseUnits,
                  stockCashierRevenue: cashierRevenueRank,
                  stockTopMedicines: topMeds,
                  stockMedicineRevenue: medRevenue,
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('PDF failed: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('Full analytics PDF'),
            style: FilledButton.styleFrom(backgroundColor: _posGreen),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, String value) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _kpiCard(String label, String value, double changePct, IconData icon) {
    final up = changePct >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _posGreen),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: up ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${up ? '+' : ''}${changePct.toStringAsFixed(0)}% vs yday',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: up ? _posGreen : Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }


}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});
  final StockTransactionEntry entry;

  static String _relativeTime(DateTime timestamp) {
    final delta = DateTime.now().difference(timestamp);
    if (delta.inSeconds < 60) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) {
      return '${delta.inHours} hour${delta.inHours == 1 ? '' : 's'} ago';
    }
    if (delta.inDays < 7) {
      return '${delta.inDays} day${delta.inDays == 1 ? '' : 's'} ago';
    }
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  String get _attribution {
    if (entry.source == 'POS_SYNC') return 'POS';
    return entry.changedByUsername ?? 'Manual';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDispense = entry.isDispense;
    final deltaColor =
        isDispense ? theme.colorScheme.error : theme.colorScheme.primary;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: deltaColor.withValues(alpha: 0.12),
        child: Icon(
          isDispense ? Icons.arrow_downward : Icons.arrow_upward,
          color: deltaColor,
          size: 20,
        ),
      ),
      title: Text(entry.medicineName,
          style: theme.textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Text(
        '${entry.transactionType.toLowerCase()} · $_attribution · ${_relativeTime(entry.serverTimestamp)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        entry.quantityDelta > 0
            ? '+${entry.quantityDelta}'
            : '${entry.quantityDelta}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: deltaColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
/// Smooth revenue-trend sparkline used at the top of the Analytics tab.
class _RevenueTrendPainter extends CustomPainter {
  _RevenueTrendPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1.0 : maxV;
    final n = values.length;
    final stepX = n > 1 ? size.width / (n - 1) : size.width;

    final points = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          n > 1 ? i * stepX : size.width / 2,
          size.height - (values[i] / safeMax) * (size.height - 6) - 3,
        ),
    ];

    if (maxV <= 0) {
      // Flat baseline when there is no data yet, so the chart isn't blank.
      final flatPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final y = size.height - 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), flatPaint);
      return;
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final midX = (prev.dx + cur.dx) / 2;
      linePath.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
    }

    final fillPath = Path()
      ..addPath(linePath, Offset.zero)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final dotFill = Paint()..color = color;
    final dotRing = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final p in points) {
      canvas.drawCircle(p, 3.2, dotFill);
      canvas.drawCircle(p, 3.2, dotRing);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueTrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// Simple ring/donut chart for a small set of proportions (e.g. dispensed vs
/// restocked units). Draws a grey ring when there is no data yet.
class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter(this.values, this.colors);

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 16.0;
    final ringRect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    if (total <= 0) {
      final emptyPaint = Paint()
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(ringRect, 0, 2 * math.pi, false, emptyPaint);
      return;
    }

    double startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = (values[i] / total) * 2 * math.pi;
      final segmentPaint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(ringRect, startAngle, sweep, false, segmentPaint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}

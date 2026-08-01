import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/owner_stock_service.dart';
import '../services/pharmacy_service.dart';
import '../state.dart';

/// True when [edited] denotes a different price from [current].
///
/// Pulled out as a pure top-level function -- same reasoning as
/// parseStockPayload in owner_stock_service.dart -- because it is the one
/// piece of this screen that is worth testing without a device.
///
/// The comparison MUST be numeric. Price crosses the wire as a string: DRF
/// renders PharmacyMedicineStock.price (a DecimalField) as "10.50", and
/// OwnerStock.price keeps it as a string rather than guessing a precision.
/// A naive `edited != current` therefore reports a change whenever the two
/// sides merely spell the same number differently -- an owner who opens the
/// dialog on "10.50", types "10.5", and saves would fire a PATCH that changes
/// nothing, and the same mismatch in reverse ("10.5" from the server against
/// an untouched "10.50" field) fires one on a dialog the owner only looked at.
/// Those phantom writes are not free: every write is an owner-audited call.
///
/// Falls back to a trimmed string compare when either side will not parse, so
/// a value this function does not understand is still passed through to the
/// server for it to accept or reject, rather than being silently dropped.
bool priceHasChanged(String current, String edited) {
  final a = num.tryParse(current.trim());
  final b = num.tryParse(edited.trim());
  if (a != null && b != null) return a != b;
  return current.trim() != edited.trim();
}

/// Validates the quantity field. Returns null when valid, else the message to
/// show under the field.
///
/// This exists so a non-numeric entry is refused at the dialog instead of
/// being swallowed: `int.tryParse(...)` followed by `if (value != null)` would
/// close the dialog, write nothing, and tell the owner nothing.
String? validateQuantity(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Enter a quantity.';
  final value = int.tryParse(text);
  if (value == null) return 'Enter a whole number, e.g. 12.';
  if (value < 0) return 'Quantity cannot be negative.';
  return null;
}

/// Validates the price field. Returns null when valid, else the message.
String? validatePrice(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Enter a price.';
  final value = num.tryParse(text);
  if (value == null) return 'Enter an amount, e.g. 10.50.';
  if (value < 0) return 'Price cannot be negative.';
  return null;
}

/// The pharmacy owner's stock editor -- the only human-facing write path to
/// PharmacyMedicineStock. Reached from login when the account is linked to a
/// pharmacy (see routeForRole in login_screen.dart).
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  List<OwnerStock> _stock = [];
  bool _loading = true;
  String? _error;
  // Per-row inline errors, keyed by stock id, so one rejected edit doesn't
  // replace the whole list with an error screen.
  final Map<int, String> _rowErrors = {};

  // Shown when the network, rather than the server, is the problem. Reused by
  // every handler so a dropped connection never produces silence.
  static const _offlineMessage =
      'Could not reach the server. Check your connection and try again.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
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
      // 403 means the owner link was removed while this session was open.
      // Drop back to the normal app rather than looping on an error.
      if (e.statusCode == 403) {
        AppStateManager.instance.clearOwnerRole();
        Navigator.pushReplacementNamed(context, '/home');
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      // Also catches the StateError parseStockPayload throws if the endpoint
      // ever starts paginating. Calling that a connection problem is not
      // strictly accurate, but it is a shape this client cannot serve and the
      // owner's only useful action is still Retry.
      if (!mounted) return;
      setState(() {
        _error = _offlineMessage;
        _loading = false;
      });
    }
  }

  Future<void> _editRow(OwnerStock row) async {
    final formKey = GlobalKey<FormState>();
    final quantityController =
        TextEditingController(text: row.quantity.toString());
    final priceController = TextEditingController(text: row.price);

    // Everything that reads these controllers lives inside the try, and the
    // finally runs only after `await showDialog` has completed -- disposing
    // any earlier would blow up in the dialog's own teardown, which still
    // touches the controllers its TextFormFields are attached to.
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
              // Refuses to close on invalid input rather than closing and
              // quietly doing nothing.
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
      if (quantity == null) {
        // Unreachable while the validator above is in place; kept so a future
        // edit to the dialog cannot reintroduce a silent no-op.
        setState(() => _rowErrors[row.id] = 'Quantity must be a whole number.');
        return;
      }

      setState(() => _rowErrors.remove(row.id));
      try {
        OwnerStock updated = row;
        // Two calls rather than one, because a quantity change goes through
        // the ledger and a price change doesn't -- keeping them separate means
        // a price correction never writes a phantom stock adjustment.
        if (quantity != row.quantity) {
          updated = await OwnerStockService.instance.setQuantity(row.id, quantity);
        }
        if (priceHasChanged(row.price, price)) {
          updated = await OwnerStockService.instance.setPrice(row.id, price);
        }
        if (!mounted) return;
        setState(() {
          final index = _stock.indexWhere((s) => s.id == row.id);
          if (index != -1) _stock[index] = updated;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        // Leave the old values on screen -- the write didn't happen.
        setState(() => _rowErrors[row.id] = e.message);
      } catch (_) {
        // A dropped connection throws SocketException, not ApiException.
        // Without this the failure escapes as an unhandled async error and
        // the row just never updates.
        if (!mounted) return;
        setState(() => _rowErrors[row.id] = _offlineMessage);
      }
    } finally {
      quantityController.dispose();
      priceController.dispose();
    }
  }

  Future<void> _removeRow(OwnerStock row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove medicine'),
        content: Text(
          'Remove ${row.medicineName} from your stock list? '
          'This says your pharmacy no longer carries it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await OwnerStockService.instance.removeStock(row.id);
      if (!mounted) return;
      setState(() => _stock.removeWhere((s) => s.id == row.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _rowErrors[row.id] = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _rowErrors[row.id] = _offlineMessage);
    }
  }

  Future<void> _addMedicine() async {
    final formKey = GlobalKey<FormState>();
    final searchController = TextEditingController();
    final quantityController = TextEditingController(text: '0');
    final priceController = TextEditingController(text: '0.00');
    List<Map<String, dynamic>> results = [];
    int? selectedId;
    String? dialogError;
    bool searching = false;
    bool submitting = false;

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
                  // The old selection may not be in the new result set.
                  if (!found.any((m) => m['id'] == selectedId)) selectedId = null;
                });
              } catch (e) {
                // Deliberately not `on ApiException` only -- a search run with
                // no connection would otherwise leave the dialog spinning
                // with no explanation.
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
                setDialogState(() => dialogError = 'Quantity must be a whole number.');
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
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!ctx.mounted) return;
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
                                      child: Text('No medicines found yet.'),
                                    )
                                  // RadioGroup rather than the RadioListTile
                                  // groupValue/onChanged pair, which is
                                  // deprecated as of Flutter 3.32.
                                  : RadioGroup<int>(
                                      groupValue: selectedId,
                                      onChanged: (value) =>
                                          setDialogState(() => selectedId = value),
                                      // .builder, not a mapped children list:
                                      // only the visible rows get built.
                                      child: ListView.builder(
                                        itemCount: results.length,
                                        itemBuilder: (context, index) {
                                          final medicine = results[index];
                                          return RadioListTile<int>(
                                            value: medicine['id'] as int,
                                            title: Text('${medicine['name']}'),
                                          );
                                        },
                                      ),
                                    ),
                        ),
                        TextFormField(
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          validator: validateQuantity,
                          decoration: const InputDecoration(labelText: 'Quantity'),
                        ),
                        TextFormField(
                          controller: priceController,
                          keyboardType: TextInputType.number,
                          validator: validatePrice,
                          decoration: const InputDecoration(labelText: 'Price'),
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

      if (added == true) await _load();
    } finally {
      searchController.dispose();
      quantityController.dispose();
      priceController.dispose();
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _logout();
  }

  /// Mirrors the drawer logout in home_screen.dart. Owners never enter
  /// AppShell -- login sends them here with pushReplacementNamed -- so without
  /// this handler clearOwnerRole() is unreachable for every owner account.
  ///
  /// THE ORDER BELOW IS LOAD-BEARING. profileToSnapshot() reads
  /// isPharmacyOwnerNotifier / ownedPharmacyId / ownedPharmacyName straight off
  /// AppStateManager (state.dart:347-349), so the biometric snapshot has to be
  /// written BEFORE clearOwnerRole() wipes them. Clearing first would persist a
  /// snapshot saying isPharmacyOwner: false, and the owner's next fingerprint
  /// login would restore them as a plain consumer -- permanently, because the
  /// bad snapshot then survives every subsequent logout.
  Future<void> _logout() async {
    final biometricOn = await BiometricService.instance.isEnabled;

    if (biometricOn) {
      final p = AppStateManager.instance.userProfileNotifier.value;
      await BiometricService.instance.saveUserSnapshot(profileToSnapshot(p));
    }

    await AuthService.instance.logout(keepBiometricSession: biometricOn);

    AppStateManager.instance.clearOwnerRole();
    AppStateManager.instance.setLoggedIn(false);
    if (!biometricOn) {
      AppStateManager.instance.resetProfile();
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<String>(
          valueListenable: AppStateManager.instance.ownedPharmacyNameNotifier,
          builder: (context, name, _) => Text(name.isEmpty ? 'My Pharmacy' : name),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Open the main app',
            onPressed: () => Navigator.pushNamed(context, '/home'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMedicine,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_stock.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No medicines yet. Use "Add medicine" to start your stock list.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      // .builder because /my-pharmacy/stock/ does not paginate: owner_views.py
      // list() hands back every row a pharmacy stocks, so the render cost has
      // to stay bounded even when the payload isn't.
      child: ListView.builder(
        itemCount: _stock.length,
        itemBuilder: (context, index) {
          final row = _stock[index];
          final rowError = _rowErrors[row.id];
          return ListTile(
            title: Text(row.medicineName),
            subtitle: Text(
              rowError ?? 'Qty ${row.quantity}  ·  Rs ${row.price}',
              style: rowError != null ? TextStyle(color: theme.colorScheme.error) : null,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit quantity and price',
                  onPressed: () => _editRow(row),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () => _removeRow(row),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

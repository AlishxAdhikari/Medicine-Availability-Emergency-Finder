import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/owner_stock_service.dart';
import '../services/pharmacy_service.dart';
import '../services/stock_alert_service.dart';
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

/// True when [error] says the caller is no longer this pharmacy's owner.
///
/// IsPharmacyOwner (backend/pharmacy/permissions.py) denies EVERY method on
/// OwnerStockViewSet, not just list(), so any call in this screen can come
/// back 403 the moment an admin unlinks the PharmacyOwner row. Treating that
/// as an ordinary row error would strand the owner on a dashboard of stale
/// stock with isPharmacyOwnerNotifier still true and every action failing the
/// same way. Extracted as a pure predicate so the four call sites agree and
/// so it can be tested without a device.
bool isOwnershipRevoked(Object error) =>
    error is ApiException && error.statusCode == 403;

/// True when [error] says this session is over.
///
/// ApiClient only lets a 401 reach a caller after it has already tried the
/// refresh token once and failed, at which point it deletes both tokens
/// (api_client.dart's _handleResponse). So by the time this returns true there
/// is no credential left on the device and no request will ever succeed again
/// -- which is why it cannot be treated as an ordinary row error like the
/// others here. Left as one, the owner sat on a dashboard of stale stock
/// tapping a Retry button that could not work, with no logged-out state to tell
/// them why. Separate from [isOwnershipRevoked] because the destination
/// differs: a revoked owner is still signed in and goes to /home, an expired
/// session goes back to the login screen.
bool isSessionExpired(Object error) =>
    error is ApiException && error.statusCode == 401;

/// Validates the low-stock threshold field. Returns null when valid, else the
/// message to show under the field.
///
/// Blank is allowed and means "leave it as it is" -- on the add dialog the
/// server applies its own default of 10, and on the edit dialog the field is
/// pre-filled, so an owner who clears it is not asking for zero. Zero itself is
/// valid and means "only alert me when it runs out".
String? validateLowThreshold(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final value = int.tryParse(text);
  if (value == null) return 'Enter a whole number, e.g. 10.';
  if (value < 0) return 'The alert level cannot be negative.';
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

  // The stock ledger behind the "Activity" tab. Loaded separately from _stock
  // so a failure on one tab never blanks the other -- the stock list is what
  // the owner actually works in, and it must not disappear because an audit
  // feed could not be fetched.
  List<StockTransactionEntry> _transactions = [];
  bool _activityLoading = true;
  String? _activityError;
  // Per-row inline errors, keyed by stock id, so one rejected edit doesn't
  // replace the whole list with an error screen.
  final Map<int, String> _rowErrors = {};

  // Shown when the network, rather than the server, is the problem. Reused by
  // every handler so a dropped connection never produces silence.
  static const _offlineMessage =
      'Could not reach the server. Check your connection and try again.';

  // Live low-stock feed for this owner's own pharmacy. The POS sells stock all
  // day without touching this app, so without the socket the dashboard is only
  // ever as current as the last pull-to-refresh -- and the one screen that
  // most needs to know a medicine just ran out was the only one not listening.
  final StockAlertService _alertService = StockAlertService();
  StreamSubscription<StockAlert>? _alertSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _loadTransactions();
    _subscribeToAlerts();
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _alertService.disconnect();
    super.dispose();
  }

  /// Opens the socket for the pharmacy this account owns. Silent on failure:
  /// live updates are an enhancement over the list that _load() already
  /// fetched, so a socket that will not open must not produce an error screen
  /// over working data.
  Future<void> _subscribeToAlerts() async {
    final pharmacyId = AppStateManager.instance.ownedPharmacyIdNotifier.value;
    // Null when an older backend sent no `pharmacy` on the login response, or
    // when a biometric snapshot predates that field.
    if (pharmacyId == null) return;

    try {
      final stream = await _alertService.connect(pharmacyId);
      if (!mounted) {
        // Disposed during connect(); nothing would ever close this socket.
        _alertService.disconnect();
        return;
      }
      _alertSubscription = stream.listen(_onStockAlert);
    } catch (_) {
      // No socket, no live updates. The dashboard still works.
    }
  }

  void _onStockAlert(StockAlert alert) {
    if (!mounted) return;
    setState(() {
      // The alert carries the server's committed quantity, so trust it over
      // the row we are holding -- that is the entire point of the socket.
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

    // An alert means stock just moved, so the ledger has a new row. Refetching
    // is event-driven rather than polled, but note it only covers movements
    // that crossed the low-stock threshold: sync/signals.py raises an alert
    // from check_threshold(), not on every transaction. Ordinary sales above
    // the threshold reach the feed on the next pull-to-refresh or tab switch.
    // Making every sale appear the instant it happens needs the server to
    // broadcast all transactions, not just threshold crossings.
    _loadTransactions();

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

  /// Demote to a plain consumer and leave. Called from every path that can
  /// see a 403 -- see isOwnershipRevoked. Callers MUST have checked `mounted`
  /// immediately before, because this touches State.context, and callers
  /// inside a dialog MUST have dismissed the dialog first, or the
  /// pushReplacement lands under a route that is still on top.
  void _leaveAsRevokedOwner() {
    AppStateManager.instance.clearOwnerRole();
    Navigator.pushReplacementNamed(context, '/home');
  }

  /// Drop back to the login screen because the session is gone -- see
  /// [isSessionExpired]. Same caller contract as [_leaveAsRevokedOwner]:
  /// `mounted` checked immediately before, any dialog dismissed first.
  ///
  /// The role and the logged-in flag are both cleared, because ApiClient has
  /// already discarded the tokens: leaving isLoggedIn true would leave the app
  /// claiming a session that no longer exists anywhere. The stack goes with it,
  /// for the same reason logout clears it -- nothing behind this screen is
  /// usable without a token.
  void _leaveAsSignedOut() {
    AppStateManager.instance.clearOwnerRole();
    AppStateManager.instance.setLoggedIn(false);
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  /// Swaps a server response into the list in place. Must be called inside a
  /// setState. No-ops if the row has since left the list.
  void _replaceRow(OwnerStock updated) {
    final index = _stock.indexWhere((s) => s.id == updated.id);
    if (index != -1) _stock[index] = updated;
  }

  Future<void> _load() async {
    // Guarded like every other setState in this file: _load is called from
    // initState, from Retry, from pull-to-refresh and from _addMedicine after
    // an await, and the last of those can outlive the screen.
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      // Row errors describe the state we are about to replace. Leaving them
      // would keep a stale message on a row whose real quantity and price the
      // refresh just fetched.
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
      // 401 means the refresh already failed and the tokens are gone; there is
      // nothing to retry with, so send them to login instead of an error card.
      if (isSessionExpired(e)) {
        _leaveAsSignedOut();
        return;
      }
      // 403 means the owner link was removed while this session was open.
      // Drop back to the normal app rather than looping on an error.
      if (isOwnershipRevoked(e)) {
        _leaveAsRevokedOwner();
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on StateError {
      // parseStockPayload refusing a truncated page. Retry cannot fix it, so
      // saying "check your connection" sends the owner to look at the one
      // thing that is not wrong -- and the stock list they are being shown is
      // incomplete, which is the part they need to know.
      if (!mounted) return;
      setState(() {
        _error = 'Your stock list is too long for this version of the app to '
            'show safely. Some medicines would be missing, so nothing is '
            'shown. Please update the app.';
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

  /// Fetches the stock ledger for the Activity tab.
  ///
  /// Deliberately never sets [_error]: that field drives the whole-screen
  /// error state for the stock list. A failure here is confined to
  /// [_activityError] so the owner keeps working in a dashboard whose audit
  /// tab happens to be unavailable.
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
      // Session and ownership handling matches _load(): these are conditions
      // of the whole session, not of this one request, so they still route
      // away from the screen rather than showing a per-tab error.
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

  Future<void> _editRow(OwnerStock row) async {
    final formKey = GlobalKey<FormState>();
    final quantityController =
        TextEditingController(text: row.quantity.toString());
    final priceController = TextEditingController(text: row.price);
    final thresholdController =
        TextEditingController(text: row.lowThreshold.toString());

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
      // Null when left blank, which means "unchanged" -- see
      // validateLowThreshold. tryParse is safe here for the same reason it is
      // for quantity: the validator has already refused anything unparseable.
      final threshold = int.tryParse(thresholdController.text.trim());
      if (quantity == null) {
        // Unreachable while the validator above is in place; kept so a future
        // edit to the dialog cannot reintroduce a silent no-op.
        setState(() => _rowErrors[row.id] = 'Quantity must be a whole number.');
        return;
      }

      setState(() => _rowErrors.remove(row.id));
      try {
        // Two calls rather than one, because a quantity change goes through
        // the ledger and a price change doesn't -- keeping them separate means
        // a price correction never writes a phantom stock adjustment.
        //
        // Each response is committed to _stock AS IT ARRIVES, never batched to
        // the end. If setQuantity succeeds and setPrice then fails on a
        // dropped connection, the server has already recorded the new quantity
        // and written an ADJUSTED StockTransaction for it. Holding the old row
        // on screen would tell the owner nothing was written, and -- worse --
        // the retry would compare the new quantity against the stale row,
        // decide it still differs, and fire setQuantity a SECOND time, adding
        // a delta-0 ADJUSTED row to the ledger this feature exists to keep
        // honest. Committing per call keeps the displayed row exactly as
        // server-authoritative as the calls that actually returned.
        // Threshold before quantity, matching the order owner_views.py applies
        // them in: the alert that a quantity drop may raise is judged against
        // whatever threshold the row holds at that moment, so sending the new
        // threshold second would have the server test the old one.
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
        // Both of these leave the screen; the dialog is already closed by this
        // point -- this catch sits after the `await showDialog` -- so
        // State.context is on top.
        if (isSessionExpired(e)) {
          _leaveAsSignedOut();
          return;
        }
        if (isOwnershipRevoked(e)) {
          _leaveAsRevokedOwner();
          return;
        }
        // Leave whatever did commit on screen; only the failed call is undone.
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
      thresholdController.dispose();
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
      setState(() {
        _stock.removeWhere((s) => s.id == row.id);
        _rowErrors.remove(row.id);
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
      _setRemoveError(row.id, e.message);
    } catch (_) {
      if (!mounted) return;
      _setRemoveError(row.id, _offlineMessage);
    }
  }

  /// A remove failure only has somewhere to show itself if the row is still
  /// in the list. Double-tap Remove and the second DELETE 404s against a row
  /// the first one already removed; writing _rowErrors[row.id] then would
  /// leave an entry no ListTile ever reads -- invisible to the owner and
  /// resurrected if that id ever came back. Drop it instead.
  void _setRemoveError(int rowId, String message) {
    if (!_stock.any((s) => s.id == rowId)) return;
    setState(() => _rowErrors[rowId] = message);
  }

  Future<void> _addMedicine() async {
    final formKey = GlobalKey<FormState>();
    final searchController = TextEditingController();
    final quantityController = TextEditingController(text: '0');
    final priceController = TextEditingController(text: '0.00');
    // Left empty on purpose: blank sends no low_threshold at all and lets the
    // server's default stand, rather than this screen hard-coding a copy of it.
    final thresholdController = TextEditingController();
    List<Map<String, dynamic>> results = [];
    int? selectedId;
    String? dialogError;
    bool searching = false;
    bool submitting = false;
    // Set by submit() when the POST comes back 403. The demote-and-leave has
    // to happen from out here, after `await showDialog` returns: navigating
    // from inside the dialog would push /home underneath a route that is
    // still on top, and State.mounted (not ctx.mounted) is the right guard
    // for the State.context that pushReplacementNamed needs.
    bool ownershipRevoked = false;
    // Same deferral, for the same reason: an expired session has to leave from
    // out here, after the dialog is gone.
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
                  // The old selection may not be in the new result set.
                  if (!found.any((m) => m['id'] == selectedId)) selectedId = null;
                });
              } catch (e) {
                // No isOwnershipRevoked branch here, unlike every other
                // handler in this file: searchMedicines hits /medicines/,
                // which is a ReadOnlyModelViewSet with
                // permission_classes = [AllowAny] (pharmacy/views.py:15-20)
                // and is called without auth, so IsPharmacyOwner never runs
                // on it and a 403 is not reachable. A 403 from an unrelated
                // future cause should stay an in-dialog message, not eject
                // the owner from a dashboard whose own API still works.
                //
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
                  lowThreshold:
                      int.tryParse(thresholdController.text.trim()),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!ctx.mounted) return;
                if (isSessionExpired(e)) {
                  // Close the dialog and let the caller navigate.
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
    // Matches the drawer logout in home_screen.dart: clear the stack rather
    // than replace one route, so nothing an owner opened on the way here can
    // be reached with the back button after the tokens are gone.
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // DefaultTabController rather than a TabController field: nothing outside
    // build() needs to drive or read the tab index, so the extra State
    // plumbing and its dispose() would buy nothing.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Stock'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Activity'),
            ],
          ),
        ),
        // Shown on both tabs. Adding a medicine is a reasonable thing to want
        // while reading the ledger, and hiding it would mean listening to the
        // tab index purely to take a button away.
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addMedicine,
          icon: const Icon(Icons.add),
          label: const Text('Add medicine'),
        ),
        body: TabBarView(
          children: [
            _buildBody(theme),
            _buildActivity(theme),
          ],
        ),
      ),
    );
  }

  /// The stock ledger: what was dispensed, restocked or adjusted, newest
  /// first. The rows come from StockTransaction, which the backend has always
  /// written on every stock change but never exposed until now.
  Widget _buildActivity(ThemeData theme) {
    if (_activityLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activityError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_activityError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadTransactions,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_transactions.isEmpty) {
      // AlwaysScrollableScrollPhysics so pull-to-refresh still works on an
      // empty list -- otherwise there is nothing to drag and the owner cannot
      // recheck without leaving the screen.
      return RefreshIndicator(
        onRefresh: _loadTransactions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'No stock movements yet. Sales and restocks will appear here as '
                'they happen.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTransactions,
      child: ListView.separated(
        itemCount: _transactions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _ActivityRow(entry: _transactions[index]),
      ),
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
          // Derived from the row rather than remembered from the alert that
          // announced it: the same condition the server tests (signals.py uses
          // quantity > low_threshold to mean "fine"), so it stays right after
          // an edit, a refresh, or a threshold change, with no second copy of
          // the state to keep in step.
          final isLow = row.quantity <= row.lowThreshold;
          return ListTile(
            isThreeLine: rowError != null,
            leading: isLow
                ? Icon(
                    row.quantity == 0
                        ? Icons.error_outline
                        : Icons.warning_amber_outlined,
                    color: theme.colorScheme.error,
                  )
                : null,
            title: Text(row.medicineName),
            // The error is shown IN ADDITION to the quantity and price, never
            // instead of them. Replacing them hid the only copy of the row's
            // data on screen at exactly the moment the owner needs it: after
            // a rejected edit, deciding whether to retry means knowing what
            // the server currently holds.
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Qty ${row.quantity}  ·  Rs ${row.price}'
                  '  ·  alert ≤ ${row.lowThreshold}',
                ),
                if (rowError != null)
                  Text(
                    rowError,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
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

/// One line of the stock ledger.
///
/// Reads at a glance as "what happened, to what, how much, when": the sign of
/// the delta is carried by both colour and an explicit +/- so it does not rely
/// on colour alone, which would be invisible to a colour-blind owner and in
/// bright sunlight.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final StockTransactionEntry entry;

  /// "2 minutes ago" beats a wall-clock time for a feed whose whole point is
  /// recency -- the owner cares that a sale just happened, not that it was
  /// 14:32. Falls back to a date once relative time stops being useful.
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
    final d = timestamp;
    return '${d.day}/${d.month}/${d.year}';
  }

  /// Who or what made the change. changed_by is null for POS_SYNC rows, which
  /// authenticate with a pharmacy-wide key and have no user behind them, so
  /// the source is named instead of leaving a blank.
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
      title: Text(
        entry.medicineName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${entry.transactionType.toLowerCase()} · $_attribution · '
        '${_relativeTime(entry.serverTimestamp)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        // Explicit sign: quantity_delta is already negative for a dispense, so
        // only the positive case needs a '+' adding.
        entry.quantityDelta > 0 ? '+${entry.quantityDelta}' : '${entry.quantityDelta}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: deltaColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

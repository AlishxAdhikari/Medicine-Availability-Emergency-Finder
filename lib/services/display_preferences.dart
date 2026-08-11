import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../state.dart' show StockDisplayMode;

/// Persists the handful of display choices that must survive a restart.
///
/// Separate from AppStateManager, which holds session state in plain
/// ValueNotifiers and deliberately forgets everything on relaunch. A display
/// preference is different: someone who switched the search results to exact
/// quantities expects them to still be exact tomorrow, and on a demo phone
/// that gets backgrounded and reopened repeatedly, re-picking it every launch
/// is the kind of friction that looks like a bug.
///
/// Same storage and same load-once-at-startup contract as ServerConfig -- see
/// the note there on why the getter stays synchronous.
class DisplayPreferences {
  DisplayPreferences._internal();
  static final DisplayPreferences instance = DisplayPreferences._internal();

  static const _storage = FlutterSecureStorage();
  static const _stockDisplayKey = 'stock_display_mode';

  /// Defaults to [StockDisplayMode.availability] -- the behaviour every
  /// existing install already has, so upgrading doesn't silently start
  /// publishing exact counts to users who never asked for them.
  final ValueNotifier<StockDisplayMode> stockDisplayModeNotifier =
      ValueNotifier<StockDisplayMode>(StockDisplayMode.availability);

  StockDisplayMode get stockDisplayMode => stockDisplayModeNotifier.value;

  bool _loaded = false;

  /// Reads the saved preference. Safe to call more than once, and never
  /// throws: on a platform where secure storage is unavailable we keep the
  /// default rather than blocking startup on a settings read.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final saved = await _storage.read(key: _stockDisplayKey);
      if (saved == StockDisplayMode.quantity.name) {
        stockDisplayModeNotifier.value = StockDisplayMode.quantity;
      } else if (saved == StockDisplayMode.availability.name) {
        stockDisplayModeNotifier.value = StockDisplayMode.availability;
      }
      // Anything else (null, or a mode written by a newer build) leaves the
      // default in place.
    } catch (_) {
      // Keep the default.
    }
    _loaded = true;
  }

  /// Applies [mode] immediately and persists it. The notifier fires first, so
  /// the UI never waits on the disk write.
  Future<void> setStockDisplayMode(StockDisplayMode mode) async {
    if (stockDisplayModeNotifier.value == mode && _loaded) return;
    stockDisplayModeNotifier.value = mode;
    _loaded = true;
    try {
      await _storage.write(key: _stockDisplayKey, value: mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  Future<void> toggleStockDisplayMode() => setStockDisplayMode(
        stockDisplayMode == StockDisplayMode.quantity
            ? StockDisplayMode.availability
            : StockDisplayMode.quantity,
      );
}

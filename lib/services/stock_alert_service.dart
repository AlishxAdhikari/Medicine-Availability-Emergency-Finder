import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';
import 'owner_stock_service.dart' show StockTransactionEntry;
import 'server_config.dart';

/// One message pushed from sync/consumers.py's StockConsumer, matching the
/// payload shape built in sync/signals.py's check_threshold():
/// {"medicine_id": 1, "medicine_name": "...", "quantity": 3, "level": "low"}
class StockAlert {
  final int medicineId;
  final String medicineName;
  final int quantity;
  final String level; // 'low' or 'critical'

  StockAlert({
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.level,
  });

  factory StockAlert.fromJson(Map<String, dynamic> json) {
    return StockAlert(
      medicineId: json['medicine_id'] as int,
      medicineName: json['medicine_name'] as String,
      quantity: json['quantity'] as int,
      level: json['level'] as String,
    );
  }
}

/// A medicine's new committed quantity, pushed on EVERY stock movement by
/// sync/signals.py's broadcast_stock_state():
/// {"event": "stock_level", "medicine_id": 1, "medicine_name": "...",
///  "quantity": 49, "low_threshold": 10}
///
/// Distinct from [StockAlert]: this is the routine fact, sent whether or not
/// the quantity is worth worrying about, and it is what lets a customer's
/// search results track an owner's sale as it happens. [StockAlert] is the
/// exceptional judgement layered on top, and arrives right after this one when
/// both apply.
class StockLevel {
  final int medicineId;
  final String medicineName;
  final int quantity;
  final int lowThreshold;

  StockLevel({
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.lowThreshold,
  });

  /// `low_threshold` is tolerated as missing so a client can talk to a server
  /// that hasn't been redeployed yet; the quantity is the part that matters.
  factory StockLevel.fromJson(Map<String, dynamic> json) {
    return StockLevel(
      medicineId: json['medicine_id'] as int,
      medicineName: json['medicine_name'] as String,
      quantity: (json['quantity'] as num).toInt(),
      lowThreshold: (json['low_threshold'] as num?)?.toInt() ?? 0,
    );
  }
}

/// True when a socket message is a stock-ledger row rather than a low-stock
/// alert.
///
/// Three kinds arrive on the same socket, tagged by sync/signals.py with an
/// `event` key. Pulled out as pure top-level functions -- same reasoning as
/// parseStockPayload in owner_stock_service.dart -- because the routing
/// decision is the one part of the socket layer worth testing without a
/// server.
///
/// An untagged message is treated as an alert: that is all a server predating
/// the `event` key could have sent. Erring the other way would feed an alert
/// payload to StockTransactionEntry.fromJson and throw on every message.
bool isTransactionMessage(Map<String, dynamic> json) =>
    json['event'] == 'stock_transaction';

/// True when a socket message is a routine level update. Requires the explicit
/// tag -- unlike [isTransactionMessage]'s counterpart default, there is no
/// older-server case to be generous about, because `stock_level` and the
/// `event` key shipped together.
bool isStockLevelMessage(Map<String, dynamic> json) =>
    json['event'] == 'stock_level';

/// Opens a WebSocket connection to sync/routing.py's
/// `ws/stock/<pharmacy_id>/` endpoint and exposes incoming low-stock alerts
/// as a Dart Stream. One instance per active connection -- call connect()
/// when a screen starts watching a pharmacy, and dispose() when it stops
/// (e.g. in the State's dispose() method), otherwise the socket and its
/// stream subscription leak.
class StockAlertService {
  WebSocketChannel? _channel;
  StreamController<StockAlert>? _controller;

  /// Ledger rows pushed on the same socket. Owners only: the server sends
  /// these to the `pharmacy_<id>_owner` group, which sync/consumers.py joins a
  /// connection to only when the user actually owns this pharmacy. A
  /// non-owner's socket therefore never carries them, so this stream simply
  /// stays silent rather than needing to filter anything.
  StreamController<StockTransactionEntry>? _transactionController;

  /// Routine quantity updates, pushed on every movement. Public -- the server
  /// sends these to the same group as alerts, so any signed-in watcher of this
  /// pharmacy receives them.
  StreamController<StockLevel>? _levelController;

  bool _retriedAfterAuthFailure = false;

  /// Bumped by every connect()/disconnect(). _attach captures it and rechecks
  /// after each await, so work started for a superseded connection cannot
  /// clobber a newer channel or leak a socket nobody holds a reference to.
  int _generation = 0;

  /// A socket that stayed open at least this long clearly authenticated
  /// fine, so a 4401 after it is a *fresh* token expiry (access tokens live
  /// 30 minutes) and deserves its own retry. A refresh/reject loop closes in
  /// milliseconds and so never clears the flag.
  static const Duration _provenConnectionAge = Duration(seconds: 30);

  /// Shares ServerConfig with ApiClient, so the REST and WebSocket URLs are
  /// guaranteed to name the same machine. ServerConfig.wsBaseUrl keeps the
  /// ws:// scheme and omits the /api/v1 prefix, since the WebSocket route is
  /// mounted at the ASGI root (medalert_api/asgi.py), not under DRF.
  String get _wsBaseUrl => ServerConfig.instance.wsBaseUrl;

  /// Connects to a specific pharmacy's stock-alert group. Returns a
  /// broadcast stream so multiple widgets could listen if needed, though
  /// typically only one screen watches a given pharmacy at a time.
  ///
  /// The access token goes in the query string because browsers can't set
  /// custom headers on a WebSocket handshake -- sync/middleware.py reads it
  /// from there. Without a valid token the server accepts the socket and then
  /// immediately closes it with code 4401.
  Future<Stream<StockAlert>> connect(int pharmacyId) async {
    disconnect(); // close any previous connection first -- one at a time

    _retriedAfterAuthFailure = false;
    _generation++;
    // The controller is created here, not in _attach, so it survives a
    // reconnect -- the caller keeps listening to the same stream across a
    // token refresh and never sees the socket flap.
    final controller = StreamController<StockAlert>.broadcast();
    _controller = controller;
    _transactionController = StreamController<StockTransactionEntry>.broadcast();
    _levelController = StreamController<StockLevel>.broadcast();
    await _attach(pharmacyId, _generation);
    return controller.stream;
  }

  /// Every committed quantity change for the connected pharmacy.
  ///
  /// Same shape and lifetime rules as [transactions] -- read it after
  /// connect(), it survives a token-refresh reconnect, and it closes when
  /// [disconnect] runs. Unlike [transactions] this one is not owner-gated:
  /// customers are its main audience.
  Stream<StockLevel> get levels =>
      (_levelController ??= StreamController<StockLevel>.broadcast()).stream;

  /// Every stock movement for the connected pharmacy, as it commits.
  ///
  /// Exposed as a getter rather than returned from [connect] so the existing
  /// single-return signature stays intact for the screens that only care
  /// about alerts. Read it after connect(); like the alert stream it survives
  /// a token-refresh reconnect, and it closes when [disconnect] runs.
  ///
  /// Empty (but valid) before the first connect(), so a caller that listens
  /// eagerly does not need a null check.
  Stream<StockTransactionEntry> get transactions =>
      (_transactionController ??=
              StreamController<StockTransactionEntry>.broadcast())
          .stream;

  Future<void> _attach(int pharmacyId, int generation) async {
    final token = await ApiClient.instance.accessToken;
    // disconnect() (or another connect()) may have run during that await.
    // Bail before opening a socket nothing would ever close.
    if (_controller == null || generation != _generation) return;

    final uri = Uri.parse('$_wsBaseUrl/ws/stock/$pharmacyId/').replace(
      queryParameters: {'token': ?token},
    );
    // Explicitly close whatever we are replacing. On the 4401 reconnect path
    // the old channel is done but its sink is still ours to release.
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(uri);
    final openedAt = DateTime.now();

    _channel!.stream.listen(
      (raw) {
        try {
          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          // Three message kinds share this socket; see isTransactionMessage.
          if (isTransactionMessage(json)) {
            _transactionController?.add(StockTransactionEntry.fromJson(json));
          } else if (isStockLevelMessage(json)) {
            _levelController?.add(StockLevel.fromJson(json));
          } else {
            _controller?.add(StockAlert.fromJson(json));
          }
        } catch (_) {
          // Malformed message from the server -- drop it rather than
          // crashing the whole stream for one bad payload.
        }
      },
      onError: (_) {
        // Connection dropped (server restarted, network blip, etc). The
        // stream just ends; the UI's listener should treat "no more
        // alerts" as normal rather than fatal.
        if (generation != _generation) return; // superseded; not ours to close
        _controller?.close();
        _transactionController?.close();
        _levelController?.close();
      },
      onDone: () async {
        // 4401 from sync/consumers.py means the access token was missing,
        // expired, or belongs to a deleted/deactivated user. An access token
        // lives 30 minutes (SIMPLE_JWT in settings.py), so a screen left open
        // will hit this routinely -- refresh once and reopen rather than
        // silently going dead until the user navigates away and back.
        // Retry once only: if the refresh itself is what's failing, reopening
        // in a loop would hammer the server.
        if (generation != _generation) return; // superseded; not ours to close

        // This socket lived long enough to prove the last refresh worked, so
        // give the new expiry its own retry instead of dying silently on a
        // screen the user left open past a second token lifetime.
        if (DateTime.now().difference(openedAt) >= _provenConnectionAge) {
          _retriedAfterAuthFailure = false;
        }

        if (_channel?.closeCode == 4401 && !_retriedAfterAuthFailure) {
          _retriedAfterAuthFailure = true;
          if (await ApiClient.instance.refreshAccessToken()) {
            // disconnect() -- possibly followed by a fresh connect() -- can
            // have run during the refresh. Reattaching unconditionally would
            // either resurrect a disconnected service or clobber the newly
            // created channel, leaking a socket either way.
            if (_controller == null || generation != _generation) return;
            await _attach(pharmacyId, generation);
            return; // same controller, so the caller's stream stays alive
          }
          if (_controller == null || generation != _generation) return;
        }
        _controller?.close();
        _transactionController?.close();
        _levelController?.close();
      },
    );
  }

  void disconnect() {
    // Invalidate any _attach still awaiting a token or a token refresh, so it
    // cannot reopen a socket after this call.
    _generation++;
    _channel?.sink.close();
    _channel = null;
    _controller?.close();
    _controller = null;
    _transactionController?.close();
    _transactionController = null;
    _levelController?.close();
    _levelController = null;
  }
}

/// A stock update tagged with the pharmacy it came from.
///
/// The server payloads don't name their pharmacy -- they don't need to, since
/// one socket carries one pharmacy. That stops being enough as soon as a screen
/// watches several at once, so [LiveStockWatcher] attaches the id of the
/// connection the message arrived on. Taking it from the connection rather than
/// the payload makes it impossible for the tag to disagree with the source.
class PharmacyStockEvent<T> {
  final int pharmacyId;
  final T event;

  PharmacyStockEvent(this.pharmacyId, this.event);
}

/// Watches several pharmacies' stock sockets at once and merges their messages
/// into one alert stream and one level stream.
///
/// Exists because the search screen used to watch only `_results.first`. On a
/// multi-device demo that is the difference between working and not: each phone
/// sorts results by its own position, so the pharmacy making the sale is the
/// top result on approximately none of them, and every customer phone except
/// the lucky one showed nothing. Watching the whole visible result set removes
/// the coincidence.
///
/// One WebSocket per watched pharmacy, capped at [maxConnections]. The cap is
/// what makes "watch everything visible" affordable: search returns up to a
/// page of 20, and 20 sockets per phone is a lot of handshakes for cards the
/// user has to scroll to reach. Results are distance-sorted, so the first
/// [maxConnections] are the ones a customer is realistically choosing between.
class LiveStockWatcher {
  /// Ceiling on simultaneous sockets, applied to the head of the watch list.
  static const int maxConnections = 8;

  final Map<int, StockAlertService> _services = {};
  final Map<int, List<StreamSubscription<dynamic>>> _subscriptions = {};

  final StreamController<PharmacyStockEvent<StockAlert>> _alerts =
      StreamController<PharmacyStockEvent<StockAlert>>.broadcast();
  final StreamController<PharmacyStockEvent<StockLevel>> _levels =
      StreamController<PharmacyStockEvent<StockLevel>>.broadcast();

  /// Guards against interleaved [watch] calls -- a second search can start
  /// while the first is still opening sockets, and without this the older call
  /// would resume and connect pharmacies that are no longer on screen.
  int _generation = 0;
  bool _disposed = false;

  Stream<PharmacyStockEvent<StockAlert>> get alerts => _alerts.stream;
  Stream<PharmacyStockEvent<StockLevel>> get levels => _levels.stream;

  /// Pharmacy ids with a live socket right now. Exposed for tests and for the
  /// "live" badge on the search screen.
  Set<int> get watched => _services.keys.toSet();

  /// Makes the watched set equal the first [maxConnections] of [pharmacyIds].
  ///
  /// Diffed rather than torn down and rebuilt: re-running the same search, or
  /// scrolling, usually keeps most ids, and dropping their sockets would mean
  /// a window where a sale goes unseen and a burst of reconnects on every
  /// keystroke-debounced search.
  Future<void> watch(Iterable<int> pharmacyIds) async {
    if (_disposed) return;
    final generation = ++_generation;

    final wanted = <int>{};
    for (final id in pharmacyIds) {
      if (wanted.length >= maxConnections) break;
      wanted.add(id);
    }

    for (final id in _services.keys.toList()) {
      if (!wanted.contains(id)) _drop(id);
    }

    for (final id in wanted) {
      if (_services.containsKey(id)) continue; // already connected
      final service = StockAlertService();
      // Registered before the await so a concurrent watch() for the same id
      // sees it as taken and doesn't open a second socket to it.
      _services[id] = service;

      final alertStream = await service.connect(id);
      if (_disposed || generation != _generation) {
        // Superseded (or disposed) while connecting. Only tear this one down
        // if it is still the service registered under this id -- a newer
        // watch() may already have replaced it.
        if (identical(_services[id], service)) _drop(id);
        return;
      }

      _subscriptions[id] = [
        alertStream.listen((alert) {
          if (!_alerts.isClosed) _alerts.add(PharmacyStockEvent(id, alert));
        }),
        service.levels.listen((level) {
          if (!_levels.isClosed) _levels.add(PharmacyStockEvent(id, level));
        }),
      ];
    }
  }

  void _drop(int id) {
    for (final sub in _subscriptions.remove(id) ?? const []) {
      sub.cancel();
    }
    _services.remove(id)?.disconnect();
  }

  /// Closes every socket and both merged streams. Call from the owning State's
  /// dispose(); the watcher is not reusable afterwards.
  void dispose() {
    _disposed = true;
    _generation++;
    for (final id in _services.keys.toList()) {
      _drop(id);
    }
    _alerts.close();
    _levels.close();
  }
}
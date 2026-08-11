import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';
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

/// Opens a WebSocket connection to sync/routing.py's
/// `ws/stock/<pharmacy_id>/` endpoint and exposes incoming low-stock alerts
/// as a Dart Stream. One instance per active connection -- call connect()
/// when a screen starts watching a pharmacy, and dispose() when it stops
/// (e.g. in the State's dispose() method), otherwise the socket and its
/// stream subscription leak.
class StockAlertService {
  WebSocketChannel? _channel;
  StreamController<StockAlert>? _controller;
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
    await _attach(pharmacyId, _generation);
    return controller.stream;
  }

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
          _controller?.add(StockAlert.fromJson(json));
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
  }
}
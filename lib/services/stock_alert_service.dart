import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

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
/// ws/stock/<pharmacy_id>/ endpoint and exposes incoming low-stock alerts
/// as a Dart Stream. One instance per active connection -- call connect()
/// when a screen starts watching a pharmacy, and dispose() when it stops
/// (e.g. in the State's dispose() method), otherwise the socket and its
/// stream subscription leak.
class StockAlertService {
  WebSocketChannel? _channel;
  StreamController<StockAlert>? _controller;
  bool _retriedAfterAuthFailure = false;

  /// Mirrors ApiClient.baseUrl's platform logic (see api_client.dart) but
  /// for the ws:// scheme and without the /api/v1 prefix, since the
  /// WebSocket route is mounted at the ASGI root (medalert_api/asgi.py),
  /// not under DRF's /api/v1/.
  String get _wsBaseUrl {
    if (kIsWeb) return 'ws://127.0.0.1:8000';
    if (Platform.isAndroid) return 'ws://192.168.1.64:8000';
    return 'ws://127.0.0.1:8000';
  }

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
    // The controller is created here, not in _attach, so it survives a
    // reconnect -- the caller keeps listening to the same stream across a
    // token refresh and never sees the socket flap.
    _controller = StreamController<StockAlert>.broadcast();
    await _attach(pharmacyId);
    return _controller!.stream;
  }

  Future<void> _attach(int pharmacyId) async {
    final token = await ApiClient.instance.accessToken;
    final uri = Uri.parse('$_wsBaseUrl/ws/stock/$pharmacyId/').replace(
      queryParameters: {'token': ?token},
    );
    _channel = WebSocketChannel.connect(uri);

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
        if (_channel?.closeCode == 4401 && !_retriedAfterAuthFailure) {
          _retriedAfterAuthFailure = true;
          if (await ApiClient.instance.refreshAccessToken()) {
            await _attach(pharmacyId);
            return; // same controller, so the caller's stream stays alive
          }
        }
        _controller?.close();
      },
    );
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _controller?.close();
    _controller = null;
  }
}
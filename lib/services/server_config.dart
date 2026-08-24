import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one place that decides which backend the app talks to.
///
/// Both ApiClient (http, /api/v1 prefix) and StockAlertService (ws, mounted
/// at the ASGI root) delegate here. They used to carry their own copies of
/// the same platform switch, which is exactly the kind of duplication that
/// drifts: the http one could be updated for a new LAN address while the
/// WebSocket one kept pointing at the old one, and the only symptom would be
/// "search works but live stock updates don't".
///
/// Two layers, in priority order:
///
/// 1. [_override] -- a host typed into the in-app settings screen and kept in
///    secure storage. Survives restarts. This exists because the demo runs on
///    physical phones on a network we don't control: if the router hands out
///    a different subnet, re-typing a host on each phone takes seconds,
///    whereas rebuilding is a laptop, a cable and (on iOS) Xcode.
/// 2. [_compiledDefault] -- baked in at build time with
///    `--dart-define=MEDALERT_HOST=192.168.1.64:8000`. This is what makes a
///    freshly installed build work with no setup at all, which matters when
///    someone else installs the app to try it.
class ServerConfig {
  ServerConfig._internal();
  static final ServerConfig instance = ServerConfig._internal();

  static const _storage = FlutterSecureStorage();
  static const _hostKey = 'backend_host';

  /// Host[:port] with no scheme and no trailing slash, e.g. "192.168.1.64:8000".
  /// Override at build time with:
  ///   flutter build apk --dart-define=MEDALERT_HOST=10.0.0.5:8000
  static const String _compiledDefault = String.fromEnvironment(
    'MEDALERT_HOST',
    defaultValue: '192.168.1.71:8000',
  );

  /// Cached so the URL getters can stay synchronous -- they are called on
  /// every request, and making them async would force `await` through every
  /// call site in every service for a value that changes at most once a
  /// session. [load] must therefore run before the first request; main()
  /// does that during startup.
  String? _override;
  bool _loaded = false;

  /// Reads any saved host override from secure storage. Safe to call more
  /// than once. Never throws: on a platform where secure storage is
  /// unavailable we fall back to the compiled default rather than blocking
  /// app startup on a settings read.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final saved = await _storage.read(key: _hostKey);
      if (saved != null && saved.trim().isNotEmpty) _override = saved.trim();
    } catch (_) {
      // Keep the compiled default.
    }
    _loaded = true;
  }

  /// The host the app is currently using, for display in the settings screen.
  String get host => _override ?? _compiledDefault;

  /// True when the user has typed a host that differs from the build-time
  /// default, so settings can offer to reset back to it.
  bool get isOverridden => _override != null && _override != _compiledDefault;

  String get compiledDefault => _compiledDefault;

  /// Persists a new host and applies it to subsequent requests immediately.
  /// Strips any scheme or trailing slash the user pasted in, since the
  /// getters below add their own.
  Future<void> setHost(String value) async {
    final cleaned = normalizeHost(value);
    if (cleaned.isEmpty) return;
    _override = cleaned;
    _loaded = true;
    await _storage.write(key: _hostKey, value: cleaned);
  }

  /// Drops the override and goes back to the build-time default.
  Future<void> resetToDefault() async {
    _override = null;
    await _storage.delete(key: _hostKey);
  }

  /// "http://192.168.1.64:8000/" -> "192.168.1.64:8000".
  /// Pasting a full URL is the obvious thing to do, so accept it rather than
  /// producing "http://http://...".
  static String normalizeHost(String value) {
    var v = value.trim();
    v = v.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v.trim();
  }

  /// Desktop and web builds run on the same machine as `manage.py runserver`,
  /// so they keep using loopback and ignore the configured host. Phones
  /// (Android *and* iOS) must use the LAN address -- on a physical iPhone
  /// 127.0.0.1 is the phone itself, which is why the previous
  /// `if (Platform.isAndroid)` switch left iOS unable to reach the backend
  /// at all.
  ///
  /// Uses defaultTargetPlatform rather than dart:io's Platform so this file
  /// still compiles for web, where dart:io does not exist.
  bool get _usesLoopback {
    if (kIsWeb) return true;
    return defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
  }

  String get _effectiveHost => _usesLoopback ? '127.0.0.1:8000' : host;

  /// Base URL for the DRF API, including the /api/v1 prefix that every
  /// REST endpoint sits under (see medalert_api/urls.py).
  String get httpBaseUrl => 'http://$_effectiveHost/api/v1';

  /// Base URL for WebSockets. Deliberately has no /api/v1 prefix: the
  /// `ws/stock/<pharmacy_id>/` route is mounted at the ASGI root in
  /// medalert_api/asgi.py, not under DRF's router.
  String get wsBaseUrl => 'ws://$_effectiveHost';

  /// A cheap unauthenticated endpoint used by the settings screen's
  /// "Test connection" button. Chosen because it needs no token and no
  /// query parameters, so a success means the host, port, firewall and
  /// ALLOWED_HOSTS are all correct.
  String get healthCheckUrl => '$httpBaseUrl/ambulances/districts/';
}

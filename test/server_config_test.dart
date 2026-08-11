import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/server_config.dart';

/// These cover the pure, storage-free half of ServerConfig: host parsing and
/// URL construction. The persistence half needs a platform channel for
/// flutter_secure_storage and belongs in an integration test.
///
/// The URL pair is what matters most here. ApiClient and StockAlertService
/// used to build their base URLs separately, and the failure mode when those
/// two disagreed was nasty to diagnose: REST calls succeed, so the app looks
/// healthy, while live stock updates silently never arrive. Asserting both
/// derive from one host is the regression guard for that.
void main() {
  group('normalizeHost', () {
    test('leaves a bare host:port untouched', () {
      expect(ServerConfig.normalizeHost('192.168.1.64:8000'), '192.168.1.64:8000');
    });

    test('strips a scheme the user pasted in', () {
      // Pasting a full URL from a browser is the obvious thing to do, and
      // without stripping it we would build "http://http://...".
      expect(ServerConfig.normalizeHost('http://192.168.1.64:8000'), '192.168.1.64:8000');
      expect(ServerConfig.normalizeHost('https://example.com'), 'example.com');
      expect(ServerConfig.normalizeHost('ws://192.168.1.64:8000'), '192.168.1.64:8000');
    });

    test('strips trailing slashes', () {
      expect(ServerConfig.normalizeHost('http://192.168.1.64:8000/'), '192.168.1.64:8000');
      expect(ServerConfig.normalizeHost('192.168.1.64:8000///'), '192.168.1.64:8000');
    });

    test('trims surrounding whitespace', () {
      // Phone keyboards readily add a trailing space, and an untrimmed host
      // produces a malformed URI rather than a clear error.
      expect(ServerConfig.normalizeHost('  192.168.1.64:8000  '), '192.168.1.64:8000');
    });

    test('returns empty for blank input so callers can reject it', () {
      expect(ServerConfig.normalizeHost('   '), isEmpty);
      expect(ServerConfig.normalizeHost(''), isEmpty);
    });
  });

  group('URL construction', () {
    test('http and ws base URLs always name the same host', () {
      final config = ServerConfig.instance;

      final httpHost = Uri.parse(config.httpBaseUrl).authority;
      final wsHost = Uri.parse(config.wsBaseUrl).authority;

      expect(httpHost, wsHost);
    });

    test('http base URL carries the /api/v1 prefix and ws does not', () {
      final config = ServerConfig.instance;

      // The REST API is mounted under /api/v1 by medalert_api/urls.py, but the
      // WebSocket route lives at the ASGI root in medalert_api/asgi.py.
      // Giving the socket URL an /api/v1 prefix makes the handshake 404.
      expect(config.httpBaseUrl, endsWith('/api/v1'));
      expect(config.wsBaseUrl, isNot(contains('/api/v1')));
    });

    test('uses the expected schemes', () {
      expect(Uri.parse(ServerConfig.instance.httpBaseUrl).scheme, 'http');
      expect(Uri.parse(ServerConfig.instance.wsBaseUrl).scheme, 'ws');
    });

    test('health check sits under the http base URL and needs no auth', () {
      final config = ServerConfig.instance;
      expect(config.healthCheckUrl, startsWith(config.httpBaseUrl));
      expect(config.healthCheckUrl, endsWith('/ambulances/districts/'));
    });
  });
}

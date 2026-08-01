import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/screens/login_screen.dart';

void main() {
  group('routeForRole', () {
    test('sends a pharmacy owner to the dashboard', () {
      final route = routeForRole({
        'role': 'pharmacy_owner',
        'pharmacy': {'id': 7, 'name': 'My Pharmacy'},
      });

      expect(route, '/owner');
    });

    test('sends a plain user home', () {
      expect(routeForRole({'role': 'user', 'pharmacy': null}), '/home');
    });

    test('falls back to home when the server sends no role', () {
      // An older backend, or a response shape change -- default to the
      // read-only experience rather than opening an editor the account may
      // have no permission to use.
      expect(routeForRole({}), '/home');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/location_service.dart';
import 'package:medalert/widgets/service_map.dart';

/// Wraps [child] in the minimum a ServiceMap needs to lay out. The map fills
/// its parent, so it must be given bounded constraints.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 400, child: child)),
    );

const _kathmanduPharmacy = MapPlace(
  label: 'City Central Pharmacy',
  subtitle: 'Durbar Marg',
  latitude: 27.7100,
  longitude: 85.3150,
  icon: Icons.local_pharmacy,
  isPrimary: true,
);

const _secondPharmacy = MapPlace(
  label: 'MediQuick 24/7',
  subtitle: 'Thamel',
  latitude: 27.7150,
  longitude: 85.3100,
  icon: Icons.local_pharmacy,
);

void main() {
  // Tiles are network-backed and will fail to load under test; that is fine
  // and expected. Everything asserted here is the marker layer, which is what
  // the screens actually depend on being correct.

  testWidgets('draws a pin carrying each place\'s own category icon',
      (tester) async {
    await tester.pumpWidget(_host(const ServiceMap(
      places: [_kathmanduPharmacy, _secondPharmacy],
    )));
    await tester.pump();

    // The whole point of the icon: a pharmacy pin has to be identifiable as a
    // pharmacy without tapping it.
    expect(find.byIcon(Icons.local_pharmacy), findsNWidgets(2));
  });

  testWidgets('a different place type gets a different icon', (tester) async {
    await tester.pumpWidget(_host(const ServiceMap(
      places: [
        MapPlace(
          label: 'Bir Hospital Blood Bank',
          latitude: 27.7050,
          longitude: 85.3130,
          icon: Icons.bloodtype,
        ),
      ],
    )));
    await tester.pump();

    expect(find.byIcon(Icons.bloodtype), findsOneWidget);
    expect(find.byIcon(Icons.local_pharmacy), findsNothing);
  });

  testWidgets('a real fix marks the user with a person icon', (tester) async {
    await tester.pumpWidget(_host(const ServiceMap(
      places: [_kathmanduPharmacy],
      origin: UserLocation(latitude: 27.7172, longitude: 85.3240, isPrecise: true),
    )));
    await tester.pump();

    expect(find.byIcon(Icons.person), findsOneWidget);
    // The user must not be drawn with the searching icon when we actually
    // know where they are.
    expect(find.byIcon(Icons.location_searching), findsNothing);
  });

  testWidgets('a fallback location is visibly not a real fix', (tester) async {
    await tester.pumpWidget(_host(ServiceMap(
      places: const [_kathmanduPharmacy],
      origin: LocationService.fallback,
    )));
    await tester.pump();

    // Distinct icon, plus the "Approximate area" pill -- the map must never
    // assert the user is standing on the fallback point.
    expect(find.byIcon(Icons.location_searching), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);
    expect(find.text('Approximate area'), findsOneWidget);
  });

  testWidgets('says so when there is nothing to plot', (tester) async {
    await tester.pumpWidget(_host(const ServiceMap(
      places: [],
      emptyMessage: 'No pharmacies in this radius',
    )));
    await tester.pump();

    expect(find.text('No pharmacies in this radius'), findsOneWidget);
  });

  testWidgets('tapping a pin opens its details card', (tester) async {
    await tester.pumpWidget(_host(const ServiceMap(places: [_kathmanduPharmacy])));
    await tester.pump();

    expect(find.text('Durbar Marg'), findsNothing);

    await tester.tap(find.byIcon(Icons.local_pharmacy));
    await tester.pump();

    expect(find.text('City Central Pharmacy'), findsOneWidget);
    expect(find.text('Durbar Marg'), findsOneWidget);
  });
}

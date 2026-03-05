import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/features/map/presentation/widgets/route_hint_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows origin hint when no pins', (tester) async {
    await tester.pumpWidget(wrap(const RouteHintCard(routeOrigin: null, routeDestination: null)));
    expect(find.text('Long-press to drop Origin pin.'), findsOneWidget);
  });

  testWidgets('shows destination hint when only origin exists', (tester) async {
    await tester.pumpWidget(wrap(const RouteHintCard(
      routeOrigin: LatLng(52.0, -9.0),
      routeDestination: null,
    )));
    expect(find.text('Long-press again to drop Destination pin.'), findsOneWidget);
  });

  testWidgets('shows ready hint when both pins exist', (tester) async {
    await tester.pumpWidget(wrap(const RouteHintCard(
      routeOrigin: LatLng(52.0, -9.0),
      routeDestination: LatLng(52.1, -9.1),
    )));
    expect(find.text('Pins set. Tap "Get Route" to calculate fastest path.'), findsOneWidget);
  });
}

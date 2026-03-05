import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteHintCard extends StatelessWidget {
  const RouteHintCard({
    super.key,
    required this.routeOrigin,
    required this.routeDestination,
  });

  final LatLng? routeOrigin;
  final LatLng? routeDestination;

  @override
  Widget build(BuildContext context) {
    final text = routeOrigin == null
        ? 'Long-press to drop Origin pin.'
        : routeDestination == null
            ? 'Long-press again to drop Destination pin.'
            : 'Pins set. Tap "Get Route" to calculate fastest path.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text),
      ),
    );
  }
}

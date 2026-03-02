import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Builds a Google Maps URL for directions (Maps URLs format).
String exportGoogleMapsDirectionsUrl({
  required LatLng origin,
  required LatLng destination,
  List<LatLng>? waypoints,
  String travelMode = 'driving',
}) {
  final originStr = '${origin.latitude},${origin.longitude}';
  final destStr = '${destination.latitude},${destination.longitude}';
  final waypointsStr = waypoints?.isNotEmpty == true
      ? waypoints!
          .map((w) => '${w.latitude},${w.longitude}')
          .join('|')
      : null;
  final params = <String, String>{
    'api': '1',
    'origin': originStr,
    'destination': destStr,
    'travelmode': travelMode,
  };
  if (waypointsStr != null) params['waypoints'] = waypointsStr;
  final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  return 'https://www.google.com/maps/dir/?$query';
}

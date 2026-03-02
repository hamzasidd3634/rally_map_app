import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Immutable lat/lng for use in domain and data layers.
class LatLngModel {
  const LatLngModel(this.lat, this.lng);

  final double lat;
  final double lng;

  LatLng toLatLng() => LatLng(lat, lng);

  static LatLngModel fromLatLng(LatLng l) => LatLngModel(l.latitude, l.longitude);
}

import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'projection.dart';
import 'segment_intersection.dart';

/// Distance in meters from a point to the nearest point on a polyline.
/// Uses equirectangular projection around the given latitude.
double distanceToPolylineMeters(
  double pointLat,
  double pointLon,
  List<LatLng> polyline,
  double refLat,
) {
  if (polyline.isEmpty) return double.infinity;
  if (polyline.length == 1) {
    return _haversineMeters(
      pointLat,
      pointLon,
      polyline[0].latitude,
      polyline[0].longitude,
    );
  }
  final proj = Projection(refLat);
  final refLon = polyline.first.longitude;
  final p = proj.toLocal(pointLat, pointLon, refLon);
  final pt = Point2(p[0], p[1]);
  var minDist2 = double.infinity;
  for (var i = 0; i < polyline.length - 1; i++) {
    final a = proj.toLocal(
      polyline[i].latitude,
      polyline[i].longitude,
      refLon,
    );
    final b = proj.toLocal(
      polyline[i + 1].latitude,
      polyline[i + 1].longitude,
      refLon,
    );
    final d2 = distanceToSegmentSquared(pt, Point2(a[0], a[1]), Point2(b[0], b[1]));
    if (d2 < minDist2) minDist2 = d2;
  }
  return math.sqrt(minDist2);
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}


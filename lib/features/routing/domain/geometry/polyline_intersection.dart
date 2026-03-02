import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'projection.dart';
import 'segment_intersection.dart';

/// Check if polyline A and polyline B intersect (any segment crosses any segment).
/// Uses equirectangular projection around refLat. tolerance in meters.
bool polylinesIntersect(
  List<LatLng> polylineA,
  List<LatLng> polylineB, {
  double refLat = 0,
  double toleranceMeters = 1.0,
}) {
  if (polylineA.length < 2 || polylineB.length < 2) return false;
  final refLon = polylineA.first.longitude;
  final proj = Projection(refLat);
  final tol = toleranceMeters;

  for (var i = 0; i < polylineA.length - 1; i++) {
    final a0 = proj.toLocal(
      polylineA[i].latitude,
      polylineA[i].longitude,
      refLon,
    );
    final a1 = proj.toLocal(
      polylineA[i + 1].latitude,
      polylineA[i + 1].longitude,
      refLon,
    );
    final pa0 = Point2(a0[0], a0[1]);
    final pa1 = Point2(a1[0], a1[1]);

    for (var j = 0; j < polylineB.length - 1; j++) {
      final b0 = proj.toLocal(
        polylineB[j].latitude,
        polylineB[j].longitude,
        refLon,
      );
      final b1 = proj.toLocal(
        polylineB[j + 1].latitude,
        polylineB[j + 1].longitude,
        refLon,
      );
      final pb0 = Point2(b0[0], b0[1]);
      final pb1 = Point2(b1[0], b1[1]);
      if (segmentsIntersect(pa0, pa1, pb0, pb1, tolerance: tol)) {
        return true;
      }
    }
  }
  return false;
}

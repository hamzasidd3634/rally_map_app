import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Douglas-Peucker simplification (pure Dart, testable).
/// Reduces polyline points while staying within [toleranceMeters] of original.
List<LatLng> douglasPeucker(List<LatLng> points, double toleranceMeters) {
  if (points.length <= 2) return List<LatLng>.from(points);
  return _douglasPeuckerRecursive(points, 0, points.length - 1, toleranceMeters);
}

List<LatLng> _douglasPeuckerRecursive(
  List<LatLng> points,
  int start,
  int end,
  double tolerance,
) {
  if (end <= start + 1) {
    return [points[start], points[end]];
  }
  var maxDist = 0.0;
  var maxIndex = start;
  final p0 = points[start];
  final p1 = points[end];
  for (var i = start + 1; i < end; i++) {
    final d = _distanceToSegmentMeters(
      points[i].latitude,
      points[i].longitude,
      p0.latitude,
      p0.longitude,
      p1.latitude,
      p1.longitude,
    );
    if (d > maxDist) {
      maxDist = d;
      maxIndex = i;
    }
  }
  if (maxDist <= tolerance) {
    return [points[start], points[end]];
  }
  final left = _douglasPeuckerRecursive(points, start, maxIndex, tolerance);
  final right = _douglasPeuckerRecursive(points, maxIndex, end, tolerance);
  return [...left.sublist(0, left.length - 1), ...right];
}

double _distanceToSegmentMeters(
  double px,
  double py,
  double x0,
  double y0,
  double x1,
  double y1,
) {
  final dx = (x1 - x0) * _mPerDegLon(y0);
  final dy = (y1 - y0) * 111320.0;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-20) {
    return _haversine(px, py, x0, y0);
  }
  final t = ((px - x0) * _mPerDegLon(px) * (x1 - x0) + (py - y0) * 111320 * (y1 - y0)) / len2;
  final t2 = t.clamp(0.0, 1.0);
  final qx = x0 + t2 * (x1 - x0);
  final qy = y0 + t2 * (y1 - y0);
  return _haversine(px, py, qx, qy);
}

double _mPerDegLon(double lat) {
  const r = 6371000.0;
  return (r * math.pi / 180) * (lat.isFinite ? math.cos(lat * math.pi / 180) : 1);
}

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a.clamp(0.0, 1.0)), math.sqrt((1 - a).clamp(0.0, 1.0)));
  return r * c;
}

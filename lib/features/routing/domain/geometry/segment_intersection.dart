// Pure Dart segment intersection and distance helpers (testable).
// Uses local planar projection (equirectangular) for robustness.

import 'dart:math' as math;

/// 2D point in local meters.
class Point2 {
  const Point2(this.x, this.y);
  final double x;
  final double y;
}

/// Check if segment (a0,a1) and (b0,b1) intersect (excluding endpoints by default).
/// tolerance: max distance to consider as intersection.
bool segmentsIntersect(
  Point2 a0,
  Point2 a1,
  Point2 b0,
  Point2 b1, {
  double tolerance = 0.0,
}) {
  final d = _cross2(a1.x - a0.x, a1.y - a0.y, b1.x - b0.x, b1.y - b0.y);
  if (d.abs() < 1e-12) return false; // parallel
  final t = _cross2(b0.x - a0.x, b0.y - a0.y, b1.x - b0.x, b1.y - b0.y) / d;
  final u = _cross2(b0.x - a0.x, b0.y - a0.y, a1.x - a0.x, a1.y - a0.y) / d;
  if (tolerance > 0) {
    if (t >= -tolerance && t <= 1 + tolerance && u >= -tolerance && u <= 1 + tolerance) {
      return true;
    }
    return false;
  }
  return t > 0 && t < 1 && u > 0 && u < 1;
}

double _cross2(double a, double b, double c, double d) => a * d - b * c;

/// Squared distance from point p to segment (s0, s1).
double distanceToSegmentSquared(Point2 p, Point2 s0, Point2 s1) {
  final dx = s1.x - s0.x;
  final dy = s1.y - s0.y;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-20) return (p.x - s0.x) * (p.x - s0.x) + (p.y - s0.y) * (p.y - s0.y);
  var t = ((p.x - s0.x) * dx + (p.y - s0.y) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final qx = s0.x + t * dx;
  final qy = s0.y + t * dy;
  return (p.x - qx) * (p.x - qx) + (p.y - qy) * (p.y - qy);
}

/// Distance from point to segment in meters.
double distanceToSegment(Point2 p, Point2 s0, Point2 s1) {
  return math.sqrt(distanceToSegmentSquared(p, s0, s1));
}

/// Equirectangular projection around a reference latitude.
/// Used for local planar segment intersection (pure Dart, testable).
class Projection {
  Projection(this.refLat);

  final double refLat;

  /// Meters per degree longitude at refLat (approximate).
  static double metersPerDegreeLon(double lat) {
    const double earthRadiusM = 6371000;
    return (earthRadiusM * 3.141592653589793 / 180) * (lat.isFinite ? _cosDeg(lat) : 1);
  }

  static double _cosDeg(double deg) {
    final r = deg * 3.141592653589793 / 180;
    return r.isFinite ? _cos(r) : 1;
  }

  static double _cos(double x) {
    x = x % (2 * 3.141592653589793);
    if (x < 0) x += 2 * 3.141592653589793;
    if (x > 3.141592653589793) return -_cos(x - 3.141592653589793);
    if (x > 1.5707963267948966) return -_cos(3.141592653589793 - x);
    final x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24;
  }

  /// Convert (lat, lon) to local (x, y) in meters. Origin at (refLat, refLon).
  List<double> toLocal(double lat, double lon, double refLon) {
    const double mPerDegLat = 111320; // approximate
    final mPerDegLon = Projection.metersPerDegreeLon(refLat);
    return [
      (lon - refLon) * mPerDegLon,
      (refLat - lat) * mPerDegLat,
    ];
  }
}

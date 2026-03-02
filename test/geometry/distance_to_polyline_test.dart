import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/features/routing/domain/geometry/distance_to_polyline.dart';

void main() {
  group('distanceToPolylineMeters', () {
    test('empty polyline returns infinity', () {
      expect(
        distanceToPolylineMeters(48.0, 2.0, [], 48.0),
        double.infinity,
      );
    });

    test('single point returns haversine distance', () {
      final polyline = [LatLng(48.0, 2.0)];
      final d = distanceToPolylineMeters(48.01, 2.0, polyline, 48.0);
      expect(d, greaterThan(0));
      expect(d, lessThan(2000)); // ~1.1 km per degree lat
    });

    test('point near segment has small distance', () {
      final polyline = [
        LatLng(48.0, 2.0),
        LatLng(48.0, 2.01),
      ];
      final d = distanceToPolylineMeters(48.0, 2.005, polyline, 48.0);
      expect(d, lessThan(500));
      expect(d, greaterThanOrEqualTo(0));
    });
  });
}

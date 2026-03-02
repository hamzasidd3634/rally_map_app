import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/features/routing/domain/geometry/polyline_intersection.dart';

void main() {
  group('polylinesIntersect', () {
    test('crossing polylines intersect', () {
      final a = [
        LatLng(48.0, 2.0),
        LatLng(48.01, 2.01),
      ];
      final b = [
        LatLng(48.005, 2.0),
        LatLng(48.005, 2.02),
      ];
      expect(polylinesIntersect(a, b, refLat: 48.0), isTrue);
    });

    test('non-crossing polylines do not intersect', () {
      final a = [
        LatLng(48.0, 2.0),
        LatLng(48.0, 2.01),
      ];
      final b = [
        LatLng(48.01, 2.0),
        LatLng(48.01, 2.01),
      ];
      expect(polylinesIntersect(a, b, refLat: 48.0), isFalse);
    });
  });
}

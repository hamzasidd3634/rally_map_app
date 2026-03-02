import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/features/routing/domain/export_google_maps_url.dart';

void main() {
  group('exportGoogleMapsDirectionsUrl', () {
    test('builds URL with origin and destination', () {
      final url = exportGoogleMapsDirectionsUrl(
        origin: LatLng(48.0, 2.0),
        destination: LatLng(48.01, 2.01),
      );
      expect(url, contains('https://www.google.com/maps/dir/?'));
      expect(url, contains('origin=48.0%2C2.0'));
      expect(url, contains('destination=48.01%2C2.01'));
      expect(url, contains('travelmode=driving'));
    });

    test('includes waypoints when provided', () {
      final url = exportGoogleMapsDirectionsUrl(
        origin: LatLng(48.0, 2.0),
        destination: LatLng(48.02, 2.02),
        waypoints: [LatLng(48.01, 2.01)],
      );
      expect(url, contains('waypoints='));
    });
  });
}

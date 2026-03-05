import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/features/map/state/map_state.dart';

void main() {
  group('MapState', () {
    test('stageStart prefers stage_1 first point', () {
      final state = MapState(
        stages: {
          'stage_2': [const LatLng(1, 1), const LatLng(1.1, 1.1)],
          'stage_1': [const LatLng(2, 2), const LatLng(2.1, 2.1)],
        },
      );
      expect(state.stageStart, const LatLng(2, 2));
    });

    test('clear nullable route fields through copyWith(null)', () {
      final state = MapState(
        routeOrigin: const LatLng(52.0, -9.0),
        routeDestination: const LatLng(52.1, -9.1),
        routeCrossesStageMessage: 'msg',
      );
      final cleared = state.copyWith(
        routeOrigin: null,
        routeDestination: null,
        routeCrossesStageMessage: null,
      );
      expect(cleared.routeOrigin, isNull);
      expect(cleared.routeDestination, isNull);
      expect(cleared.routeCrossesStageMessage, isNull);
    });

    test('markers include route origin/destination/waypoints', () {
      final state = MapState(
        routeOrigin: const LatLng(52.0, -9.0),
        routeDestination: const LatLng(52.1, -9.1),
        routeWaypoints: const [LatLng(52.05, -9.05)],
      );
      final ids = state.markers.map((m) => m.markerId.value).toSet();
      expect(ids, contains('route_origin'));
      expect(ids, contains('route_destination'));
      expect(ids, contains('route_waypoint_0'));
    });

    test('polylines include user route when points exist', () {
      final state = MapState(
        routePoints: const [LatLng(52.0, -9.0), LatLng(52.1, -9.1)],
      );
      final ids = state.polylines.map((p) => p.polylineId.value).toSet();
      expect(ids, contains('user_route'));
    });
  });
}

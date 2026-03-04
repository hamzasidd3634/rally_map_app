import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/features/routing/domain/geometry/polyline_intersection.dart';

import '../data/gpx_service.dart';
import '../data/stage_repository.dart';
import '../../routing/data/directions_client.dart';
import 'map_state.dart';

/// Rally logo visibility: shown when camera zoom is in [0, 5] inclusive, hidden when zoom > 5.
const double rallyLogoZoomThreshold = 5.0;
const double rallyLogoZoomMin = 0.0;

class MapCubit extends Cubit<MapState> {
  MapCubit({
    StageRepository? stageRepository,
    GpxCache? gpxCache,
    DirectionsClient? directionsClient,
    String? directionsApiKey,
    CameraPosition? initialCamera,
  })  : _stageRepo = stageRepository ?? StageRepository(),
        _gpxCache = gpxCache ?? GpxCache(),
        _directions = directionsClient ??
            DirectionsClient(apiKey: "AIzaSyAfmGm_et883qbzn8h_ML-5gwBMoXypQTs"),
        super(MapState(
          cameraPosition: initialCamera ??
              const CameraPosition(
                target: LatLng(48.8610, 2.3610),
                zoom: 1.0,
              ),
          isLoading: true,
        )) {
    _loadMapData();
  }

  final StageRepository _stageRepo;
  final GpxCache _gpxCache;
  final DirectionsClient _directions;

  Future<void> _loadMapData() async {
    try {
      final stages = await _stageRepo.loadAllStages();
      final closed1 = await _gpxCache.parseAndCache('assets/gpx/closed_road_1.gpx');
      final closed2 = await _gpxCache.parseAndCache('assets/gpx/closed_road_2.gpx');
      final closed3 = await _gpxCache.parseAndCache('assets/gpx/closed_road_3.gpx');
      CameraPosition? initialCamera = state.cameraPosition;
      if (stages.isNotEmpty) {
        final firstPoints = stages['stage_1'] ?? stages.values.first;
        if (firstPoints.isNotEmpty) {
          initialCamera = CameraPosition(
            target: firstPoints.first,
            zoom: 1.0,
          );
        }
      }
      final zoom = initialCamera?.zoom ?? state.cameraPosition?.zoom ?? 1.0;
      final rallyLogoVisible = zoom >= rallyLogoZoomMin && zoom <= rallyLogoZoomThreshold;
      emit(state.copyWith(
        stages: stages,
        stagePoints: stages.isEmpty ? await _stageRepo.loadStageCoordinates() : const [],
        closedRoads: {
          'closed_1': closed1,
          'closed_2': closed2,
          'closed_3': closed3,
        },
        cameraPosition: initialCamera,
        zoomLevel: zoom,
        rallyLogoVisible: rallyLogoVisible,
        isLoading: false,
        error: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: e.toString(),
      ));
    }
  }

  /// Call from onCameraIdle only (not on every camera move). Updates zoom level
  /// and rally logo visibility. Keeps pan/zoom smooth: no state emit during move,
  /// so polylines/markers do not rebuild and do not flicker.
  /// Logo visible when zoom in [0, 5] inclusive; hidden when zoom > 5.
  void onCameraIdle(CameraPosition position) {
    final zoom = position.zoom;
    final visible = zoom >= rallyLogoZoomMin && zoom <= rallyLogoZoomThreshold;
    if (state.zoomLevel == zoom && state.rallyLogoVisible == visible) return;
    emit(state.copyWith(
      cameraPosition: position,
      zoomLevel: zoom,
      rallyLogoVisible: visible,
    ));
  }

  /// Update camera position (e.g. after returning from Street View). Does not
  /// change overlays or trigger logo visibility; that happens on next idle.
  void setCameraPosition(CameraPosition position) {
    emit(state.copyWith(cameraPosition: position));
  }

  /// Part D: set route origin (long-press first pin).
  void setRouteOrigin(LatLng position) {
    emit(state.copyWith(routeOrigin: position));
  }

  /// Part D: set route destination (long-press second pin).
  void setRouteDestination(LatLng position) {
    emit(state.copyWith(routeDestination: position));
  }

  /// Part D: set route polyline and whether it crosses stage.
  void setRouteResult({
    required List<LatLng> points,
    required bool crossesStage,
    String? crossesStageMessage,
    List<LatLng>? waypoints,
  }) {
    emit(state.copyWith(
      routePoints: points,
      routeCrossesStage: crossesStage,
      routeCrossesStageMessage: crossesStageMessage,
      routeWaypoints: waypoints ?? const [],
    ));
  }

  /// Part D: clear user route.
  void clearRoute() {
    emit(state.copyWith(
      routeOrigin: null,
      routeDestination: null,
      routeWaypoints: [],
      routePoints: [],
      routeCrossesStage: false,
      routeCrossesStageMessage: '',
      isRouting: false,
    ));
  }

  /// Build fastest route. If it crosses a stage, fetch an alternate route
  /// using avoidance waypoints around the stage area.
  Future<void> buildRouteWithStageAvoidance() async {
    final origin = state.routeOrigin;
    final destination = state.routeDestination;
    if (origin == null || destination == null) return;
    if (_directions.apiKey.trim().isEmpty) {
      emit(state.copyWith(
        routeCrossesStageMessage:
            'Directions API key missing. Pass --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY',
      ));
      return;
    }
    emit(state.copyWith(isRouting: true, routeCrossesStageMessage: ''));
    try {
      final fastest = await _directions.getRoute(
        origin: origin,
        destination: destination,
      );
      if (fastest.length < 2) {
        emit(state.copyWith(
          isRouting: false,
          routePoints: [],
          routeWaypoints: [],
          routeCrossesStage: false,
          routeCrossesStageMessage: 'No route found between selected points.',
        ));
        return;
      }

      if (!routeCrossesStage(fastest)) {
        emit(state.copyWith(
          isRouting: false,
          routePoints: fastest,
          routeWaypoints: const [],
          routeCrossesStage: false,
          routeCrossesStageMessage: '',
        ));
        return;
      }

      final candidates = _buildAvoidanceWaypoints();
      for (final waypoint in candidates) {
        final alt = await _directions.getRoute(
          origin: origin,
          destination: destination,
          waypoints: [waypoint],
        );
        if (alt.length >= 2 && !routeCrossesStage(alt)) {
          emit(state.copyWith(
            isRouting: false,
            routePoints: alt,
            routeWaypoints: [waypoint],
            routeCrossesStage: false,
            routeCrossesStageMessage:
                'The fastest route crosses a stage. We\'ve rerouted you around.',
          ));
          return;
        }
      }

      // Fallback if all alternates still cross stages.
      emit(state.copyWith(
        isRouting: false,
        routePoints: fastest,
        routeWaypoints: const [],
        routeCrossesStage: true,
        routeCrossesStageMessage:
            'The fastest route crosses a stage. Alternate route is unavailable.',
      ));
    } catch (e) {
      emit(state.copyWith(
        isRouting: false,
        routeCrossesStageMessage: 'Unable to build route: $e',
      ));
    }
  }

  /// Part D: check if route crosses any stage (pure geometry).
  bool routeCrossesStage(List<LatLng> routePoints) {
    if (routePoints.length < 2) return false;
    for (final stagePoints in state.stages.values) {
      if (stagePoints.length < 2) continue;
      final refLat = stagePoints.first.latitude;
      if (polylinesIntersect(
        stagePoints,
        routePoints,
        refLat: refLat,
        toleranceMeters: 2.0,
      )) {
        return true;
      }
    }
    if (state.stagePoints.length >= 2) {
      final refLat = state.stagePoints.first.latitude;
      return polylinesIntersect(
        state.stagePoints,
        routePoints,
        refLat: refLat,
        toleranceMeters: 2.0,
      );
    }
    return false;
  }

  List<LatLng> _buildAvoidanceWaypoints() {
    final allStagePoints = <LatLng>[];
    for (final points in state.stages.values) {
      allStagePoints.addAll(points);
    }
    if (allStagePoints.isEmpty && state.stagePoints.isNotEmpty) {
      allStagePoints.addAll(state.stagePoints);
    }
    if (allStagePoints.isEmpty) return const [];

    var minLat = allStagePoints.first.latitude;
    var maxLat = allStagePoints.first.latitude;
    var minLon = allStagePoints.first.longitude;
    var maxLon = allStagePoints.first.longitude;
    for (final p in allStagePoints.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    const margin = 0.01; // roughly >1km, enough to steer around stage zone
    final north = maxLat + margin;
    final south = minLat - margin;
    final west = minLon - margin;
    final east = maxLon + margin;
    final midLat = (minLat + maxLat) / 2;
    final midLon = (minLon + maxLon) / 2;

    return [
      LatLng(north, midLon),
      LatLng(south, midLon),
      LatLng(midLat, west),
      LatLng(midLat, east),
      LatLng(north, west),
      LatLng(north, east),
      LatLng(south, west),
      LatLng(south, east),
    ];
  }
}

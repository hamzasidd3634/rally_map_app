import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Immutable map state for the map screen.
///
/// **Smooth UX (no jank):** State is only updated on initial load and on
/// [MapCubit.onCameraIdle], not on every camera move. Polylines and markers use
/// stable IDs (stage_1, stage_2, stage_3, closed_1, closed_2, closed_3, start_*, finish_*)
/// so the map does not flicker or rebuild overlays while panning/zooming.
class MapState extends Equatable {
  static const Object _unset = Object();

  const MapState({
    this.cameraPosition,
    this.stagePoints = const [],
    this.stages = const {},
    this.closedRoads = const {},
    this.rallyLogoVisible = true,
    this.zoomLevel = 4.0,
    this.isLoading = true,
    this.error,
    this.routeOrigin,
    this.routeDestination,
    this.routeWaypoints = const [],
    this.routePoints = const [],
    this.routeCrossesStage = false,
    this.routeCrossesStageMessage,
    this.isRouting = false,
  });

  final CameraPosition? cameraPosition;
  @Deprecated('Use stages instead')
  final List<LatLng> stagePoints;
  /// StageId -> points for each stage route (e.g. stage_1, stage_2, stage_3).
  final Map<String, List<LatLng>> stages;
  /// PolylineId -> points for closed roads
  final Map<String, List<LatLng>> closedRoads;
  final bool rallyLogoVisible;
  final double zoomLevel;
  final bool isLoading;
  final String? error;
  /// Part D: routing
  final LatLng? routeOrigin;
  final LatLng? routeDestination;
  final List<LatLng> routeWaypoints;
  final List<LatLng> routePoints;
  final bool routeCrossesStage;
  final String? routeCrossesStageMessage;
  final bool isRouting;

  static const _stageColors = [
    Colors.blue,
    Colors.orange,
    Color(0xFF9C27B0), // purple
  ];

  Set<Polyline> get polylines {
    final out = <Polyline>{};
    if (stages.isNotEmpty) {
      var colorIndex = 0;
      for (final e in stages.entries) {
        if (e.value.length >= 2) {
          out.add(Polyline(
            polylineId: PolylineId(e.key),
            points: e.value,
            color: _stageColors[colorIndex % _stageColors.length],
            width: 6,
          ));
          colorIndex++;
        }
      }
    } else if (stagePoints.length >= 2) {
      out.add(Polyline(
        polylineId: const PolylineId('stage'),
        points: stagePoints,
        color: Colors.blue,
        width: 6,
      ));
    }
    // Closed roads (GPX): red polylines near rally stages.
    for (final e in closedRoads.entries) {
      if (e.value.length >= 2) {
        out.add(Polyline(
          polylineId: PolylineId(e.key),
          points: e.value,
          color: Colors.red,
          width: 5,
        ));
      }
    }
    if (routePoints.length >= 2) {
      out.add(Polyline(
        polylineId: const PolylineId('user_route'),
        points: routePoints,
        color: Colors.green,
        width: 5,
      ));
    }
    return out;
  }

  Set<Marker> get markers {
    final out = <Marker>{};
    if (stages.isNotEmpty) {
      for (final e in stages.entries) {
        if (e.value.isNotEmpty) {
          out.add(Marker(
            markerId: MarkerId('start_${e.key}'),
            position: e.value.first,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ));
          out.add(Marker(
            markerId: MarkerId('finish_${e.key}'),
            position: e.value.last,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ));
        }
      }
    } else if (stagePoints.isNotEmpty) {
      out.add(Marker(
        markerId: const MarkerId('start'),
        position: stagePoints.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
      out.add(Marker(
        markerId: const MarkerId('finish'),
        position: stagePoints.last,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }
    if (routeOrigin != null) {
      out.add(Marker(
        markerId: const MarkerId('route_origin'),
        position: routeOrigin!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    if (routeDestination != null) {
      out.add(Marker(
        markerId: const MarkerId('route_destination'),
        position: routeDestination!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ));
    }
    for (var i = 0; i < routeWaypoints.length; i++) {
      out.add(Marker(
        markerId: MarkerId('route_waypoint_$i'),
        position: routeWaypoints[i],
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      ));
    }
    return out;
  }

  /// First stage's start (e.g. for rally logo). Prefers stages, then legacy stagePoints.
  LatLng? get stageStart {
    if (stages.isNotEmpty) {
      final pts = stages['stage_1'] ?? stages.values.firstWhere((p) => p.isNotEmpty, orElse: () => <LatLng>[]);
      return pts.isNotEmpty ? pts.first : null;
    }
    return stagePoints.isNotEmpty ? stagePoints.first : null;
  }
  /// First stage's end.
  LatLng? get stageEnd {
    if (stages.isNotEmpty) {
      final pts = stages['stage_1'] ?? stages.values.firstWhere((p) => p.isNotEmpty, orElse: () => <LatLng>[]);
      return pts.isNotEmpty ? pts.last : null;
    }
    return stagePoints.isNotEmpty ? stagePoints.last : null;
  }

  MapState copyWith({
    CameraPosition? cameraPosition,
    List<LatLng>? stagePoints,
    Map<String, List<LatLng>>? stages,
    Map<String, List<LatLng>>? closedRoads,
    bool? rallyLogoVisible,
    double? zoomLevel,
    bool? isLoading,
    Object? error = _unset,
    Object? routeOrigin = _unset,
    Object? routeDestination = _unset,
    List<LatLng>? routeWaypoints,
    List<LatLng>? routePoints,
    bool? routeCrossesStage,
    Object? routeCrossesStageMessage = _unset,
    bool? isRouting,
  }) {
    return MapState(
      cameraPosition: cameraPosition ?? this.cameraPosition,
      stagePoints: stagePoints ?? this.stagePoints,
      stages: stages ?? this.stages,
      closedRoads: closedRoads ?? this.closedRoads,
      rallyLogoVisible: rallyLogoVisible ?? this.rallyLogoVisible,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      routeOrigin: identical(routeOrigin, _unset) ? this.routeOrigin : routeOrigin as LatLng?,
      routeDestination: identical(routeDestination, _unset) ? this.routeDestination : routeDestination as LatLng?,
      routeWaypoints: routeWaypoints ?? this.routeWaypoints,
      routePoints: routePoints ?? this.routePoints,
      routeCrossesStage: routeCrossesStage ?? this.routeCrossesStage,
      routeCrossesStageMessage: identical(routeCrossesStageMessage, _unset)
          ? this.routeCrossesStageMessage
          : routeCrossesStageMessage as String?,
      isRouting: isRouting ?? this.isRouting,
    );
  }

  @override
  List<Object?> get props => [
        cameraPosition,
        stagePoints,
        stages,
        closedRoads,
        rallyLogoVisible,
        zoomLevel,
        isLoading,
        error,
        routeOrigin,
        routeDestination,
        routeWaypoints,
        routePoints,
        routeCrossesStage,
        routeCrossesStageMessage,
        isRouting,
      ];
}

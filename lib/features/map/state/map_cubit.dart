import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/shared/utils/douglas_peucker.dart';

import '../data/gpx_service.dart';
import '../data/stage_repository.dart';
import '../../routing/data/directions_client.dart';
import 'map_state.dart';

/// Rally logo visibility: shown when camera zoom is in [0, 5] inclusive, hidden when zoom > 5.
const double rallyLogoZoomThreshold = 5.0;
const double rallyLogoZoomMin = 0.0;
const double _stageBufferMeters = 60.0;
const double _stageSimplifyMeters = 20.0;
const double _detourOffsetMultiplierPrimary = 1.8;
const double _detourOffsetMultiplierFallback = 3.0;
const int _maxGraphNodes = 280;
const double _minNodeSpacingMeters = 30.0;
const double _maxEdgeMetersFloor = 5000.0;
const double _maxEdgeMetersCap = 20000.0;
const Duration _searchYield = Duration(milliseconds: 16);

class _RouteSearchResult {
  const _RouteSearchResult({
    required this.points,
    required this.waypoints,
  });

  final List<LatLng> points;
  final List<LatLng> waypoints;
}

class _StageSegment {
  _StageSegment(this.a, this.b)
      : minLat = math.min(a.latitude, b.latitude),
        maxLat = math.max(a.latitude, b.latitude),
        minLon = math.min(a.longitude, b.longitude),
        maxLon = math.max(a.longitude, b.longitude);
  final LatLng a;
  final LatLng b;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
}

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
  /// using deterministic geometry-based avoidance (visibility-graph style).
  Future<void> buildRouteWithStageAvoidance() async {
    final origin = state.routeOrigin;
    final destination = state.routeDestination;
    if (origin == null || destination == null) return;
    emit(state.copyWith(isRouting: true, routeCrossesStageMessage: ''));
    try {
      final stageSegments = _collectStageSegments();
      if (stageSegments.isEmpty) {
        emit(state.copyWith(
          isRouting: false,
          routePoints: [origin, destination],
          routeWaypoints: const [],
          routeCrossesStage: false,
          routeCrossesStageMessage: '',
        ));
        return;
      }

      if (_pointTooCloseToStages(origin, stageSegments, _stageBufferMeters) ||
          _pointTooCloseToStages(destination, stageSegments, _stageBufferMeters)) {
        emit(state.copyWith(
          isRouting: false,
          routePoints: const [],
          routeWaypoints: const [],
          routeCrossesStage: false,
          routeCrossesStageMessage: '',
        ));
        return;
      }

      final direct = [origin, destination];
      if (!_polylineIntersectsBufferedStages(
        direct,
        stageSegments,
        _stageBufferMeters,
      )) {
        emit(state.copyWith(
          isRouting: false,
          routePoints: direct,
          routeWaypoints: const [],
          routeCrossesStage: false,
          routeCrossesStageMessage: '',
        ));
        return;
      }

      emit(state.copyWith(
        routeCrossesStageMessage: 'Searching for alternative route...',
      ));

      final safe = await _searchUntilFound(
        origin: origin,
        destination: destination,
        stageSegments: stageSegments,
      );
      emit(state.copyWith(
        isRouting: false,
        routePoints: safe.points,
        routeWaypoints: safe.waypoints,
        routeCrossesStage: false,
        routeCrossesStageMessage:
            'The fastest route crosses a stage. We\'ve rerouted you around.',
      ));
      return;

      // Fallback if all alternates still cross stages.
      emit(state.copyWith(
        isRouting: false,
        routePoints: const [],
        routeWaypoints: const [],
        routeCrossesStage: false,
        routeCrossesStageMessage: '',
      ));
    } catch (e) {
      emit(state.copyWith(
        isRouting: false,
        routeCrossesStageMessage: 'Unable to build route: $e',
      ));
    }
  }

  _RouteSearchResult? _findSafeRouteVisibilityGraph({
    required LatLng origin,
    required LatLng destination,
    required List<_StageSegment> stageSegments,
    double detourScale = 1.0,
    double detailScale = 1.0,
  }) {
    final passes = <double>[
      _detourOffsetMultiplierPrimary * detourScale,
      _detourOffsetMultiplierFallback * detourScale,
    ];

    for (final multiplier in passes) {
      final nodes = _buildGraphNodes(
        origin,
        destination,
        stageSegments,
        _stageBufferMeters,
        multiplier,
        detailScale,
      );
      if (nodes.length < 2) continue;

      final maxEdgeMeters =
          _maxEdgeMeters(origin, destination) * math.sqrt(detourScale).clamp(1.0, 4.0);

      final path = _aStarPath(
        nodes,
        stageSegments,
        _stageBufferMeters,
        maxEdgeMeters,
      );
      if (path != null && path.length >= 2) {
        final waypoints = path.length > 2
            ? path.sublist(1, path.length - 1)
            : const <LatLng>[];
        return _RouteSearchResult(points: path, waypoints: waypoints);
      }
    }

    return null;
  }

  Future<_RouteSearchResult> _searchUntilFound({
    required LatLng origin,
    required LatLng destination,
    required List<_StageSegment> stageSegments,
  }) async {
    var detourScale = 1.0;
    var detailScale = 1.0;

    while (true) {
      final safe = _findSafeRouteVisibilityGraph(
        origin: origin,
        destination: destination,
        stageSegments: stageSegments,
        detourScale: detourScale,
        detailScale: detailScale,
      );
      if (safe != null) return safe;

      detourScale *= 1.35;
      detailScale = math.min(detailScale * 1.2, 4.0);
      await Future.delayed(_searchYield);
    }
  }

  List<LatLng>? _aStarPath(
    List<LatLng> nodes,
    List<_StageSegment> stageSegments,
    double bufferMeters,
    double maxEdgeMeters,
  ) {
    final start = 0;
    final goal = 1;

    final openSet = <int>{start};
    final cameFrom = <int, int>{};
    final gScore = <int, double>{start: 0.0};
    final fScore = <int, double>{
      start: _haversineMeters(nodes[start], nodes[goal]),
    };

    while (openSet.isNotEmpty) {
      int current = openSet.first;
      double bestF = fScore[current] ?? double.infinity;
      for (final idx in openSet) {
        final f = fScore[idx] ?? double.infinity;
        if (f < bestF) {
          bestF = f;
          current = idx;
        }
      }

      if (current == goal) {
        return _reconstructNodePath(cameFrom, nodes, current);
      }

      openSet.remove(current);

      for (var neighbor = 0; neighbor < nodes.length; neighbor++) {
        if (neighbor == current) continue;
        final d = _haversineMeters(nodes[current], nodes[neighbor]);
        if (d > maxEdgeMeters) continue;
        if (!_segmentClearOfStages(
          nodes[current],
          nodes[neighbor],
          stageSegments,
          bufferMeters,
        )) {
          continue;
        }

        final tentativeG = (gScore[current] ?? double.infinity) + d;
        final knownG = gScore[neighbor];
        if (knownG == null || tentativeG < knownG) {
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeG;
          fScore[neighbor] =
              tentativeG + _haversineMeters(nodes[neighbor], nodes[goal]);
          openSet.add(neighbor);
        }
      }
    }

    return null;
  }

  List<LatLng> _reconstructNodePath(
    Map<int, int> cameFrom,
    List<LatLng> nodes,
    int current,
  ) {
    final path = <LatLng>[nodes[current]];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      path.add(nodes[current]);
    }
    return path.reversed.toList();
  }

  List<LatLng> _buildGraphNodes(
    LatLng origin,
    LatLng destination,
    List<_StageSegment> stageSegments,
    double bufferMeters,
    double detourMultiplier,
    double detailScale,
  ) {
    final nodes = <LatLng>[origin, destination];

    final detours = _buildDetourPoints(
      stageSegments,
      bufferMeters * detourMultiplier,
      detailScale,
    );
    for (final p in detours) {
      if (_pointTooCloseToStages(p, stageSegments, bufferMeters)) continue;
      _addIfSpaced(nodes, p, _minNodeSpacingMeters);
    }

    if (nodes.length > _maxGraphNodes) {
      final trimmed = <LatLng>[nodes.first, nodes[1]];
      final stride = (nodes.length / _maxGraphNodes).ceil();
      for (var i = 2; i < nodes.length; i += stride) {
        trimmed.add(nodes[i]);
      }
      return trimmed;
    }

    return nodes;
  }

  List<LatLng> _buildDetourPoints(
    List<_StageSegment> stageSegments,
    double offsetMeters,
    double detailScale,
  ) {
    if (stageSegments.isEmpty) return const [];
    final out = <LatLng>[];

    final stride = (stageSegments.length / (120 * detailScale))
        .ceil()
        .clamp(1, 12);
    for (var i = 0; i < stageSegments.length; i += stride) {
      final seg = stageSegments[i];
      final pts = _offsetPerpendicularPoints(seg.a, seg.b, offsetMeters);
      out.addAll(pts);
    }

    final bounds = _stageBounds(stageSegments);
    if (bounds != null) {
      final minLat = bounds[0];
      final minLon = bounds[1];
      final maxLat = bounds[2];
      final maxLon = bounds[3];
      final expand = _metersToLatLon(offsetMeters, (minLat + maxLat) / 2);
      final latPad = expand[0];
      final lonPad = expand[1];
      out.add(LatLng(minLat - latPad, minLon - lonPad));
      out.add(LatLng(minLat - latPad, maxLon + lonPad));
      out.add(LatLng(maxLat + latPad, minLon - lonPad));
      out.add(LatLng(maxLat + latPad, maxLon + lonPad));
    }

    return out;
  }

  List<double>? _stageBounds(List<_StageSegment> segments) {
    if (segments.isEmpty) return null;
    var minLat = segments.first.a.latitude;
    var maxLat = segments.first.a.latitude;
    var minLon = segments.first.a.longitude;
    var maxLon = segments.first.a.longitude;
    for (final seg in segments) {
      for (final p in [seg.a, seg.b]) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLon) minLon = p.longitude;
        if (p.longitude > maxLon) maxLon = p.longitude;
      }
    }
    return [minLat, minLon, maxLat, maxLon];
  }

  List<double> _metersToLatLon(double meters, double refLat) {
    final metersPerDegLat = 111320.0;
    final metersPerDegLon =
        111320.0 * math.cos(refLat * math.pi / 180.0).abs().clamp(0.2, 1.0);
    return [meters / metersPerDegLat, meters / metersPerDegLon];
  }

  void _addIfSpaced(List<LatLng> nodes, LatLng point, double minMeters) {
    for (final existing in nodes) {
      if (_haversineMeters(existing, point) < minMeters) return;
    }
    nodes.add(point);
  }

  List<LatLng> _offsetPerpendicularPoints(
    LatLng a,
    LatLng b,
    double offsetMeters,
  ) {
    final mid = _segmentMidpoint(a, b);
    final refLat = mid.latitude;
    final refLon = mid.longitude;

    final localA = _toLocal(a, refLat, refLon);
    final localB = _toLocal(b, refLat, refLon);
    final dx = localB[0] - localA[0];
    final dy = localB[1] - localA[1];
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return const [];

    final nx = -dy / len;
    final ny = dx / len;
    final left = _fromLocal(
      mid,
      nx * offsetMeters,
      ny * offsetMeters,
    );
    final right = _fromLocal(
      mid,
      -nx * offsetMeters,
      -ny * offsetMeters,
    );
    return [left, right];
  }

  LatLng _segmentMidpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  List<double> _toLocal(LatLng p, double refLat, double refLon) {
    final metersPerDegLat = 111320.0;
    final metersPerDegLon =
        111320.0 * math.cos(refLat * math.pi / 180.0).abs().clamp(0.2, 1.0);
    return [
      (p.longitude - refLon) * metersPerDegLon,
      (refLat - p.latitude) * metersPerDegLat,
    ];
  }

  LatLng _fromLocal(LatLng origin, double dx, double dy) {
    final metersPerDegLat = 111320.0;
    final metersPerDegLon =
        111320.0 * math.cos(origin.latitude * math.pi / 180.0).abs().clamp(0.2, 1.0);
    final dLat = -dy / metersPerDegLat;
    final dLon = dx / metersPerDegLon;
    return LatLng(origin.latitude + dLat, origin.longitude + dLon);
  }

  double _maxEdgeMeters(LatLng origin, LatLng destination) {
    final d = _haversineMeters(origin, destination) * 1.5;
    return d.clamp(_maxEdgeMetersFloor, _maxEdgeMetersCap);
  }

  List<_StageSegment> _collectStageSegments() {
    final out = <_StageSegment>[];
    if (state.stages.isNotEmpty) {
      for (final stage in state.stages.values) {
        final simplified = _simplifyStage(stage);
        for (var i = 0; i < simplified.length - 1; i++) {
          out.add(_StageSegment(simplified[i], simplified[i + 1]));
        }
      }
      return out;
    }
    if (state.stagePoints.length >= 2) {
      final simplified = _simplifyStage(state.stagePoints);
      for (var i = 0; i < simplified.length - 1; i++) {
        out.add(_StageSegment(simplified[i], simplified[i + 1]));
      }
    }
    return out;
  }

  List<LatLng> _simplifyStage(List<LatLng> points) {
    if (points.length < 3) return points;
    return douglasPeucker(points, _stageSimplifyMeters);
  }

  bool _pointTooCloseToStages(
    LatLng point,
    List<_StageSegment> segments,
    double bufferMeters,
  ) {
    for (final seg in segments) {
      final d = _distancePointToSegmentMeters(point, seg.a, seg.b);
      if (d <= bufferMeters) return true;
    }
    return false;
  }

  bool _polylineIntersectsBufferedStages(
    List<LatLng> route,
    List<_StageSegment> segments,
    double bufferMeters,
  ) {
    if (route.length < 2) return false;
    for (var i = 0; i < route.length - 1; i++) {
      if (!_segmentClearOfStages(
        route[i],
        route[i + 1],
        segments,
        bufferMeters,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _segmentClearOfStages(
    LatLng a,
    LatLng b,
    List<_StageSegment> segments,
    double bufferMeters,
  ) {
    final midLat = (a.latitude + b.latitude) / 2;
    final latLonPad = _metersToLatLon(bufferMeters, midLat);
    final padLat = latLonPad[0];
    final padLon = latLonPad[1];
    final minLat = math.min(a.latitude, b.latitude) - padLat;
    final maxLat = math.max(a.latitude, b.latitude) + padLat;
    final minLon = math.min(a.longitude, b.longitude) - padLon;
    final maxLon = math.max(a.longitude, b.longitude) + padLon;

    for (final seg in segments) {
      if (seg.maxLat < minLat ||
          seg.minLat > maxLat ||
          seg.maxLon < minLon ||
          seg.minLon > maxLon) {
        continue;
      }
      final d = _segmentDistanceMeters(a, b, seg.a, seg.b);
      if (d <= bufferMeters) return false;
    }
    return true;
  }

  double _segmentDistanceMeters(
    LatLng a0,
    LatLng a1,
    LatLng b0,
    LatLng b1,
  ) {
    final refLat =
        (a0.latitude + a1.latitude + b0.latitude + b1.latitude) / 4.0;
    final refLon =
        (a0.longitude + a1.longitude + b0.longitude + b1.longitude) / 4.0;

    final p0 = _toLocal(a0, refLat, refLon);
    final p1 = _toLocal(a1, refLat, refLon);
    final q0 = _toLocal(b0, refLat, refLon);
    final q1 = _toLocal(b1, refLat, refLon);

    return _segmentDistanceLocal(p0, p1, q0, q1);
  }

  double _segmentDistanceLocal(
    List<double> p0,
    List<double> p1,
    List<double> q0,
    List<double> q1,
  ) {
    final ux = p1[0] - p0[0];
    final uy = p1[1] - p0[1];
    final vx = q1[0] - q0[0];
    final vy = q1[1] - q0[1];
    final wx = p0[0] - q0[0];
    final wy = p0[1] - q0[1];

    final a = ux * ux + uy * uy;
    final b = ux * vx + uy * vy;
    final c = vx * vx + vy * vy;
    final d = ux * wx + uy * wy;
    final e = vx * wx + vy * wy;
    final D = a * c - b * b;
    const eps = 1e-12;

    double sN;
    double sD = D;
    double tN;
    double tD = D;

    if (D < eps) {
      sN = 0.0;
      sD = 1.0;
      tN = e;
      tD = c;
    } else {
      sN = (b * e - c * d);
      tN = (a * e - b * d);

      if (sN < 0.0) {
        sN = 0.0;
        tN = e;
        tD = c;
      } else if (sN > sD) {
        sN = sD;
        tN = e + b;
        tD = c;
      }
    }

    if (tN < 0.0) {
      tN = 0.0;
      if (-d < 0.0) {
        sN = 0.0;
      } else if (-d > a) {
        sN = sD;
      } else {
        sN = -d;
        sD = a;
      }
    } else if (tN > tD) {
      tN = tD;
      if (-d + b < 0.0) {
        sN = 0.0;
      } else if (-d + b > a) {
        sN = sD;
      } else {
        sN = -d + b;
        sD = a;
      }
    }

    final sc = sN.abs() < eps ? 0.0 : sN / sD;
    final tc = tN.abs() < eps ? 0.0 : tN / tD;

    final dx = wx + sc * ux - tc * vx;
    final dy = wy + sc * uy - tc * vy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _distancePointToSegmentMeters(
    LatLng p,
    LatLng a,
    LatLng b,
  ) {
    final refLat = (p.latitude + a.latitude + b.latitude) / 3.0;
    final refLon = (p.longitude + a.longitude + b.longitude) / 3.0;
    final pl = _toLocal(p, refLat, refLon);
    final al = _toLocal(a, refLat, refLon);
    final bl = _toLocal(b, refLat, refLon);

    final dx = bl[0] - al[0];
    final dy = bl[1] - al[1];
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-12) {
      final ex = pl[0] - al[0];
      final ey = pl[1] - al[1];
      return math.sqrt(ex * ex + ey * ey);
    }
    var t = ((pl[0] - al[0]) * dx + (pl[1] - al[1]) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final qx = al[0] + t * dx;
    final qy = al[1] + t * dy;
    final ex = pl[0] - qx;
    final ey = pl[1] - qy;
    return math.sqrt(ex * ex + ey * ey);
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h = sinDLat * sinDLat +
        math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return r * c;
  }

  /// Part D: check if route crosses any buffered stage.
  bool routeCrossesStage(List<LatLng> routePoints) {
    if (routePoints.length < 2) return false;
    final segments = _collectStageSegments();
    return _polylineIntersectsBufferedStages(
      routePoints,
      segments,
      _stageBufferMeters,
    );
  }

}

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rally_map_app/shared/utils/douglas_peucker.dart';

import '../data/gpx_service.dart';
import '../data/stage_repository.dart';
import '../../routing/data/directions_client.dart';
import '../../routing/data/roads_client.dart';
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
const double _maxStopSpacingMeters = 2000.0;
const double _maxSnapDistanceMeters = 250.0;
const bool _logRouteFallbacks = true;
const String _presetPointsAsset = "assets/gpx/Doesn't work route.gpx";
const int _maxPresetPoints = 60;

class _RouteSearchResult {
  const _RouteSearchResult({
    required this.points,
    required this.waypoints,
  });

  final List<LatLng> points;
  final List<LatLng> waypoints;
}

class _IsolateRouteResult {
  const _IsolateRouteResult({
    required this.points,
    required this.waypoints,
    required this.detoured,
    required this.error,
  });

  final List<LatLng> points;
  final List<LatLng> waypoints;
  final bool detoured;
  final String? error;
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

@pragma('vm:entry-point')
class MapCubit extends Cubit<MapState> {
  MapCubit({
    StageRepository? stageRepository,
    GpxCache? gpxCache,
    DirectionsClient? directionsClient,
    String? directionsApiKey,
    CameraPosition? initialCamera,
  })  : _stageRepo = stageRepository ?? StageRepository(),
        _gpxCache = gpxCache ?? GpxCache(),
        _directionsApiKey = directionsApiKey ??
            directionsClient?.apiKey ??
            "AIzaSyAfmGm_et883qbzn8h_ML-5gwBMoXypQTs",
        _directions = directionsClient ??
            DirectionsClient(apiKey: directionsApiKey ??
                directionsClient?.apiKey ??
                "AIzaSyAfmGm_et883qbzn8h_ML-5gwBMoXypQTs"),
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
  final String _directionsApiKey;

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

  Future<List<LatLng>> loadPresetPoints({
    String assetPath = _presetPointsAsset,
    int maxPoints = _maxPresetPoints,
  }) async {
    final points = await _gpxCache.parseAndCache(assetPath);
    return _downsamplePoints(points, maxPoints);
  }

  List<LatLng> _downsamplePoints(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final step = (points.length / maxPoints).ceil();
    final out = <LatLng>[];
    for (var i = 0; i < points.length; i += step) {
      out.add(points[i]);
    }
    return out;
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
      final stagePolylines = _serializeStagePolylines();
      final result = await _runRoutingIsolate(
        origin: origin,
        destination: destination,
        stagePolylines: stagePolylines,
      );
      if (result == null || result.points.isEmpty) {
        emit(state.copyWith(
          isRouting: false,
          routeCrossesStage: false,
          routeCrossesStageMessage: '',
        ));
        return;
      }
      emit(state.copyWith(
        isRouting: false,
        routePoints: result.points,
        routeWaypoints: result.waypoints,
        routeCrossesStage: false,
        routeCrossesStageMessage: result.detoured
            ? 'The fastest route crosses a stage. We\'ve rerouted you around.'
            : '',
      ));
    } catch (e) {
      emit(state.copyWith(
        isRouting: false,
        routeCrossesStageMessage: 'Unable to build route: $e',
      ));
    }
  }

  List<List<List<double>>> _serializeStagePolylines() {
    final out = <List<List<double>>>[];
    if (state.stages.isNotEmpty) {
      for (final entry in state.stages.entries) {
        final stageId = entry.key;
        final stage = entry.value;
        if (stage.isEmpty) continue;
        out.add(stage
            .map((p) => <double>[p.latitude, p.longitude])
            .toList(growable: false));
        final closedKey = _closedRoadKeyForStage(stageId);
        if (closedKey != null && state.closedRoads.containsKey(closedKey)) {
          final road = state.closedRoads[closedKey]!;
          if (road.isNotEmpty) {
            out.add(road
                .map((p) => <double>[p.latitude, p.longitude])
                .toList(growable: false));
          }
        }
      }
    } else if (state.stagePoints.isNotEmpty) {
      out.add(state.stagePoints
          .map((p) => <double>[p.latitude, p.longitude])
          .toList(growable: false));
    }
    return out;
  }

  Future<_IsolateRouteResult?> _runRoutingIsolate({
    required LatLng origin,
    required LatLng destination,
    required List<List<List<double>>> stagePolylines,
  }) async {
    final receivePort = ReceivePort();
    FlutterIsolate? isolate;
    try {
      isolate = await FlutterIsolate.spawn(
        MapCubit._routingIsolateEntry,
        <String, dynamic>{
          'sendPort': receivePort.sendPort,
          'origin': <double>[origin.latitude, origin.longitude],
          'destination': <double>[destination.latitude, destination.longitude],
          'stages': stagePolylines,
          'apiKey': _directionsApiKey,
        },
      );
      final response = await receivePort.first
          .timeout(const Duration(seconds: 45));
      if (response is! Map) return null;
      if (response['error'] is String) {
        return _IsolateRouteResult(
          points: const [],
          waypoints: const [],
          detoured: false,
          error: response['error'] as String,
        );
      }
      final pointsRaw = response['points'] as List<dynamic>? ?? const [];
      final waypointsRaw = response['waypoints'] as List<dynamic>? ?? const [];
      final detoured = response['detoured'] == true;
      final points = pointsRaw
          .map((p) => LatLng(
                (p[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ))
          .toList(growable: false);
      final waypoints = waypointsRaw
          .map((p) => LatLng(
                (p[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ))
          .toList(growable: false);
      return _IsolateRouteResult(
        points: points,
        waypoints: waypoints,
        detoured: detoured,
        error: null,
      );
    } on TimeoutException {
      return null;
    } finally {
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _routingIsolateEntry(
    Map<String, dynamic> message,
  ) async {
    final sendPort = message['sendPort'] as SendPort;
    try {
      final originPair = message['origin'] as List<dynamic>;
      final destinationPair = message['destination'] as List<dynamic>;
      final origin = LatLng(
        (originPair[0] as num).toDouble(),
        (originPair[1] as num).toDouble(),
      );
      final destination = LatLng(
        (destinationPair[0] as num).toDouble(),
        (destinationPair[1] as num).toDouble(),
      );
      final apiKey = message['apiKey'] as String? ?? '';
      if (apiKey.isEmpty) {
        sendPort.send({'error': 'Directions API key missing.'});
        return;
      }
      final stageRaw = message['stages'] as List<dynamic>? ?? const [];
      final polylines = <List<LatLng>>[];
      for (final rawLine in stageRaw) {
        final list = rawLine as List<dynamic>;
        if (list.isEmpty) continue;
        polylines.add(list
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList(growable: false));
      }

      final stageSegments = _collectStageSegmentsFromPolylines(polylines);
      final directions = DirectionsClient(apiKey: apiKey);
      final roads = RoadsClient(apiKey: apiKey);
      if (stageSegments.isEmpty) {
        final road = await _safeDirectionsRoute(
          directions,
          origin: origin,
          destination: destination,
        );
        if (road.length >= 2) {
          sendPort.send({
            'points': road
                .map((p) => <double>[p.latitude, p.longitude])
                .toList(growable: false),
            'waypoints': const <List<double>>[],
            'detoured': false,
          });
          return;
        }
        if (_logRouteFallbacks) {
          // ignore: avoid_print
          print('Route fallback: direct road failed, using straight line.');
        }
        sendPort.send({
          'points': <List<double>>[
            <double>[origin.latitude, origin.longitude],
            <double>[destination.latitude, destination.longitude],
          ],
          'waypoints': const <List<double>>[],
          'detoured': false,
        });
        return;
      }

      final directRoad = await _safeDirectionsRoute(
        directions,
        origin: origin,
        destination: destination,
      );
      if (directRoad.length >= 2 &&
          !_polylineIntersectsBufferedStages(
            directRoad,
            stageSegments,
            _stageBufferMeters,
          )) {
        sendPort.send({
          'points': directRoad
              .map((p) => <double>[p.latitude, p.longitude])
              .toList(growable: false),
          'waypoints': const <List<double>>[],
          'detoured': false,
        });
        return;
      }

      final safe = await _searchRoadRouteUntilFound(
        origin: origin,
        destination: destination,
        stageSegments: stageSegments,
        directions: directions,
        roads: roads,
      );
      if (safe.points.isEmpty) {
        final fallback = await _forceWideSafeRoute(
          origin: origin,
          destination: destination,
          stageSegments: stageSegments,
          directions: directions,
          roads: roads,
        );
        if (fallback.points.isNotEmpty) {
          sendPort.send({
            'points': fallback.points
                .map((p) => <double>[p.latitude, p.longitude])
                .toList(growable: false),
            'waypoints': fallback.waypoints
                .map((p) => <double>[p.latitude, p.longitude])
                .toList(growable: false),
            'detoured': true,
          });
          return;
        }
        sendPort.send({
          'points': const <List<double>>[],
          'waypoints': const <List<double>>[],
          'detoured': false,
        });
        return;
      }
      sendPort.send({
        'points': safe.points
            .map((p) => <double>[p.latitude, p.longitude])
            .toList(growable: false),
        'waypoints': safe.waypoints
            .map((p) => <double>[p.latitude, p.longitude])
            .toList(growable: false),
        'detoured': true,
      });
    } catch (e) {
      sendPort.send({'error': e.toString()});
    }
  }

  static _RouteSearchResult? _findSafeRouteVisibilityGraph({
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

  static Future<List<LatLng>> _safeDirectionsRoute(
    DirectionsClient directions, {
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
  }) async {
    try {
      return await directions.getRoute(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
      );
    } catch (_) {
      return const [];
    }
  }

  static Future<_RouteSearchResult> _searchRoadRouteUntilFound({
    required LatLng origin,
    required LatLng destination,
    required List<_StageSegment> stageSegments,
    required DirectionsClient directions,
    required RoadsClient roads,
  }) async {
    var detourScale = 0.75;
    var detailScale = 1.0;
    var attempts = 0;
    List<LatLng>? bestRoute;
    List<LatLng>? bestWaypoints;
    double bestDistance = double.infinity;
    final startedAt = DateTime.now();
    const maxAttempts = 20;
    const maxDuration = Duration(seconds: 20);

    while (true) {
      attempts++;
      final safe = _findSafeRouteVisibilityGraph(
        origin: origin,
        destination: destination,
        stageSegments: stageSegments,
        detourScale: detourScale,
        detailScale: detailScale,
      );
      if (safe != null) {
        final built = await _buildRouteFromSafePath(
          safe.points,
          origin: origin,
          destination: destination,
          stageSegments: stageSegments,
          directions: directions,
          roads: roads,
        );
        if (built.points.isNotEmpty) {
          final distance = _polylineLengthMeters(built.points);
          if (distance < bestDistance) {
            bestDistance = distance;
            bestRoute = built.points;
            bestWaypoints = built.waypoints;
          }
        }
      }

      if (attempts >= maxAttempts ||
          DateTime.now().difference(startedAt) > maxDuration) {
        if (bestRoute != null) {
          return _RouteSearchResult(
            points: bestRoute!,
            waypoints: bestWaypoints ?? const [],
          );
        }
        return await _forceWideSafeRoute(
          origin: origin,
          destination: destination,
          stageSegments: stageSegments,
          directions: directions,
          roads: roads,
        );
      }

      detourScale *= 1.35;
      detailScale = math.min(detailScale * 1.2, 4.0);
      await Future.delayed(_searchYield);
    }
  }

  static Future<_RouteSearchResult> _buildRouteFromSafePath(
    List<LatLng> safePath, {
    required LatLng origin,
    required LatLng destination,
    required List<_StageSegment> stageSegments,
    required DirectionsClient directions,
    required RoadsClient roads,
  }) async {
    if (safePath.length < 2) {
      return _RouteSearchResult(points: const [], waypoints: const []);
    }
    final normalized = _splitPathByMaxSegment(
      safePath,
      _maxStopSpacingMeters,
    );
    final indices = List<int>.generate(normalized.length, (i) => i);
    final waypoints = normalized.length > 2
        ? normalized.sublist(1, normalized.length - 1)
        : const <LatLng>[];
    List<LatLng> snapped;
    try {
      snapped = await roads.snapToRoads(waypoints);
    } catch (_) {
      snapped = waypoints;
    }
    if (snapped.isEmpty && waypoints.isNotEmpty) {
      snapped = waypoints;
    }
    snapped = _constrainSnappedWaypoints(
      waypoints,
      snapped,
      _maxSnapDistanceMeters,
    );
    final roadNodes = <LatLng>[origin, ...snapped, destination];
    final route = <LatLng>[];
    for (var i = 0; i < roadNodes.length - 1; i++) {
      final roadSegment = await _safeDirectionsRoute(
        directions,
        origin: roadNodes[i],
        destination: roadNodes[i + 1],
      );
      final intersects = roadSegment.length >= 2 &&
          _polylineIntersectsBufferedStages(
            roadSegment,
            stageSegments,
            _stageBufferMeters,
          );
      if (roadSegment.length >= 2 && !intersects) {
        _appendSegment(route, roadSegment);
        continue;
      }
      if (_logRouteFallbacks) {
        final reason =
            roadSegment.length < 2 ? 'no road segment' : 'stage intersection';
        // ignore: avoid_print
        print('Route fallback: segment $i -> $reason, using straight line.');
      }
      final startIdx = indices[i];
      final endIdx = indices[i + 1];
      final fallback = _slicePath(normalized, startIdx, endIdx);
      _appendSegment(route, fallback);
    }
    if (route.length < 2) {
      return _RouteSearchResult(points: normalized, waypoints: snapped);
    }
    return _RouteSearchResult(points: route, waypoints: snapped);
  }

  static Future<_RouteSearchResult> _forceWideSafeRoute({
    required LatLng origin,
    required LatLng destination,
    required List<_StageSegment> stageSegments,
    required DirectionsClient directions,
    required RoadsClient roads,
  }) async {
    final forcedScale = _requiredDetourScale(origin, destination, stageSegments);
    final forcedOffset =
        _stageBufferMeters * _detourOffsetMultiplierFallback * forcedScale;
    final safe = _findSafeRouteVisibilityGraph(
      origin: origin,
      destination: destination,
      stageSegments: stageSegments,
      detourScale: forcedScale,
      detailScale: 4.0,
    );
    if (safe != null) {
      return _buildRouteFromSafePath(
        safe.points,
        origin: origin,
        destination: destination,
        stageSegments: stageSegments,
        directions: directions,
        roads: roads,
      );
    }

    final perimeter = _buildPerimeterFallbackPath(
      origin: origin,
      destination: destination,
      stageSegments: stageSegments,
      padMeters: forcedOffset,
    );
    if (perimeter == null) {
      return _RouteSearchResult(points: const [], waypoints: const []);
    }
    return _buildRouteFromSafePath(
      perimeter,
      origin: origin,
      destination: destination,
      stageSegments: stageSegments,
      directions: directions,
      roads: roads,
    );
  }

  static double _requiredDetourScale(
    LatLng origin,
    LatLng destination,
    List<_StageSegment> stageSegments,
  ) {
    final direct = _haversineMeters(origin, destination);
    final bounds = _stageBounds(stageSegments);
    var diag = 0.0;
    if (bounds != null) {
      diag = _haversineMeters(
        LatLng(bounds[0], bounds[1]),
        LatLng(bounds[2], bounds[3]),
      );
    }
    final targetOffset = math.max(direct, diag) * 1.5 + 2000.0;
    final scale = targetOffset / (_stageBufferMeters * _detourOffsetMultiplierFallback);
    return scale.clamp(1.0, 5000.0);
  }

  static List<LatLng>? _buildPerimeterFallbackPath({
    required LatLng origin,
    required LatLng destination,
    required List<_StageSegment> stageSegments,
    required double padMeters,
  }) {
    final bounds = _stageBounds(stageSegments);
    if (bounds == null) return null;
    final minLat = bounds[0];
    final minLon = bounds[1];
    final maxLat = bounds[2];
    final maxLon = bounds[3];
    final expand = _metersToLatLon(padMeters, (minLat + maxLat) / 2);
    final latPad = expand[0];
    final lonPad = expand[1];
    final south = minLat - latPad;
    final north = maxLat + latPad;
    final west = minLon - lonPad;
    final east = maxLon + lonPad;
    final midLat = (south + north) / 2;
    final midLon = (west + east) / 2;

    final nodes = <LatLng>[
      origin,
      destination,
      LatLng(south, west),
      LatLng(south, midLon),
      LatLng(south, east),
      LatLng(midLat, east),
      LatLng(north, east),
      LatLng(north, midLon),
      LatLng(north, west),
      LatLng(midLat, west),
    ];
    final maxEdge = math.max(
      _maxEdgeMeters(origin, destination) * 4.0,
      padMeters * 3.0,
    );
    return _aStarPath(nodes, stageSegments, _stageBufferMeters, maxEdge);
  }

  static List<LatLng> _constrainSnappedWaypoints(
    List<LatLng> original,
    List<LatLng> snapped,
    double maxSnapMeters,
  ) {
    if (original.length != snapped.length) return original;
    final out = <LatLng>[];
    for (var i = 0; i < original.length; i++) {
      final o = original[i];
      final s = snapped[i];
      if (_haversineMeters(o, s) > maxSnapMeters) {
        out.add(o);
      } else {
        out.add(s);
      }
    }
    return out;
  }

  static List<LatLng> _splitPathByMaxSegment(
    List<LatLng> path,
    double maxSegmentMeters,
  ) {
    if (path.length <= 1) return path;
    final out = <LatLng>[path.first];
    for (var i = 1; i < path.length; i++) {
      final a = out.last;
      final b = path[i];
      final d = _haversineMeters(a, b);
      if (d <= maxSegmentMeters) {
        out.add(b);
        continue;
      }
      final steps = (d / maxSegmentMeters).ceil();
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        out.add(_lerpLatLng(a, b, t));
      }
    }
    return out;
  }

  static List<LatLng> _slicePath(List<LatLng> path, int startIdx, int endIdx) {
    final safeStart = startIdx.clamp(0, path.length - 1);
    final safeEnd = endIdx.clamp(0, path.length - 1);
    if (safeStart == safeEnd) return [path[safeStart]];
    if (safeStart < safeEnd) {
      return path.sublist(safeStart, safeEnd + 1);
    }
    return path.sublist(safeEnd, safeStart + 1).reversed.toList();
  }

  static void _appendSegment(List<LatLng> out, List<LatLng> segment) {
    if (segment.isEmpty) return;
    if (out.isEmpty) {
      out.addAll(segment);
      return;
    }
    final start = segment.first;
    final last = out.last;
    if (start.latitude == last.latitude && start.longitude == last.longitude) {
      out.addAll(segment.sublist(1));
      return;
    }
    out.addAll(segment);
  }

  static LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  static double _polylineLengthMeters(List<LatLng> points) {
    if (points.length <= 1) return 0.0;
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += _haversineMeters(points[i - 1], points[i]);
    }
    return sum;
  }

  static List<LatLng>? _aStarPath(
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

  static List<LatLng> _reconstructNodePath(
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

  static List<LatLng> _buildGraphNodes(
    LatLng origin,
    LatLng destination,
    List<_StageSegment> stageSegments,
    double bufferMeters,
    double detourMultiplier,
    double detailScale,
  ) {
    final nodes = <LatLng>[origin, destination];

    final tightOffset = bufferMeters * 1.1;
    final tightFocusDetours = _buildFocusDetours(
      origin,
      destination,
      stageSegments,
      tightOffset,
    );
    for (final p in tightFocusDetours) {
      if (_pointTooCloseToStages(p, stageSegments, bufferMeters)) continue;
      _addIfSpaced(nodes, p, _minNodeSpacingMeters);
    }

    final detours = _buildDetourPoints(
      stageSegments,
      bufferMeters * detourMultiplier,
      detailScale,
    );
    for (final p in detours) {
      if (_pointTooCloseToStages(p, stageSegments, bufferMeters)) continue;
      _addIfSpaced(nodes, p, _minNodeSpacingMeters);
    }
    final focusDetours = _buildFocusDetours(
      origin,
      destination,
      stageSegments,
      bufferMeters * detourMultiplier,
    );
    for (final p in focusDetours) {
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

  static List<LatLng> _buildFocusDetours(
    LatLng origin,
    LatLng destination,
    List<_StageSegment> stageSegments,
    double offsetMeters,
  ) {
    if (stageSegments.isEmpty) return const [];
    final refLat = (origin.latitude + destination.latitude) / 2;
    final refLon = (origin.longitude + destination.longitude) / 2;
    final o = _toLocal(origin, refLat, refLon);
    final d = _toLocal(destination, refLat, refLon);
    final lx = d[0] - o[0];
    final ly = d[1] - o[1];
    final len2 = lx * lx + ly * ly;
    if (len2 < 1e-6) return const [];

    final scored = <MapEntry<_StageSegment, double>>[];
    for (final seg in stageSegments) {
      final mid = _segmentMidpoint(seg.a, seg.b);
      final m = _toLocal(mid, refLat, refLon);
      final t = ((m[0] - o[0]) * lx + (m[1] - o[1]) * ly) / len2;
      final cx = o[0] + t * lx;
      final cy = o[1] + t * ly;
      final dx = m[0] - cx;
      final dy = m[1] - cy;
      final dist2 = dx * dx + dy * dy;
      scored.add(MapEntry(seg, dist2));
    }
    scored.sort((a, b) => a.value.compareTo(b.value));
    final take = math.min(18, scored.length);
    final out = <LatLng>[];
    for (var i = 0; i < take; i++) {
      final seg = scored[i].key;
      out.addAll(_offsetPerpendicularPoints(seg.a, seg.b, offsetMeters));
    }
    return out;
  }

  static List<LatLng> _buildDetourPoints(
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

  static List<double>? _stageBounds(List<_StageSegment> segments) {
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

  static List<double> _metersToLatLon(double meters, double refLat) {
    final metersPerDegLat = 111320.0;
    final metersPerDegLon =
        111320.0 * math.cos(refLat * math.pi / 180.0).abs().clamp(0.2, 1.0);
    return [meters / metersPerDegLat, meters / metersPerDegLon];
  }

  static void _addIfSpaced(List<LatLng> nodes, LatLng point, double minMeters) {
    for (final existing in nodes) {
      if (_haversineMeters(existing, point) < minMeters) return;
    }
    nodes.add(point);
  }

  static List<LatLng> _offsetPerpendicularPoints(
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

  static LatLng _segmentMidpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  static List<double> _toLocal(LatLng p, double refLat, double refLon) {
    final metersPerDegLat = 111320.0;
    final metersPerDegLon =
        111320.0 * math.cos(refLat * math.pi / 180.0).abs().clamp(0.2, 1.0);
    return [
      (p.longitude - refLon) * metersPerDegLon,
      (refLat - p.latitude) * metersPerDegLat,
    ];
  }

  static LatLng _fromLocal(LatLng origin, double dx, double dy) {
    final metersPerDegLat = 111320.0;
    final metersPerDegLon =
        111320.0 * math.cos(origin.latitude * math.pi / 180.0).abs().clamp(0.2, 1.0);
    final dLat = -dy / metersPerDegLat;
    final dLon = dx / metersPerDegLon;
    return LatLng(origin.latitude + dLat, origin.longitude + dLon);
  }

  static double _maxEdgeMeters(LatLng origin, LatLng destination) {
    final d = _haversineMeters(origin, destination) * 1.5;
    return d.clamp(_maxEdgeMetersFloor, _maxEdgeMetersCap);
  }

  String? _closedRoadKeyForStage(String stageId) {
    if (stageId.isEmpty) return null;
    final match = RegExp(r'(\d+)').firstMatch(stageId);
    if (match == null) return null;
    return 'closed_${match.group(1)}';
  }

  List<_StageSegment> _collectStageSegments() {
    final out = <_StageSegment>[];
    if (state.stages.isNotEmpty) {
      for (final entry in state.stages.entries) {
        final stageId = entry.key;
        final stage = entry.value;
        final simplified = _simplifyStage(stage);
        for (var i = 0; i < simplified.length - 1; i++) {
          out.add(_StageSegment(simplified[i], simplified[i + 1]));
        }
        final closedKey = _closedRoadKeyForStage(stageId);
        if (closedKey != null && state.closedRoads.containsKey(closedKey)) {
          final road = state.closedRoads[closedKey]!;
          if (road.length >= 2) {
            final roadSimplified = _simplifyStage(road);
            for (var i = 0; i < roadSimplified.length - 1; i++) {
              out.add(_StageSegment(roadSimplified[i], roadSimplified[i + 1]));
            }
          }
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

  static List<_StageSegment> _collectStageSegmentsFromPolylines(
    List<List<LatLng>> polylines,
  ) {
    final out = <_StageSegment>[];
    for (final polyline in polylines) {
      if (polyline.length < 2) continue;
      final simplified = _simplifyStage(polyline);
      for (var i = 0; i < simplified.length - 1; i++) {
        out.add(_StageSegment(simplified[i], simplified[i + 1]));
      }
    }
    return out;
  }

  static List<LatLng> _simplifyStage(List<LatLng> points) {
    if (points.length < 3) return points;
    return douglasPeucker(points, _stageSimplifyMeters);
  }

  static bool _pointTooCloseToStages(
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

  static bool _polylineIntersectsBufferedStages(
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

  static bool _segmentClearOfStages(
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

  static double _segmentDistanceMeters(
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

  static double _segmentDistanceLocal(
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

  static double _distancePointToSegmentMeters(
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

  static double _haversineMeters(LatLng a, LatLng b) {
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

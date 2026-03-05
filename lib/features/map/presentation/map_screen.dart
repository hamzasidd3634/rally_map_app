import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rally_map_app/features/routing/domain/geometry/distance_to_polyline.dart';
import 'package:rally_map_app/features/routing/domain/geometry/projection.dart';
import 'package:rally_map_app/features/routing/domain/geometry/segment_intersection.dart';
import 'package:rally_map_app/features/routing/domain/export_google_maps_url.dart';

import '../../street_view/presentation/street_view_screen.dart';
import 'widgets/route_actions_panel.dart';
import 'widgets/route_hint_card.dart';
import '../state/map_cubit.dart';
import '../state/map_state.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _controller;
  BitmapDescriptor? _rallyLogoDescriptor;
  CameraPosition? _lastCameraPosition;

  @override
  void initState() {
    super.initState();
    _loadRallyLogo();
  }

  Future<void> _loadRallyLogo() async {
    final descriptor = await _getRallyLogoDescriptor();
    if (mounted) setState(() => _rallyLogoDescriptor = descriptor);
  }

  /// Rally logo overlay: use assets/images/rally_logo.png; fallback to default marker if missing/invalid.
  Future<BitmapDescriptor> _getRallyLogoDescriptor() async {
    try {
      const int targetWidthPx = 400; // try 60–100
      final ByteData data = await rootBundle.load('assets/images/rally_logo.png');

      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: targetWidthPx,
      );

      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? bytes =
      await fi.image.toByteData(format: ui.ImageByteFormat.png);

      if (bytes == null) {
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
      }

      return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
    } catch (_) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
    }
  }
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
  }

  void _onCameraMove(CameraPosition position) {
    _lastCameraPosition = position;
  }

  void _onCameraIdle() {
    if (_lastCameraPosition != null) {
      context.read<MapCubit>().onCameraIdle(_lastCameraPosition!);
    }
  }

  void _onTap(LatLng position) async {
    final cubit = context.read<MapCubit>();
    final state = cubit.state;
    final snapped = _snapToStageIfNear(position, state.stages, state.stagePoints);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => StreetViewScreen(initialPosition: snapped),
      ),
    );
  }

  void _onLongPress(LatLng position) {
    final cubit = context.read<MapCubit>();
    final state = cubit.state;
    if (state.routeOrigin == null || (state.routeOrigin != null && state.routeDestination != null)) {
      // Start a fresh route selection after two pins are already set.
      cubit.clearRoute();
      cubit.setRouteOrigin(position);
      return;
    }
    cubit.setRouteDestination(position);
  }

  Future<void> _exportRouteToGoogleMaps(MapState state) async {
    final origin = state.routeOrigin;
    final destination = state.routeDestination;
    if (origin == null || destination == null) return;
    final url = exportGoogleMapsDirectionsUrl(
      origin: origin,
      destination: destination,
      waypoints: state.routeWaypoints,
    );
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Google Maps URL.')),
      );
    }
  }

  /// If tap is within ~25m of any stage polyline, snap to closest point on that stage.
  LatLng _snapToStageIfNear(LatLng tap, Map<String, List<LatLng>> stages, List<LatLng> legacyStagePoints) {
    const refLat = 52.0;
    const thresholdMeters = 25.0;
    if (stages.isNotEmpty) {
      double minDist = double.infinity;
      LatLng? bestSnap;
      for (final points in stages.values) {
        if (points.length < 2) continue;
        final dist = distanceToPolylineMeters(tap.latitude, tap.longitude, points, refLat);
        if (dist <= thresholdMeters && dist < minDist) {
          minDist = dist;
          bestSnap = _closestPointOnPolyline(tap, points, refLat);
        }
      }
      if (bestSnap != null) return bestSnap;
      return tap;
    }
    if (legacyStagePoints.length < 2) return tap;
    final dist = distanceToPolylineMeters(tap.latitude, tap.longitude, legacyStagePoints, refLat);
    if (dist > thresholdMeters) return tap;
    return _closestPointOnPolyline(tap, legacyStagePoints, refLat);
  }

  LatLng _closestPointOnPolyline(LatLng point, List<LatLng> polyline, double refLat) {
    // Use first segment for simplicity; full impl would iterate all segments.
    if (polyline.isEmpty) return point;
    if (polyline.length == 1) return polyline.first;
    final proj = Projection(refLat);
    final refLon = polyline.first.longitude;
    final p = proj.toLocal(point.latitude, point.longitude, refLon);
    final pt = Point2(p[0], p[1]);
    var minD2 = double.infinity;
    var best = polyline.first;
    for (var i = 0; i < polyline.length - 1; i++) {
      final a = proj.toLocal(
        polyline[i].latitude,
        polyline[i].longitude,
        refLon,
      );
      final b = proj.toLocal(
        polyline[i + 1].latitude,
        polyline[i + 1].longitude,
        refLon,
      );
      final d2 = distanceToSegmentSquared(pt, Point2(a[0], a[1]), Point2(b[0], b[1]));
      if (d2 < minD2) {
        minD2 = d2;
        final t = _segmentClosestT(pt, Point2(a[0], a[1]), Point2(b[0], b[1]));
        final lat = polyline[i].latitude + t * (polyline[i + 1].latitude - polyline[i].latitude);
        final lon = polyline[i].longitude + t * (polyline[i + 1].longitude - polyline[i].longitude);
        best = LatLng(lat, lon);
      }
    }
    return best;
  }

  double _segmentClosestT(Point2 p, Point2 s0, Point2 s1) {
    final dx = s1.x - s0.x;
    final dy = s1.y - s0.y;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-20) return 0;
    var t = ((p.x - s0.x) * dx + (p.y - s0.y) * dy) / len2;
    return t.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<MapCubit, MapState>(
        listenWhen: (prev, curr) =>
            prev.routeCrossesStageMessage != curr.routeCrossesStageMessage &&
            (curr.routeCrossesStageMessage?.isNotEmpty ?? false),
        listener: (context, state) {
          final msg = state.routeCrossesStageMessage;
          if (msg == null || msg.isEmpty) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null) {
            return Center(child: Text('Error: ${state.error}'));
          }
          final initialPosition = state.cameraPosition ??
              const CameraPosition(target: LatLng(48.8610, 2.3610), zoom: 1.0);
          final polylines = state.polylines;
          final markers = state.markers;
          // Rally logo overlay: visible when zoom in [0, 5], anchored at rally location (stage 1 start).
          final rallyMarkers = <Marker>{};
          if (state.rallyLogoVisible &&
              state.stageStart != null &&
              _rallyLogoDescriptor != null) {
            rallyMarkers.add(Marker(
              markerId: const MarkerId('rally_logo'),
              position: state.stageStart!,
              icon: _rallyLogoDescriptor!,
              zIndexInt: 2,
              flat: true,
              anchor: const Offset(0.5, 0.5),
            ));
          }
          final allMarkers = {...markers, ...rallyMarkers};
          return Stack(
            children: [
              SizedBox.expand(
                child: GoogleMap(
                  initialCameraPosition: initialPosition,
                  polylines: polylines,
                  markers: allMarkers,
                  onMapCreated: _onMapCreated,
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                  onTap: _onTap,
                  onLongPress: _onLongPress,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: true,
                  myLocationButtonEnabled: false,
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: RouteHintCard(
                  routeOrigin: state.routeOrigin,
                  routeDestination: state.routeDestination,
                ),
              ),
              Positioned(
                right: 12,
                bottom: 16,
                child: RouteActionsPanel(
                  hasOrigin: state.routeOrigin != null,
                  hasDestination: state.routeDestination != null,
                  isRouting: state.isRouting,
                  onGetRoute: () => context.read<MapCubit>().buildRouteWithStageAvoidance(),
                  onClear: () => context.read<MapCubit>().clearRoute(),
                  onExport: () => _exportRouteToGoogleMaps(state),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

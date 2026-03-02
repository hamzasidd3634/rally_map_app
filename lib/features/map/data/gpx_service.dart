import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gpx/gpx.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../shared/utils/douglas_peucker.dart';

/// Result of parsing and simplifying one GPX file.
class GpxPolylineResult {
  const GpxPolylineResult(this.points);
  final List<LatLng> points;
}

/// Parses GPX XML string and returns list of LatLng. Runs on isolate via compute().
List<LatLng> parseGpxToLatLng(String xml, {double simplifyToleranceMeters = 5.0}) {
  final gpx = GpxReader().fromString(xml);
  final points = <LatLng>[];
  for (final trk in gpx.trks) {
    for (final seg in trk.trksegs) {
      for (final w in seg.trkpts) {
        if (w.lat != null && w.lon != null) {
          points.add(LatLng(w.lat!, w.lon!));
        }
      }
    }
  }
  if (points.length <= 2) return points;
  return douglasPeucker(points, simplifyToleranceMeters);
}

/// Cache for parsed+simplified GPX polylines. Parse once, reuse.
class GpxCache {
  GpxCache({this.simplifyToleranceMeters = 5.0});

  final double simplifyToleranceMeters;
  final Map<String, List<LatLng>> _cache = {};

  Future<List<LatLng>> parseAndCache(String assetPath) async {
    if (_cache.containsKey(assetPath)) return _cache[assetPath]!;
    final xml = await _loadAsset(assetPath);
    final points = await compute(
      _parseGpxIsolate,
      (xml, simplifyToleranceMeters),
    );
    _cache[assetPath] = points;
    return points;
  }

  List<LatLng>? getCached(String assetPath) => _cache[assetPath];

  Future<String> _loadAsset(String path) async {
    return await rootBundle.loadString(path);
  }
}

/// Top-level for compute: (xml, tolerance) -> list of LatLng.
List<LatLng> _parseGpxIsolate((String, double) input) {
  return parseGpxToLatLng(input.$1, simplifyToleranceMeters: input.$2);
}

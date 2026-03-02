import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Loads stage routes from assets/data/stageN.json.
/// Format per file: { "name": "Stage N", "coordinates": [[lat, lon], ...] }
class StageRepository {
  StageRepository({
    this.assetPath = 'assets/data/stage.json',
    this.stageAssetPaths = const [
      'assets/data/stage1.json',
      'assets/data/stage2.json',
      'assets/data/stage3.json',
    ],
  });

  final String assetPath;
  final List<String> stageAssetPaths;

  static List<LatLng> _parseCoordinates(List<dynamic>? coords) {
    if (coords == null) return [];
    return coords
        .map((e) {
          final list = e as List<dynamic>;
          if (list.length >= 2) {
            return LatLng(
              (list[0] is num) ? (list[0] as num).toDouble() : double.parse(list[0].toString()),
              (list[1] is num) ? (list[1] as num).toDouble() : double.parse(list[1].toString()),
            );
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();
  }

  /// Loads a single stage from [assetPath] (default stage.json).
  Future<List<LatLng>> loadStageCoordinates() async {
    final String json = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> data = jsonDecode(json) as Map<String, dynamic>;
    return _parseCoordinates(data['coordinates'] as List<dynamic>?);
  }

  /// Loads all stage routes (stage_1, stage_2, stage_3, ...). Skips missing files.
  Future<Map<String, List<LatLng>>> loadAllStages() async {
    final Map<String, List<LatLng>> out = {};
    for (var i = 0; i < stageAssetPaths.length; i++) {
      final path = stageAssetPaths[i];
      try {
        final String json = await rootBundle.loadString(path);
        final Map<String, dynamic> data = jsonDecode(json) as Map<String, dynamic>;
        final points = _parseCoordinates(data['coordinates'] as List<dynamic>?);
        if (points.length >= 2) {
          out['stage_${i + 1}'] = points;
        }
      } catch (_) {
        // Skip missing or invalid stage file
      }
    }
    return out;
  }
}

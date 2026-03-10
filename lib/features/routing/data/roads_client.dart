import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Client for Google Roads API (nearest roads).
class RoadsClient {
  RoadsClient({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _baseUrl = 'https://roads.googleapis.com/v1/nearestRoads';
  static const _maxPointsPerRequest = 100;

  /// Snap points to the nearest road. Returns the same number of points.
  /// Points without a snap response stay unchanged.
  Future<List<LatLng>> snapToRoads(List<LatLng> points) async {
    if (points.isEmpty) return const [];
    final out = <LatLng>[];
    for (var i = 0; i < points.length; i += _maxPointsPerRequest) {
      final chunk = points.sublist(
        i,
        (i + _maxPointsPerRequest).clamp(0, points.length),
      );
      final snapped = await _snapChunk(chunk);
      out.addAll(snapped);
    }
    return out;
  }

  Future<List<LatLng>> _snapChunk(List<LatLng> points) async {
    final pointsStr =
        points.map((p) => '${p.latitude},${p.longitude}').join('|');
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'points': pointsStr,
      'key': apiKey,
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Roads API error: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final snappedPoints = data['snappedPoints'] as List<dynamic>? ?? const [];
    final out = List<LatLng>.from(points);
    for (final item in snappedPoints) {
      final map = item as Map<String, dynamic>;
      final location = map['location'] as Map<String, dynamic>?;
      final originalIndex = map['originalIndex'] as int?;
      if (location == null || originalIndex == null) continue;
      if (originalIndex < 0 || originalIndex >= out.length) continue;
      out[originalIndex] = LatLng(
        (location['latitude'] as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      );
    }
    return out;
  }
}

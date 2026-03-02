import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Client for Google Directions API (fastest route).
class DirectionsClient {
  DirectionsClient({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  /// Request fastest driving route. Returns list of LatLng for the first route leg.
  Future<List<LatLng>> getRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
  }) async {
    final originStr =
        '${origin.latitude},${origin.longitude}';
    final destStr =
        '${destination.latitude},${destination.longitude}';
    final waypointsStr = waypoints?.isNotEmpty == true
        ? 'via:${waypoints!.map((w) => '${w.latitude},${w.longitude}').join('|')}'
        : null;
    final q = <String, String>{
      'origin': originStr,
      'destination': destStr,
      'mode': 'driving',
      'key': apiKey,
    };
    if (waypointsStr != null) q['waypoints'] = waypointsStr;
    final uri = Uri.parse(_baseUrl).replace(queryParameters: q);
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Directions API error: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw Exception('Directions API status: $status');
    }
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return [];
    final legs = (routes[0] as Map<String, dynamic>)['legs'] as List<dynamic>?;
    if (legs == null || legs.isEmpty) return [];
    final points = <LatLng>[];
    for (final leg in legs) {
      final steps = (leg as Map<String, dynamic>)['steps'] as List<dynamic>?;
      if (steps == null) continue;
      for (final step in steps) {
        final start = (step as Map<String, dynamic>)['start_location'];
        if (start != null) {
          points.add(LatLng(
            (start['lat'] as num).toDouble(),
            (start['lng'] as num).toDouble(),
          ));
        }
        final end = step['end_location'];
        if (end != null) {
          points.add(LatLng(
            (end['lat'] as num).toDouble(),
            (end['lng'] as num).toDouble(),
          ));
        }
      }
    }
    return _dedupeConsecutive(points);
  }

  List<LatLng> _dedupeConsecutive(List<LatLng> points) {
    if (points.length <= 1) return points;
    final out = <LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      if (p.latitude != out.last.latitude || p.longitude != out.last.longitude) {
        out.add(p);
      }
    }
    return out;
  }
}

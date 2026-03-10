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
    final points = <LatLng>[];
    final firstRoute = routes[0] as Map<String, dynamic>;
    final legs = firstRoute['legs'] as List<dynamic>?;
    if (legs == null || legs.isEmpty) {
      final overview = firstRoute['overview_polyline'] as Map<String, dynamic>?;
      final encoded = overview?['points'] as String?;
      if (encoded == null || encoded.isEmpty) return [];
      return _dedupeConsecutive(_decodePolyline(encoded));
    }
    for (final leg in legs) {
      final steps = (leg as Map<String, dynamic>)['steps'] as List<dynamic>?;
      if (steps == null) continue;
      for (final step in steps) {
        final stepMap = step as Map<String, dynamic>;
        final polyline = stepMap['polyline'] as Map<String, dynamic>?;
        final encoded = polyline?['points'] as String?;
        if (encoded != null && encoded.isNotEmpty) {
          points.addAll(_decodePolyline(encoded));
          continue;
        }
        final start = stepMap['start_location'];
        if (start != null) {
          points.add(LatLng(
            (start['lat'] as num).toDouble(),
            (start['lng'] as num).toDouble(),
          ));
        }
        final end = stepMap['end_location'];
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

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}

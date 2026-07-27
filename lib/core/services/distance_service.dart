import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/google_maps_config.dart';
import '../utils/trip_route_polyline_decode.dart';

class RouteDistanceResult {
  final double distanceKm;
  final int estimatedDurationMinutes;

  const RouteDistanceResult({
    required this.distanceKm,
    required this.estimatedDurationMinutes,
  });
}

class DistanceService {
  static const _googleMapsApiKey = GoogleMapsConfig.apiKey;

  Future<RouteDistanceResult?> calculateRoadDistance({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    if (_googleMapsApiKey.isEmpty) return null;

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin': '$originLatitude,$originLongitude',
        'destination': '$destinationLatitude,$destinationLongitude',
        'mode': 'driving',
        'key': _googleMapsApiKey,
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') return null;

    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) return null;

    final legs = routes.first['legs'];
    if (legs is! List || legs.isEmpty) return null;

    final leg = Map<String, dynamic>.from(legs.first as Map);
    final distance = Map<String, dynamic>.from(leg['distance'] as Map);
    final duration = Map<String, dynamic>.from(leg['duration'] as Map);
    final distanceMeters = distance['value'];
    final durationSeconds = duration['value'];

    if (distanceMeters is! num || durationSeconds is! num) return null;

    return RouteDistanceResult(
      distanceKm: distanceMeters.toDouble() / 1000,
      estimatedDurationMinutes: (durationSeconds / 60).round(),
    );
  }

  /// Multiple driving routes (like Google Maps alternatives). Requires
  /// `--dart-define=GOOGLE_MAPS_API_KEY=` with Directions API enabled.
  Future<List<DrivingRouteOption>> fetchDrivingRoutesWithAlternatives({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    if (_googleMapsApiKey.isEmpty) return [];

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin': '$originLatitude,$originLongitude',
        'destination': '$destinationLatitude,$destinationLongitude',
        'mode': 'driving',
        'alternatives': 'true',
        'key': _googleMapsApiKey,
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return [];

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') return [];

    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) return [];

    final out = <DrivingRouteOption>[];
    for (var i = 0; i < routes.length; i++) {
      final r = Map<String, dynamic>.from(routes[i] as Map);
      final overview = r['overview_polyline'];
      if (overview is! Map) continue;
      final encoded = overview['points'] as String?;
      if (encoded == null || encoded.isEmpty) continue;

      final pts = decodeGoogleEncodedPolyline(encoded);
      if (pts.length < 2) continue;

      var totalMeters = 0;
      var totalSeconds = 0;
      final legs = r['legs'];
      if (legs is List) {
        for (final leg in legs) {
          if (leg is! Map) continue;
          final dist = leg['distance'];
          final dur = leg['duration'];
          if (dist is Map && dist['value'] is num) {
            totalMeters += (dist['value'] as num).round();
          }
          if (dur is Map && dur['value'] is num) {
            totalSeconds += (dur['value'] as num).round();
          }
        }
      }

      out.add(
        DrivingRouteOption(
          polylinePoints: pts,
          distanceKm: totalMeters / 1000.0,
          durationMinutes: (totalSeconds / 60).round().clamp(1, 9999),
          routeIndex: i,
        ),
      );
    }
    return out;
  }
}

/// One candidate route from the Directions API (decoded polyline + summary).
class DrivingRouteOption {
  final List<LatLng> polylinePoints;
  final double distanceKm;
  final int durationMinutes;
  final int routeIndex;

  const DrivingRouteOption({
    required this.polylinePoints,
    required this.distanceKm,
    required this.durationMinutes,
    required this.routeIndex,
  });
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    final routes = await fetchDrivingRoutesWithAlternatives(
      originLatitude: originLatitude,
      originLongitude: originLongitude,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
    );
    if (routes.isEmpty) return null;
    final best = routes.first;
    return RouteDistanceResult(
      distanceKm: best.distanceKm,
      estimatedDurationMinutes: best.durationMinutes,
    );
  }

  /// Snap a GPS trail onto roads via Google Roads API (frontend-only).
  /// Chunks at 100 points (API limit).
  Future<List<LatLng>> snapPathToRoads(
    List<LatLng> path, {
    bool interpolate = true,
  }) async {
    if (path.length < 2) return const [];
    final sparse = _downsampleForSnap(path, maxPoints: 300);
    final viaDirect = await _snapViaGoogleDirect(
      sparse,
      interpolate: interpolate,
    );
    if (viaDirect.length >= 2) {
      debugPrint(
        'DistanceService: Snap-to-Roads OK '
        '(${sparse.length} → ${viaDirect.length})',
      );
    } else {
      debugPrint('DistanceService: Snap-to-Roads unavailable');
    }
    return viaDirect;
  }

  Future<List<LatLng>> _snapViaGoogleDirect(
    List<LatLng> path, {
    required bool interpolate,
  }) async {
    if (_googleMapsApiKey.isEmpty || path.length < 2) return const [];
    final out = <LatLng>[];
    for (final chunk in _chunk(path, 100)) {
      final pathParam =
          chunk.map((p) => '${p.latitude},${p.longitude}').join('|');
      final uri = Uri.https(
        'roads.googleapis.com',
        '/v1/snapToRoads',
        {
          'path': pathParam,
          'interpolate': interpolate ? 'true' : 'false',
          'key': _googleMapsApiKey,
        },
      );
      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          debugPrint(
            'DistanceService: Google snap HTTP ${response.statusCode} '
            'body=${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
          );
          return const [];
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) {
          debugPrint('DistanceService: Google snap error=${body['error']}');
          return const [];
        }
        final snapped = body['snappedPoints'];
        if (snapped is! List) return const [];
        for (final sp in snapped) {
          if (sp is! Map) continue;
          final loc = sp['location'];
          if (loc is! Map) continue;
          final lat = (loc['latitude'] as num?)?.toDouble();
          final lng = (loc['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          out.add(LatLng(lat, lng));
        }
      } catch (e) {
        debugPrint('DistanceService: Google snap direct failed: $e');
        return const [];
      }
    }
    return out;
  }

  List<List<LatLng>> _chunk(List<LatLng> path, int size) {
    if (path.isEmpty) return const [];
    final out = <List<LatLng>>[];
    for (var i = 0; i < path.length; i += size) {
      final end = (i + size > path.length) ? path.length : i + size;
      out.add(path.sublist(i, end));
    }
    return out;
  }

  List<LatLng> _downsampleForSnap(List<LatLng> path, {required int maxPoints}) {
    if (path.length <= maxPoints) return path;
    final step = (path.length / maxPoints).ceil().clamp(1, path.length);
    final out = <LatLng>[];
    for (var i = 0; i < path.length; i += step) {
      out.add(path[i]);
    }
    final last = path.last;
    if (out.last.latitude != last.latitude ||
        out.last.longitude != last.longitude) {
      out.add(last);
    }
    return out;
  }

  /// Driving routes for gap-fill / distance via Google Directions (frontend-only).
  Future<List<DrivingRouteOption>> fetchDrivingRoutesWithAlternatives({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    return _fetchViaGoogleDirect(
      originLatitude: originLatitude,
      originLongitude: originLongitude,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
    );
  }

  Future<List<DrivingRouteOption>> _fetchViaGoogleDirect({
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

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') {
        debugPrint(
            'DistanceService: Google Directions status=${body['status']}');
        return [];
      }

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
    } catch (e) {
      debugPrint('DistanceService: Google Directions direct failed: $e');
      return [];
    }
  }
}

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

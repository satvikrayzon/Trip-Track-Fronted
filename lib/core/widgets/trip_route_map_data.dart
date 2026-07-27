import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';

import '../database/hive_database.dart';
import '../utils/route_point_simplify.dart';
import '../utils/trip_route_polyline_decode.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import '../di/service_locator.dart';
import '../network/models/api_result.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../utils/geo_utils.dart';
import '../services/distance_service.dart';
import '../config/google_maps_config.dart';

final Map<String, List<LatLng>> _routePointsMemCache = {};
final Map<String, List<Map<String, dynamic>>> _rawRoutePointsMemCache = {};

/// Hive GPS samples first, then API route points, then leg polylines.
Future<List<LatLng>> loadTraveledRoutePoints(TravelRequestModel request) async {
  final cacheKey = request.requestId.isNotEmpty
      ? request.requestId
      : request.restResourceId;
  final rawCached = _rawRoutePointsMemCache[cacheKey];
  if (rawCached != null && rawCached.isNotEmpty) {
    return rawCached
        .map((p) => LatLng(
              (p['latitude'] as num).toDouble(),
              (p['longitude'] as num).toDouble(),
            ))
        .toList();
  }
  final cached = _routePointsMemCache[cacheKey];
  if (cached != null && cached.isNotEmpty) return cached;

  List<LatLng> result = const [];

  if (request.routePoints.isNotEmpty) {
    final fromApi = <LatLng>[];
    for (final p in request.routePoints) {
      final lat = (p['latitude'] as num?)?.toDouble();
      final lng = (p['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      fromApi.add(LatLng(lat, lng));
    }
    if (fromApi.isNotEmpty) result = fromApi;
  }

  if (result.isEmpty) {
    final raw =
        await HiveDatabase.instance.getRoutePointsForRequest(request.requestId);
    if (raw.isNotEmpty) {
      result = raw
          .map((m) => LatLng(
                (m['latitude'] as num).toDouble(),
                (m['longitude'] as num).toDouble(),
              ))
          .toList();
    }
  }

  if (result.isEmpty && ServiceLocator.I.has<TravelRequestRemoteDataSource>()) {
    final api = ServiceLocator.I.get<TravelRequestRemoteDataSource>();
    final res = await api.listRoutePoints(request.restResourceId);
    if (res case ApiSuccess(:final data)) {
      final fromApi = <LatLng>[];
      for (final p in data) {
        final lat = (p['latitude'] as num?)?.toDouble();
        final lng = (p['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        fromApi.add(LatLng(lat, lng));
      }
      if (fromApi.isNotEmpty) {
        result = fromApi;
        cacheServerRoutePoints(request.requestId, fromApi);
        _rawRoutePointsMemCache[cacheKey] = List<Map<String, dynamic>>.from(data);
      }
    }
  }

  if (result.isEmpty && (request.status == 'Completed' || request.tripEndedAt != null)) {
    final merged = <LatLng>[];
    for (final leg in request.tripLegs) {
      merged.addAll(decodePipePolyline(leg.routePolylineEncoded));
    }
    result = merged;
  }

  if (result.isNotEmpty && cacheKey.isNotEmpty) {
    _routePointsMemCache[cacheKey] = result;
  }
  return result;
}

Future<List<List<LatLng>>> loadTraveledLegPoints(TravelRequestModel request) async {
  final List<List<LatLng>> legPaths = [];
  
  if (request.tripLegs.isEmpty) {
    final pts = await loadTraveledRoutePoints(request);
    return pts.isNotEmpty ? [pts] : [];
  }

  List<({double lat, double lng, DateTime? time, String? legId})>? pointsWithTime;

  final allPointsMap = <Map<String, dynamic>>[];
  if (request.routePoints.isNotEmpty) {
    allPointsMap.addAll(request.routePoints);
  } else {
    final cacheKey = request.requestId.isNotEmpty ? request.requestId : request.restResourceId;
    final rawCached = _rawRoutePointsMemCache[cacheKey];
    if (rawCached != null && rawCached.isNotEmpty) {
      allPointsMap.addAll(rawCached);
    } else {
      final raw = await HiveDatabase.instance.getRoutePointsForRequest(request.requestId);
      allPointsMap.addAll(raw);
    }

    if (allPointsMap.isEmpty && ServiceLocator.I.has<TravelRequestRemoteDataSource>()) {
      final api = ServiceLocator.I.get<TravelRequestRemoteDataSource>();
      final res = await api.listRoutePoints(request.restResourceId);
      if (res case ApiSuccess(:final data)) {
        final rawList = data.map((d) => Map<String, dynamic>.from(d as Map)).toList();
        allPointsMap.addAll(rawList);
        _rawRoutePointsMemCache[cacheKey] = rawList;
        final pts = rawList.map((m) {
          final lat = (m['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (m['longitude'] as num?)?.toDouble() ?? 0.0;
          return LatLng(lat, lng);
        }).toList();
        cacheServerRoutePoints(request.requestId, pts);
      }
    }
  }

  pointsWithTime = allPointsMap.map((m) {
    final lat = (m['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (m['longitude'] as num?)?.toDouble() ?? 0.0;
    final tStr = m['timestamp']?.toString();
    final time = tStr != null ? DateTime.tryParse(tStr) : null;
    final legId = m['legId']?.toString();
    return (lat: lat, lng: lng, time: time, legId: legId);
  }).where((p) => p.lat != 0.0 && p.lng != 0.0).toList();

  for (final leg in request.tripLegs) {
    final path = <LatLng>[];
    if (leg.departurePunch != null) {
      final start = leg.departurePunch!.time.toUtc();
      final end = leg.arrivalPunch?.time.toUtc() ?? DateTime.now().toUtc();
      
      final legPointsWithTime = <({double lat, double lng, DateTime? time, String? legId})>[];
      for (final p in pointsWithTime) {
        if (p.legId != null && p.legId == leg.legId) {
          legPointsWithTime.add(p);
          continue;
        }
        if (p.legId == null && p.time != null) {
          final pTime = p.time!.toUtc();
          if (!pTime.isBefore(start) && !pTime.isAfter(end)) {
            legPointsWithTime.add(p);
          }
        }
      }

      legPointsWithTime.sort((a, b) {
        if (a.time == null && b.time == null) return 0;
        if (a.time == null) return 1;
        if (b.time == null) return -1;
        return a.time!.compareTo(b.time!);
      });

      final filledPath = <LatLng>[];
      if (legPointsWithTime.isNotEmpty) {
        filledPath.add(LatLng(legPointsWithTime.first.lat, legPointsWithTime.first.lng));
        final distanceService = DistanceService();

        for (int i = 1; i < legPointsWithTime.length; i++) {
          final prev = legPointsWithTime[i - 1];
          final next = legPointsWithTime[i];

          if (prev.time != null && next.time != null) {
            final timeDiff = next.time!.difference(prev.time!);
            if (timeDiff > const Duration(minutes: 5) && GoogleMapsConfig.isConfigured) {
              final directDist = GeoUtils.distanceMeters(
                prev.lat, prev.lng,
                next.lat, next.lng,
              );
              if (directDist > 150) {
                try {
                  final routes = await distanceService.fetchDrivingRoutesWithAlternatives(
                    originLatitude: prev.lat,
                    originLongitude: prev.lng,
                    destinationLatitude: next.lat,
                    destinationLongitude: next.lng,
                  );
                  if (routes.isNotEmpty) {
                    final routePoints = routes.first.polylinePoints;
                    for (int j = 1; j < routePoints.length - 1; j++) {
                      filledPath.add(routePoints[j]);
                    }
                  }
                } catch (_) {}
              }
            }
          }
          filledPath.add(LatLng(next.lat, next.lng));
        }
      }
      path.addAll(filledPath);
    }

    final simplifiedPath = simplifyRoutePointsForMap(path);
    if (simplifiedPath.length >= 2) {
      legPaths.add(simplifiedPath);
    } else if (leg.routePolylineEncoded != null && leg.routePolylineEncoded!.isNotEmpty) {
      legPaths.add(decodePipePolyline(leg.routePolylineEncoded));
    } else {
      legPaths.add(simplifiedPath);
    }
  }

  if (legPaths.every((path) => path.isEmpty) && pointsWithTime.isNotEmpty) {
    final fallbackPath = pointsWithTime.map((p) => LatLng(p.lat, p.lng)).toList();
    for (var i = 0; i < legPaths.length; i++) {
      legPaths[i] = fallbackPath;
    }
  } else if (request.tripLegs.length == 1 && legPaths.first.isEmpty && pointsWithTime.isNotEmpty) {
    legPaths[0] = pointsWithTime.map((p) => LatLng(p.lat, p.lng)).toList();
  }

  return legPaths;
}

/// Clears in-memory route cache after a fresh server fetch.
void cacheServerRoutePoints(String requestId, List<LatLng> points) {
  if (requestId.isEmpty || points.isEmpty) return;
  _routePointsMemCache[requestId] = List<LatLng>.from(points);
}

/// Clears in-memory route cache after deletion.
void evictRoutePointsCache(String id) {
  if (id.isEmpty) return;
  _routePointsMemCache.remove(id);
  _rawRoutePointsMemCache.remove(id);
}

/// Display-ready path (decimated for map performance).
List<LatLng> mapDisplayRoutePoints(List<LatLng> points) =>
    simplifyRoutePointsForMap(points);

/// Best-effort start point for map initial camera (from coordinates or punches).
LatLng? tripMapStartTarget(TravelRequestModel r) {
  final ends = tripDrivingEndpoints(r);
  if (ends.origin != null) return ends.origin;

  for (final leg in r.tripLegs) {
    final dep = leg.departurePunch;
    if (dep != null) return LatLng(dep.latitude, dep.longitude);
  }

  if (r.routePoints.isNotEmpty) {
    final lat = (r.routePoints.first['latitude'] as num?)?.toDouble();
    final lng = (r.routePoints.first['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
  }

  for (final leg in r.tripLegs) {
    final decoded = decodePipePolyline(leg.routePolylineEncoded);
    if (decoded.isNotEmpty) return decoded.first;
  }

  return null;
}

/// Best-effort destination for planned-route markers.
LatLng? tripMapDestinationTarget(TravelRequestModel r) {
  final ends = tripDrivingEndpoints(r);
  if (ends.dest != null) return ends.dest;

  for (final leg in r.tripLegs.reversed) {
    final arr = leg.arrivalPunch;
    if (arr != null) return LatLng(arr.latitude, arr.longitude);
  }
  return null;
}

/// Best-effort start/end for driving directions (coordinates or punches).
({LatLng? origin, LatLng? dest}) tripDrivingEndpoints(TravelRequestModel r) {
  LatLng? fromCoord(Map<String, double>? m) {
    if (m == null) return null;
    final lat = m['latitude'];
    final lng = m['longitude'];
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  var origin = fromCoord(r.startCoordinates);
  var dest = fromCoord(r.endCoordinates);

  if (origin == null) {
    for (final leg in r.tripLegs) {
      final p = leg.departurePunch;
      if (p != null) {
        origin = LatLng(p.latitude, p.longitude);
        break;
      }
    }
  }
  if (dest == null) {
    for (final leg in r.tripLegs.reversed) {
      final p = leg.arrivalPunch;
      if (p != null) {
        dest = LatLng(p.latitude, p.longitude);
        break;
      }
    }
  }
  return (origin: origin, dest: dest);
}

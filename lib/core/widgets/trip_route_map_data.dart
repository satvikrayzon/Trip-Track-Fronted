import 'dart:async';

import 'package:flutter/material.dart' show Offset;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../database/hive_database.dart';
import '../utils/geo_utils.dart';
import '../utils/map_marker_icon.dart';
import '../utils/route_point_simplify.dart';
import '../utils/trip_route_polyline_decode.dart';
import '../../modules/travel/data/models/route_segment_model.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import '../di/service_locator.dart';
import '../network/models/api_result.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../services/gps_gap_road_fill.dart';
import '../services/map_matching_service.dart';
import '../services/road_aligned_route_service.dart';

final Map<String, List<LatLng>> _routePointsMemCache = {};
final Map<String, List<Map<String, dynamic>>> _rawRoutePointsMemCache = {};
final Map<String, List<List<List<LatLng>>>> _alignedPaintMemCache = {};

String _alignedPaintSignature(TravelRequestModel r) {
  final punches = r.tripLegs
      .map((e) =>
          '${e.legId}:${e.departurePunch?.time.toUtc().toIso8601String()}:'
          '${e.arrivalPunch?.time.toUtc().toIso8601String()}')
      .join(';');
  return '${r.requestId}|${r.status}|$punches|rpc=${r.routePointCount}';
}

List<List<List<LatLng>>>? _decodeAlignedCache(Map<String, dynamic> row) {
  final legsRaw = row['legs'];
  if (legsRaw is! List || legsRaw.isEmpty) return null;
  final out = <List<List<LatLng>>>[];
  for (final leg in legsRaw) {
    if (leg is! Map) continue;
    final segsRaw = leg['segments'];
    if (segsRaw is! List) continue;
    final segs = <List<LatLng>>[];
    for (final seg in segsRaw) {
      if (seg is! List) continue;
      final pts = <LatLng>[];
      for (final p in seg) {
        if (p is! Map) continue;
        final lat = (p['lat'] as num?)?.toDouble();
        final lng = (p['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        pts.add(LatLng(lat, lng));
      }
      if (pts.length >= 2) segs.add(pts);
    }
    out.add(segs);
  }
  if (!out.any((leg) => leg.any((s) => s.length >= 2))) return null;
  return out;
}

Map<String, dynamic> _encodeAlignedCache(
  String signature,
  List<List<List<LatLng>>> legs,
) {
  return {
    'signature': signature,
    'legs': [
      for (final leg in legs)
        {
          'segments': [
            for (final seg in leg)
              [
                for (final p in seg)
                  {'lat': p.latitude, 'lng': p.longitude},
              ],
          ],
        },
    ],
  };
}

Future<void> _saveAlignedPaintCache(
  TravelRequestModel request,
  List<List<List<LatLng>>> legs,
) async {
  final id = request.requestId.isNotEmpty
      ? request.requestId
      : request.restResourceId;
  if (id.isEmpty) return;
  if (!legs.any((leg) => leg.any((s) => s.length >= 2))) return;
  final sig = _alignedPaintSignature(request);
  _alignedPaintMemCache[id] = legs;
  try {
    await HiveDatabase.instance.saveAlignedRouteCache(
      id,
      _encodeAlignedCache(sig, legs),
    );
  } catch (_) {}
}

Future<List<List<List<LatLng>>>?> _loadAlignedPaintCache(
  TravelRequestModel request,
) async {
  final id = request.requestId.isNotEmpty
      ? request.requestId
      : request.restResourceId;
  if (id.isEmpty) return null;
  final sig = _alignedPaintSignature(request);

  final mem = _alignedPaintMemCache[id];
  if (mem != null && mem.any((leg) => leg.any((s) => s.length >= 2))) {
    return mem;
  }

  try {
    final row = await HiveDatabase.instance.getAlignedRouteCache(id);
    if (row == null) return null;
    if (row['signature']?.toString() != sig) return null;
    final decoded = _decodeAlignedCache(row);
    if (decoded != null) {
      _alignedPaintMemCache[id] = decoded;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}

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

/// Gap-filled trail as contiguous segments (for single-path map cards).
Future<List<List<LatLng>>> loadTraveledRoutePointsFilled(
  TravelRequestModel request,
) async {
  // One chronological fill for the whole trip — avoids stacking leg polylines.
  final whole = await loadWholeTripPathFilled(request);
  if (whole.isNotEmpty) return whole;

  final legs = await loadTraveledLegPoints(request);
  if (legs.isEmpty) return const [];
  return [
    for (final leg in legs)
      for (final seg in leg)
        if (seg.length >= 2) simplifyRoutePointsForMap(seg),
  ];
}

/// Single chronologically sorted path: GPS merged onto Google roads.
Future<List<List<LatLng>>> loadWholeTripPathFilled(
  TravelRequestModel request,
) async {
  // ignore: avoid_print
  print(
    '[ROAD_ALIGN] loadWholeTripPathFilled START '
    'id=${request.requestId} status=${request.status} build=v8-local-cache',
  );

  if (!_isLiveTrackingStatus(request.status)) {
    final cached = await _loadAlignedPaintCache(request);
    if (cached != null && cached.isNotEmpty) {
      final flat = <List<LatLng>>[
        for (final leg in cached)
          for (final seg in leg)
            if (seg.length >= 2) seg,
      ];
      if (flat.isNotEmpty) {
        // ignore: avoid_print
        print('[ROAD_ALIGN] whole-path CACHE HIT segs=${flat.length}');
        return flat;
      }
    }
  }

  final pointsWithTime = await _loadRoutePointsWithTime(request);
  // ignore: avoid_print
  print(
    '[ROAD_ALIGN] loaded raw GPS samples=${pointsWithTime.length}',
  );
  if (pointsWithTime.length < 2) {
    // ignore: avoid_print
    print('[ROAD_ALIGN] ABORT: <2 GPS samples — nothing to paint');
    return const [];
  }

  final sorted = List<
      ({
        double lat,
        double lng,
        DateTime? time,
        String? legId,
        String? source,
        String? pointId,
      })>.from(pointsWithTime)
    ..sort((a, b) {
      if (a.time == null && b.time == null) return 0;
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return a.time!.compareTo(b.time!);
    });

  final input = <GpsGapInputPoint>[];
  for (final p in sorted) {
    final next = GpsGapInputPoint(
      lat: p.lat,
      lng: p.lng,
      time: p.time,
      source: p.source,
      pointId: p.pointId,
    );
    if (input.isEmpty) {
      input.add(next);
      continue;
    }
    final prev = input.last;
    final d = GeoUtils.distanceMeters(prev.lat, prev.lng, next.lat, next.lng);
    if (d < 15) continue;
    input.add(next);
  }
  // ignore: avoid_print
  print('[ROAD_ALIGN] after 15m dedupe input=${input.length}');
  if (input.length < 2) {
    // ignore: avoid_print
    print('[ROAD_ALIGN] ABORT: <2 after dedupe');
    return const [];
  }

  final aligned = await RoadAlignedRouteService().align(
    gpsPoints: input,
    anchorStart: _tripPunchStart(request),
    anchorEnd: _tripPunchEnd(request),
  );
  if (!aligned.isEmpty) {
    final pieces = RoadAlignedRouteService().toMapPieces(aligned);
    // ignore: avoid_print
    print(
      '[ROAD_ALIGN] PAINT engine=${aligned.engine} '
      'alignedPts=${aligned.points.length} pieces=${pieces.length} '
      'km=${aligned.distanceKm.toStringAsFixed(2)}',
    );
    await _saveAlignedPaintCache(request, [pieces]);
    return pieces;
  }

  // ignore: avoid_print
  print('[ROAD_ALIGN] align empty → trying matched-route fallback');
  final matched = await loadMatchedRouteSegments(request);
  final matchedPts = <LatLng>[];
  for (final seg in matched) {
    matchedPts.addAll(decodePipePolyline(seg.polylineEncoded));
  }
  if (matchedPts.length >= 2) {
    // ignore: avoid_print
    print(
      '[ROAD_ALIGN] PAINT matched-route fallback pts=${matchedPts.length}',
    );
    return _piecesFromPath(matchedPts);
  }
  // ignore: avoid_print
  print('[ROAD_ALIGN] PAINT nothing — empty path');
  return const [];
}

List<List<LatLng>> _piecesFromPath(List<LatLng> path) {
  return [
    for (final piece in breakLongMapEdges(
      simplifyRoutePointsForMap(path),
      maxEdgeMeters: kMapMaxEdgeMeters,
    ))
      if (piece.length >= 2) piece,
  ];
}

double pathLengthMeters(List<LatLng> pts) {
  var m = 0.0;
  for (var i = 1; i < pts.length; i++) {
    m += GeoUtils.distanceMeters(
      pts[i - 1].latitude,
      pts[i - 1].longitude,
      pts[i].latitude,
      pts[i].longitude,
    );
  }
  return m;
}

Future<
    List<
        ({
          double lat,
          double lng,
          DateTime? time,
          String? legId,
          String? source,
          String? pointId,
        })>> _loadRoutePointsWithTime(TravelRequestModel request) async {
  final requestId = request.requestId.isNotEmpty
      ? request.requestId
      : request.restResourceId;
  final allPointsMap = <Map<String, dynamic>>[];
  final isLive = _isLiveTrackingStatus(request.status);

  // 1) Memory cache
  final rawCached = _rawRoutePointsMemCache[requestId];
  if (rawCached != null && rawCached.isNotEmpty) {
    allPointsMap.addAll(rawCached);
  }

  // 2) Hive GPS first — reopen details should not wait on the network.
  if (allPointsMap.isEmpty) {
    try {
      final hive = await HiveDatabase.instance
          .getRoutePointsForRequest(request.requestId);
      for (final raw in hive) {
        final m = Map<String, dynamic>.from(raw);
        final source = m['source']?.toString() ?? '';
        if (source == GpsGapRoadFill.fillerSource) continue;
        allPointsMap.add(m);
      }
      if (allPointsMap.isNotEmpty) {
        _rawRoutePointsMemCache[requestId] =
            List<Map<String, dynamic>>.from(allPointsMap);
      }
    } catch (_) {}
  }

  // 3) Server refresh only when live, or when we have no local points.
  final needsServer = isLive || allPointsMap.isEmpty;
  if (needsServer &&
      ServiceLocator.I.has<TravelRequestRemoteDataSource>() &&
      request.restResourceId.isNotEmpty) {
    try {
      final api = ServiceLocator.I.get<TravelRequestRemoteDataSource>();
      final res = await api.listRoutePoints(request.restResourceId);
      if (res case ApiSuccess(:final data)) {
        if (data.isNotEmpty) {
          final rawList =
              data.map((d) => Map<String, dynamic>.from(d as Map)).toList();
          allPointsMap
            ..clear()
            ..addAll(rawList);
          _rawRoutePointsMemCache[requestId] = rawList;
          cacheServerRoutePoints(
            requestId,
            rawList
                .map(
                  (m) => LatLng(
                    (m['latitude'] as num?)?.toDouble() ?? 0.0,
                    (m['longitude'] as num?)?.toDouble() ?? 0.0,
                  ),
                )
                .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
                .toList(),
          );
          // Persist server GPS locally for the next open.
          try {
            final hive = HiveDatabase.instance;
            for (final m in rawList) {
              final id = m['pointId']?.toString();
              if (id == null || id.isEmpty) continue;
              await hive.saveRoutePoint({
                ...m,
                'requestId': request.requestId,
                'isSynced': true,
              });
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  if (allPointsMap.isEmpty && request.routePoints.isNotEmpty) {
    allPointsMap.addAll(request.routePoints);
  }

  final hasServerOrLocal = allPointsMap.isNotEmpty;

  // 4) Merge unsynced local GPS when we already have a base trail.
  if (hasServerOrLocal) {
    try {
      final hive = await HiveDatabase.instance
          .getRoutePointsForRequest(request.requestId);
      for (final raw in hive) {
        final m = Map<String, dynamic>.from(raw);
        final source = m['source']?.toString() ?? '';
        if (m['isSynced'] == true) continue;
        if (source == GpsGapRoadFill.fillerSource ||
            source == 'gap_resume' ||
            source.contains('gap')) {
          continue;
        }
        if (_isNearDuplicateOfAny(allPointsMap, m)) continue;
        allPointsMap.add(m);
      }
    } catch (_) {}
  }

  final normalized = allPointsMap
      .map((m) {
        final lat = (m['latitude'] as num?)?.toDouble() ??
            (m['lat'] as num?)?.toDouble() ??
            0.0;
        final lng = (m['longitude'] as num?)?.toDouble() ??
            (m['lng'] as num?)?.toDouble() ??
            0.0;
        final time = GpsGapRoadFill.parseTimestamp(m['timestamp']);
        final legId = m['legId']?.toString();
        final source = m['source']?.toString();
        final pointId = m['pointId']?.toString();
        return (
          lat: lat,
          lng: lng,
          time: time,
          legId: legId,
          source: source,
          pointId: pointId,
        );
      })
      .where((p) => p.lat != 0.0 && p.lng != 0.0)
      .toList();

  // ignore: avoid_print
  print(
    '[ROAD_ALIGN] route samples localFirst=${allPointsMap.length} '
    'afterDedupe=${normalized.length} live=$isLive '
    'needsServer=$needsServer',
  );

  return _dedupeRouteSamples(normalized);
}

/// Actively tracking — needs fresh server tips.
bool _isLiveTrackingStatus(String status) {
  final s = status.trim();
  return s == 'Travelling' || s == 'Returning';
}

bool _isNearDuplicateOfAny(
  List<Map<String, dynamic>> existing,
  Map<String, dynamic> candidate, {
  double maxMeters = 25,
  int maxSeconds = 12,
}) {
  final cLat = (candidate['latitude'] as num?)?.toDouble() ??
      (candidate['lat'] as num?)?.toDouble();
  final cLng = (candidate['longitude'] as num?)?.toDouble() ??
      (candidate['lng'] as num?)?.toDouble();
  if (cLat == null || cLng == null) return true;
  final cTime = GpsGapRoadFill.parseTimestamp(candidate['timestamp']);
  final cId = candidate['pointId']?.toString();

  for (final m in existing) {
    final id = m['pointId']?.toString();
    if (cId != null && cId.isNotEmpty && id == cId) return true;

    final lat = (m['latitude'] as num?)?.toDouble() ??
        (m['lat'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble() ??
        (m['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) continue;

    final d = GeoUtils.distanceMeters(lat, lng, cLat, cLng);
    if (d > maxMeters) continue;

    final t = GpsGapRoadFill.parseTimestamp(m['timestamp']);
    if (cTime != null && t != null) {
      if (cTime.difference(t).abs() <= Duration(seconds: maxSeconds)) {
        return true;
      }
    } else if (d < 12) {
      return true;
    }
  }
  return false;
}

List<
    ({
      double lat,
      double lng,
      DateTime? time,
      String? legId,
      String? source,
      String? pointId,
    })> _dedupeRouteSamples(
  List<
      ({
        double lat,
        double lng,
        DateTime? time,
        String? legId,
        String? source,
        String? pointId,
      })> points,
) {
  if (points.length < 2) return points;
  final sorted = List.of(points)
    ..sort((a, b) {
      if (a.time == null && b.time == null) return 0;
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return a.time!.compareTo(b.time!);
    });

  final out = <
      ({
        double lat,
        double lng,
        DateTime? time,
        String? legId,
        String? source,
        String? pointId,
      })>[sorted.first];

  for (var i = 1; i < sorted.length; i++) {
    final prev = out.last;
    final next = sorted[i];
    if (prev.pointId != null &&
        prev.pointId!.isNotEmpty &&
        prev.pointId == next.pointId) {
      continue;
    }
    final d = GeoUtils.distanceMeters(prev.lat, prev.lng, next.lat, next.lng);
    if (d < 8) {
      // Same spot — keep newer / better timestamped sample.
      if (next.time != null &&
          (prev.time == null || next.time!.isAfter(prev.time!))) {
        out[out.length - 1] = next;
      }
      continue;
    }
    if (prev.time != null &&
        next.time != null &&
        d < 30 &&
        next.time!.difference(prev.time!).abs() <= const Duration(seconds: 8)) {
      // Local + server echo of the same fix.
      continue;
    }
    out.add(next);
  }
  return out;
}

/// Per-leg traveled paths as contiguous segments.
///
/// Outer list = legs; inner list = polyline segments for that leg. A failed
/// GPS-gap fill starts a new segment so the map does not paint a false chord.
Future<List<List<List<LatLng>>>> loadTraveledLegPoints(
  TravelRequestModel request,
) async {
  final List<List<List<LatLng>>> legPaths = [];

  // Instant reopen: paint from local aligned cache (no Snap/Directions).
  if (!_isLiveTrackingStatus(request.status)) {
    final cached = await _loadAlignedPaintCache(request);
    if (cached != null) {
      // ignore: avoid_print
      print(
        '[ROAD_ALIGN] paint CACHE HIT legs=${cached.length} '
        'id=${request.requestId}',
      );
      return cached;
    }
  }

  if (request.tripLegs.isEmpty) {
    final whole = await loadWholeTripPathFilled(request);
    if (whole.isNotEmpty) {
      final wrapped = [whole];
      await _saveAlignedPaintCache(request, wrapped);
      return wrapped;
    }
    return [];
  }

  final pointsWithTime = await _loadRoutePointsWithTime(request);
  final isLive = _isLiveTrackingStatus(request.status);

  for (final leg in request.tripLegs) {
    List<List<LatLng>> segments = const [];

    // Completed legs: use stored polyline first (no network Snap).
    if (!isLive && leg.arrivalPunch != null) {
      if (leg.routePolylineEncoded != null &&
          leg.routePolylineEncoded!.isNotEmpty) {
        final decoded = decodePipePolyline(leg.routePolylineEncoded);
        if (decoded.length >= 2) {
          legPaths.add([decoded]);
          continue;
        }
      }
      if (leg.matchedRoutePolylineEncoded != null &&
          leg.matchedRoutePolylineEncoded!.isNotEmpty) {
        final decoded = decodePipePolyline(leg.matchedRoutePolylineEncoded);
        if (decoded.length >= 2) {
          legPaths.add([decoded]);
          continue;
        }
      }
    }

    if (leg.departurePunch != null) {
      final start = leg.departurePunch!.time.toUtc();
      final end = leg.arrivalPunch?.time.toUtc() ?? DateTime.now().toUtc();

      final legPointsWithTime = <
          ({
            double lat,
            double lng,
            DateTime? time,
            String? legId,
            String? source,
            String? pointId,
          })>[];
      for (final p in pointsWithTime) {
        if (p.legId != null && p.legId!.isNotEmpty) {
          if (p.legId == leg.legId) legPointsWithTime.add(p);
          continue;
        }
        if (p.time != null) {
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

      if (legPointsWithTime.isNotEmpty) {
        final input = legPointsWithTime
            .map(
              (p) => GpsGapInputPoint(
                lat: p.lat,
                lng: p.lng,
                time: p.time,
                source: p.source,
                pointId: p.pointId,
              ),
            )
            .toList(growable: false);
        final aligned = await RoadAlignedRouteService().align(
          gpsPoints: input,
          anchorStart: LatLng(
            leg.departurePunch!.latitude,
            leg.departurePunch!.longitude,
          ),
          anchorEnd: leg.arrivalPunch != null
              ? LatLng(
                  leg.arrivalPunch!.latitude,
                  leg.arrivalPunch!.longitude,
                )
              : null,
        );
        if (!aligned.isEmpty) {
          segments = RoadAlignedRouteService().toMapPieces(aligned);
        }
      }
    }

    if (segments.any((s) => s.length >= 2)) {
      legPaths.add(segments);
    } else if (leg.matchedRoutePolylineEncoded != null &&
        leg.matchedRoutePolylineEncoded!.isNotEmpty) {
      legPaths.add([decodePipePolyline(leg.matchedRoutePolylineEncoded)]);
    } else if (leg.routePolylineEncoded != null &&
        leg.routePolylineEncoded!.isNotEmpty) {
      legPaths.add([decodePipePolyline(leg.routePolylineEncoded)]);
    } else {
      legPaths.add(segments);
    }
  }

  if (request.tripLegs.length == 1 &&
      legPaths.isNotEmpty &&
      legPaths.first.every((s) => s.isEmpty) &&
      pointsWithTime.isNotEmpty) {
    final whole = await loadWholeTripPathFilled(request);
    if (whole.isNotEmpty) legPaths[0] = whole;
  }

  if (legPaths.any((leg) => leg.any((s) => s.length >= 2))) {
    await _saveAlignedPaintCache(request, legPaths);
  }

  return legPaths;
}

/// Haversine length of painted path segments (km).
double pathSegmentsLengthKm(List<List<LatLng>> segments) {
  var meters = 0.0;
  for (final seg in segments) {
    for (var i = 1; i < seg.length; i++) {
      meters += GeoUtils.distanceMeters(
        seg[i - 1].latitude,
        seg[i - 1].longitude,
        seg[i].latitude,
        seg[i].longitude,
      );
    }
  }
  return meters / 1000.0;
}

/// Official Layer B segments from Nest match cache / API.
Future<List<RouteSegmentModel>> loadMatchedRouteSegments(
  TravelRequestModel request,
) async {
  final id = request.restResourceId.isNotEmpty
      ? request.restResourceId
      : request.requestId;
  if (id.isEmpty) return const [];

  if (ServiceLocator.I.has<MapMatchingService>()) {
    final fromService = await ServiceLocator.I
        .get<MapMatchingService>()
        .loadSegmentsForRequest(id);
    if (fromService.isNotEmpty) return fromService;
  }

  // Fallback: synthesize segments from per-leg matched polylines.
  final synthesized = <RouteSegmentModel>[];
  for (final leg in request.tripLegs) {
    final poly = leg.matchedRoutePolylineEncoded;
    if (poly == null || poly.isEmpty) continue;
    synthesized.add(
      RouteSegmentModel(
        segId: '${leg.legId}_matched',
        legId: leg.legId,
        kind: RouteSegmentKind.mapMatched,
        confidence: leg.matchConfidence ?? 0.7,
        lengthM: ((leg.officialDistanceKm ?? 0) * 1000),
        polylineEncoded: poly,
        matchMethod: 'leg_polyline',
      ),
    );
  }
  return synthesized;
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
  _alignedPaintMemCache.remove(id);
  unawaited(HiveDatabase.instance.clearAlignedRouteCache(id));
}

/// Display-ready path segments (spike-stripped, no absurd chords).
List<List<LatLng>> mapDisplayRouteSegments(
  List<LatLng> points, {
  double maxEdgeMeters = kMapMaxEdgeMeters,
}) {
  final simplified = simplifyRoutePointsForMap(stripTeleportSpikesForMap(points));
  return breakLongMapEdges(simplified, maxEdgeMeters: maxEdgeMeters);
}

/// Flattened display points for camera / markers (chords already removed).
List<LatLng> mapDisplayRoutePoints(
  List<LatLng> points, {
  double maxEdgeMeters = kMapMaxEdgeMeters,
}) {
  return [
    for (final seg in mapDisplayRouteSegments(
      points,
      maxEdgeMeters: maxEdgeMeters,
    ))
      ...seg,
  ];
}
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

LatLng? _tripPunchStart(TravelRequestModel r) {
  for (final leg in r.tripLegs) {
    final p = leg.departurePunch;
    if (p == null) continue;
    if (p.latitude.abs() < 1e-6 && p.longitude.abs() < 1e-6) continue;
    return LatLng(p.latitude, p.longitude);
  }
  return tripDrivingEndpoints(r).origin;
}

LatLng? _tripPunchEnd(TravelRequestModel r) {
  // Live trips: don't force the trail tip onto a future destination.
  final s = r.status.trim();
  final live = s == 'Travelling' ||
      s == 'Returning' ||
      s == 'At Client' ||
      s == 'In Meeting';
  if (live) return null;

  for (final leg in r.tripLegs.reversed) {
    final p = leg.arrivalPunch;
    if (p == null) continue;
    if (p.latitude.abs() < 1e-6 && p.longitude.abs() < 1e-6) continue;
    return LatLng(p.latitude, p.longitude);
  }
  return tripDrivingEndpoints(r).dest;
}

/// Map pin for trip start — prefers departure punch over painted path tip.
LatLng? tripMapStartMarkerTarget(
  TravelRequestModel r, {
  LatLng? pathFirst,
}) {
  return _tripPunchStart(r) ?? pathFirst ?? tripMapStartTarget(r);
}

/// Map pin for trip end / live tip.
LatLng? tripMapEndMarkerTarget(
  TravelRequestModel r, {
  LatLng? pathLast,
  bool isLive = false,
}) {
  if (isLive) return pathLast;
  return _tripPunchEnd(r) ?? pathLast ?? tripMapDestinationTarget(r);
}

/// A client / meeting stop along a multi-leg trip.
class TripMapStop {
  const TripMapStop({
    required this.position,
    required this.index,
    required this.title,
    this.snippet,
  });

  final LatLng position;
  final int index;
  final String title;
  final String? snippet;
}

bool _punchUsable(TripPunchModel? p) {
  if (p == null) return false;
  return p.latitude.abs() >= 1e-6 || p.longitude.abs() >= 1e-6;
}

/// Client stops (arrival / meeting) — excludes return-home and the final
/// destination when there is no return leg (that point is the End marker).
List<TripMapStop> tripMapStops(TravelRequestModel r) {
  final legs = r.tripLegs;
  if (legs.isEmpty) return const [];

  final clientLegs = legs.where((l) => !l.isReturnLeg).toList();
  final hasReturn = legs.any((l) => l.isReturnLeg);
  final out = <TripMapStop>[];
  var n = 0;

  for (var i = 0; i < clientLegs.length; i++) {
    final leg = clientLegs[i];
    final isLastClient = i == clientLegs.length - 1;
    // Single final destination with no return = End marker, not Stop.
    if (isLastClient && !hasReturn && clientLegs.length == 1) continue;

    final punch = _punchUsable(leg.arrivalPunch)
        ? leg.arrivalPunch
        : (_punchUsable(leg.meetingStartPunch) ? leg.meetingStartPunch : null);
    if (punch == null) continue;

    // Last client before return home is still a stop (office end is separate).
    // Last client with no return is also a stop when there are multiple clients.
    n++;
    final name = leg.clientName.trim().isNotEmpty
        ? leg.clientName.trim()
        : (leg.toLocation.trim().isNotEmpty
            ? leg.toLocation.trim()
            : 'Client');
    out.add(
      TripMapStop(
        position: LatLng(punch.latitude, punch.longitude),
        index: n,
        title: 'Stop $n',
        snippet: name,
      ),
    );
  }

  return out;
}

/// Orange stop pins; skips positions that sit on [exclude] (start/end).
Set<Marker> tripStopMarkers(
  TravelRequestModel r, {
  List<LatLng> exclude = const [],
  double minSeparationMeters = 35,
}) {
  final stops = tripMapStops(r);
  if (stops.isEmpty) return {};

  bool tooClose(LatLng a) {
    for (final e in exclude) {
      final d = GeoUtils.distanceMeters(
        a.latitude,
        a.longitude,
        e.latitude,
        e.longitude,
      );
      if (d < minSeparationMeters) return true;
    }
    return false;
  }

  final markers = <Marker>{};
  for (final s in stops) {
    if (tooClose(s.position)) continue;
    markers.add(
      Marker(
        markerId: MarkerId('stop_${s.index}'),
        position: s.position,
        icon: mapStopMarkerIcon,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(title: s.title, snippet: s.snippet),
        zIndexInt: 2,
      ),
    );
  }
  return markers;
}

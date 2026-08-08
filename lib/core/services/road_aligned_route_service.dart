import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geo_utils.dart';
import '../utils/route_point_simplify.dart';
import 'distance_service.dart';
import 'gps_gap_road_fill.dart';

void _roadAlignLog(String message) {
  // Use print so logs show in --release (debugPrint is often silenced).
  // ignore: avoid_print
  print('[ROAD_ALIGN] $message');
}

/// Result of merging GPS samples with Google road geometry.
class RoadAlignedRoute {
  final List<LatLng> points;
  final double distanceKm;
  final String engine;
  final int gapsFilled;

  const RoadAlignedRoute({
    required this.points,
    required this.distanceKm,
    required this.engine,
    this.gapsFilled = 0,
  });

  bool get isEmpty => points.length < 2;
  bool get isAligned =>
      engine.contains('google_roads') ||
      engine.contains('directions_corridor') ||
      engine == 'directions_gaps';
}

/// Merges live GPS with Google navigation geometry for accurate map paint.
///
/// Frontend-only pipeline (no Nest):
/// 1. Clean spikes / jitter
/// 2. Directions fill for kill / long GPS gaps (incl. missing timestamps)
/// 3. Snap-to-Roads (interpolate)
/// 4. Directions corridor fallback if Snap fails
/// 5. Stitch any remaining long edges (app-kill blank gaps)
class RoadAlignedRouteService {
  RoadAlignedRouteService({
    DistanceService? distanceService,
  }) : _distance = distanceService ?? DistanceService();

  final DistanceService _distance;

  /// Align chronological GPS samples onto the road network.
  Future<RoadAlignedRoute> align({
    required List<GpsGapInputPoint> gpsPoints,
  }) async {
    _roadAlignLog(
      'align() START build=v7-kill-gap-roads gps=${gpsPoints.length}',
    );

    if (gpsPoints.length < 2) {
      _roadAlignLog('align() ABORT: need ≥2 GPS points');
      return RoadAlignedRoute(
        points: gpsPoints.map((p) => LatLng(p.lat, p.lng)).toList(),
        distanceKm: 0,
        engine: 'empty',
      );
    }

    final cleaned = GpsGapRoadFill.stripSpikePoints(
      GpsGapRoadFill.collapseDuplicateFillerRuns(gpsPoints),
    );
    final spaced = <GpsGapInputPoint>[];
    for (final p in cleaned) {
      if (spaced.isEmpty) {
        spaced.add(p);
        continue;
      }
      final prev = spaced.last;
      final d = GeoUtils.distanceMeters(prev.lat, prev.lng, p.lat, p.lng);
      // Wider spacing cuts urban GPS scribble before Snap/Directions.
      if (d < 22) continue;
      spaced.add(p);
    }
    _roadAlignLog(
      'align() cleaned ${gpsPoints.length} → ${cleaned.length} → '
      'spaced ${spaced.length}',
    );

    if (spaced.length < 2) {
      _roadAlignLog('align() FALLBACK gps_only (too few after clean)');
      return RoadAlignedRoute(
        points: cleaned.map((p) => LatLng(p.lat, p.lng)).toList(),
        distanceKm: _pathKm(cleaned.map((p) => LatLng(p.lat, p.lng)).toList()),
        engine: 'gps_only',
      );
    }

    final local = await _alignLocally(spaced);
    final cleanedPts = _stripLatLngBacktracks(local.points);
    final result = cleanedPts.length >= 2
        ? RoadAlignedRoute(
            points: cleanedPts,
            distanceKm: _pathKm(cleanedPts),
            engine: local.engine,
            gapsFilled: local.gapsFilled,
          )
        : local;
    _roadAlignLog(
      'align() DONE engine=${result.engine} '
      'pts=${result.points.length} km=${result.distanceKm.toStringAsFixed(2)} '
      'gaps=${result.gapsFilled}',
    );
    return result;
  }

  /// Remove A→B→back-toward-A scribble from the painted polyline.
  List<LatLng> _stripLatLngBacktracks(List<LatLng> points) {
    if (points.length < 3) return points;
    final out = <LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      final next = points[i];
      while (out.length >= 2) {
        final a = out[out.length - 2];
        final b = out.last;
        final dAB = GeoUtils.distanceMeters(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        );
        final dAN = GeoUtils.distanceMeters(
          a.latitude,
          a.longitude,
          next.latitude,
          next.longitude,
        );
        final dBN = GeoUtils.distanceMeters(
          b.latitude,
          b.longitude,
          next.latitude,
          next.longitude,
        );
        if (dAB >= 30 && dBN >= 20 && dAN < dAB * 0.55 && dAN < dBN) {
          out.removeLast();
          continue;
        }
        break;
      }
      if (out.isNotEmpty) {
        final prev = out.last;
        final d = GeoUtils.distanceMeters(
          prev.latitude,
          prev.longitude,
          next.latitude,
          next.longitude,
        );
        if (d < 10) continue;
      }
      out.add(next);
    }
    return out;
  }

  Future<RoadAlignedRoute> _alignLocally(List<GpsGapInputPoint> points) async {
    _roadAlignLog('local: kill-gap Directions…');
    // forDisplay: fill large hops even when timestamps were lost after sync.
    final filled = await GpsGapRoadFill.fillPoints(
      points: points,
      distanceService: _distance,
      forDisplay: true,
    );
    var joined = <LatLng>[
      for (final seg in filled.segments)
        for (final p in seg) LatLng(p.lat, p.lng),
    ];
    // fillPoints may break failed gaps into separate segments — still stitch
    // those B→C hops so kill/reopen never leaves a blank map hole.
    joined = await _stitchLongEdges(joined);
    var gapsFilled = filled.gapsFilled;
    _roadAlignLog(
      'local: after kill-gap+stitch pts=${joined.length} '
      'gapsFilled=$gapsFilled',
    );
    if (joined.length < 2) {
      return RoadAlignedRoute(
        points: points.map((p) => LatLng(p.lat, p.lng)).toList(),
        distanceKm: 0,
        engine: 'gps_only',
      );
    }

    _roadAlignLog('local: Snap-to-Roads…');
    final snapped = await _distance.snapPathToRoads(joined);
    if (snapped.length >= 2 && _isSane(joined, snapped)) {
      final stitched = await _stitchLongEdges(snapped);
      _roadAlignLog('local Snap OK ${joined.length} → ${stitched.length}');
      return RoadAlignedRoute(
        points: stitched,
        distanceKm: _pathKm(stitched),
        engine: gapsFilled > 0
            ? 'google_roads+directions_gaps'
            : 'google_roads_snap',
        gapsFilled: gapsFilled,
      );
    }
    _roadAlignLog(
      'local Snap FAIL/unsane snapped=${snapped.length} '
      '→ Directions corridor…',
    );

    final corridor = await _directionsCorridorAlongGps(joined);
    if (corridor.points.length >= 2 && _isSane(joined, corridor.points)) {
      final stitched = await _stitchLongEdges(corridor.points);
      _roadAlignLog(
        'local corridor OK segs=${corridor.segments} '
        'pts=${stitched.length}',
      );
      return RoadAlignedRoute(
        points: stitched,
        distanceKm: _pathKm(stitched),
        engine: gapsFilled > 0
            ? 'directions_corridor+gaps'
            : 'directions_corridor',
        gapsFilled: gapsFilled,
      );
    }
    _roadAlignLog('local corridor FAIL → stitch remaining long edges');

    final fallback = await _stitchLongEdges(joined);
    final stitchedExtra = _countLongEdges(joined) - _countLongEdges(fallback);
    if (stitchedExtra > 0) gapsFilled += stitchedExtra;

    return RoadAlignedRoute(
      points: fallback,
      distanceKm: filled.roadFillMeters > 0
          ? (filled.roadFillMeters / 1000.0) +
              _estimateNonFillerKm(filled.segments)
          : _pathKm(fallback),
      engine: gapsFilled > 0 ? 'directions_gaps' : 'gps_cleaned',
      gapsFilled: gapsFilled,
    );
  }

  /// Fill any remaining hop > [minMeters] with Directions (app-kill blank gaps).
  Future<List<LatLng>> _stitchLongEdges(
    List<LatLng> path, {
    double minMeters = 250,
    int maxStitches = 40,
  }) async {
    if (path.length < 2) return path;

    final out = <LatLng>[path.first];
    var stitches = 0;

    for (var i = 1; i < path.length; i++) {
      final a = out.last;
      final b = path[i];
      final straight = GeoUtils.distanceMeters(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );

      if (straight <= minMeters ||
          straight > GpsGapRoadFill.maxStraightLineMeters ||
          stitches >= maxStitches) {
        out.add(b);
        continue;
      }

      final routes = await _distance.fetchDrivingRoutesWithAlternatives(
        originLatitude: a.latitude,
        originLongitude: a.longitude,
        destinationLatitude: b.latitude,
        destinationLongitude: b.longitude,
      );
      // Kill gaps: accept long road detours (river U-turns) over straight chords.
      final route = GpsGapRoadFill.pickSaneRoute(
        routes,
        straight,
        forKillGap: true,
      );
      if (route != null && route.polylinePoints.length >= 2) {
        out.addAll(route.polylinePoints.skip(1));
        stitches++;
        _roadAlignLog(
          'stitch OK ${straight.toStringAsFixed(0)}m → '
          '${(route.distanceKm * 1000).toStringAsFixed(0)}m road',
        );
      } else {
        // Never paint a false river/building chord — leave hop for edge break.
        out.add(b);
        _roadAlignLog(
          'stitch FAIL ${straight.toStringAsFixed(0)}m '
          '(routes=${routes.length}) — chord will be broken on paint',
        );
      }
    }

    if (stitches > 0) {
      _roadAlignLog('stitch done: $stitches long edge(s) filled');
    }
    return out;
  }

  int _countLongEdges(List<LatLng> path, {double minMeters = 250}) {
    var n = 0;
    for (var i = 1; i < path.length; i++) {
      final d = GeoUtils.distanceMeters(
        path[i - 1].latitude,
        path[i - 1].longitude,
        path[i].latitude,
        path[i].longitude,
      );
      if (d > minMeters) n++;
    }
    return n;
  }

  /// Sample GPS every ~[spacingM] and stitch Directions driving legs.
  Future<({List<LatLng> points, int segments})> _directionsCorridorAlongGps(
    List<LatLng> path, {
    double spacingM = 350,
    int maxLegs = 35,
  }) async {
    if (path.length < 2) return (points: path, segments: 0);

    final waypoints = <LatLng>[path.first];
    var last = path.first;
    for (var i = 1; i < path.length - 1; i++) {
      final p = path[i];
      if (GeoUtils.distanceMeters(
            last.latitude,
            last.longitude,
            p.latitude,
            p.longitude,
          ) >=
          spacingM) {
        waypoints.add(p);
        last = p;
        if (waypoints.length >= maxLegs) break;
      }
    }
    final end = path.last;
    final lastWp = waypoints.last;
    if (GeoUtils.distanceMeters(
              lastWp.latitude,
              lastWp.longitude,
              end.latitude,
              end.longitude,
            ) >
            40 ||
        waypoints.length == 1) {
      waypoints.add(end);
    }

    if (waypoints.length < 2) return (points: path, segments: 0);

    final out = <LatLng>[waypoints.first];
    var segments = 0;

    for (var i = 1; i < waypoints.length; i++) {
      final a = waypoints[i - 1];
      final b = waypoints[i];
      final straight = GeoUtils.distanceMeters(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      if (straight < 60) {
        out.add(b);
        continue;
      }

      final routes = await _distance.fetchDrivingRoutesWithAlternatives(
        originLatitude: a.latitude,
        originLongitude: a.longitude,
        destinationLatitude: b.latitude,
        destinationLongitude: b.longitude,
      );
      final route = GpsGapRoadFill.pickSaneRoute(
        routes,
        straight,
        forKillGap: straight >= GpsGapRoadFill.breakChordMeters,
      );
      if (route != null && route.polylinePoints.length >= 2) {
        out.addAll(route.polylinePoints.skip(1));
        segments++;
      } else {
        out.add(b);
      }
    }

    return (points: out, segments: segments);
  }

  double _estimateNonFillerKm(List<List<GpsGapOutputPoint>> segments) {
    var m = 0.0;
    for (final seg in segments) {
      for (var i = 1; i < seg.length; i++) {
        final a = seg[i - 1];
        final b = seg[i];
        if (a.source == GpsGapRoadFill.fillerSource ||
            b.source == GpsGapRoadFill.fillerSource) {
          continue;
        }
        m += GeoUtils.distanceMeters(a.lat, a.lng, b.lat, b.lng);
      }
    }
    return m / 1000.0;
  }

  bool _isSane(List<LatLng> raw, List<LatLng> snapped) {
    final rawM = _pathKm(raw) * 1000;
    final snapM = _pathKm(snapped) * 1000;
    if (rawM < 50) return true;
    return snapM <= rawM * 2.8 && snapM >= rawM * 0.35;
  }

  double _pathKm(List<LatLng> pts) {
    var m = 0.0;
    for (var i = 1; i < pts.length; i++) {
      m += GeoUtils.distanceMeters(
        pts[i - 1].latitude,
        pts[i - 1].longitude,
        pts[i].latitude,
        pts[i].longitude,
      );
    }
    return m / 1000.0;
  }

  /// Split aligned path for map polylines (break only true teleports).
  List<List<LatLng>> toMapPieces(RoadAlignedRoute route) {
    if (route.points.length < 2) return const [];
    final maxEdge =
        route.isAligned ? kAlignedMapMaxEdgeMeters : kMapMaxEdgeMeters;
    return [
      for (final piece in breakLongMapEdges(
        simplifyRoutePointsForMap(route.points),
        maxEdgeMeters: maxEdge,
      ))
        if (piece.length >= 2) piece,
    ];
  }
}

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geo_utils.dart';
import '../utils/route_point_simplify.dart';
import 'distance_service.dart';
import 'gps_gap_road_fill.dart';



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
  ///
  /// [anchorStart] / [anchorEnd] — departure / arrival punches. Leading Snap
  /// spurs before the real punch are trimmed so the trail starts where the
  /// user actually started.
  Future<RoadAlignedRoute> align({
    required List<GpsGapInputPoint> gpsPoints,
    LatLng? anchorStart,
    LatLng? anchorEnd,
  }) async {

    if (gpsPoints.length < 2) {
      return RoadAlignedRoute(
        points: gpsPoints.map((p) => LatLng(p.lat, p.lng)).toList(),
        distanceKm: 0,
        engine: 'empty',
      );
    }

    var working = gpsPoints;
    if (anchorStart != null) {
      working = trimGpsLeadingAwayFromAnchor(working, anchorStart);
    }

    final cleaned = GpsGapRoadFill.stripDetourLoops(
      GpsGapRoadFill.stripSpikePoints(
        GpsGapRoadFill.collapseDuplicateFillerRuns(working),
      ),
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

    if (spaced.length < 2) {
      return RoadAlignedRoute(
        points: cleaned.map((p) => LatLng(p.lat, p.lng)).toList(),
        distanceKm: _pathKm(cleaned.map((p) => LatLng(p.lat, p.lng)).toList()),
        engine: 'gps_only',
      );
    }

    final local = await _alignLocally(spaced);
    var cleanedPts = _stripLatLngSpikesAndBacktracks(local.points);
    cleanedPts = stripDetourLoops(cleanedPts);
    cleanedPts = anchorPathToPunches(
      cleanedPts,
      start: anchorStart,
      end: anchorEnd,
    );
    final result = cleanedPts.length >= 2
        ? RoadAlignedRoute(
            points: cleanedPts,
            distanceKm: _pathKm(cleanedPts),
            engine: local.engine,
            gapsFilled: local.gapsFilled,
          )
        : local;
    return result;
  }

  /// Drop GPS samples that wander far from [anchor] before the trail first
  /// approaches it (false "start west of office" spurs).
  static List<GpsGapInputPoint> trimGpsLeadingAwayFromAnchor(
    List<GpsGapInputPoint> points,
    LatLng anchor, {
    double nearMeters = 100,
  }) {
    if (points.length < 3) return points;

    var firstNear = -1;
    for (var i = 0; i < points.length; i++) {
      final d = GeoUtils.distanceMeters(
        points[i].lat,
        points[i].lng,
        anchor.latitude,
        anchor.longitude,
      );
      if (d <= nearMeters) {
        firstNear = i;
        break;
      }
    }

    if (firstNear < 0) {
      // No sample near punch — use closest in the first 40% of the trail.
      var bestI = 0;
      var bestD = double.infinity;
      final limit = (points.length * 0.4).ceil().clamp(3, points.length);
      for (var i = 0; i < limit; i++) {
        final d = GeoUtils.distanceMeters(
          points[i].lat,
          points[i].lng,
          anchor.latitude,
          anchor.longitude,
        );
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
      if (bestD > 450) return points;
      firstNear = bestI;
    }

    if (firstNear <= 0) {
      return points;
    }

    final d0 = GeoUtils.distanceMeters(
      points.first.lat,
      points.first.lng,
      anchor.latitude,
      anchor.longitude,
    );
    if (d0 <= nearMeters) return points;

    final anchorPt = GpsGapInputPoint(
      lat: anchor.latitude,
      lng: anchor.longitude,
      time: points[firstNear].time,
      source: 'punch_start',
    );
    return [anchorPt, ...points.sublist(firstNear)];
  }

  /// Force painted path to begin/end on punch pins; drop leading Snap spurs.
  static List<LatLng> anchorPathToPunches(
    List<LatLng> path, {
    LatLng? start,
    LatLng? end,
    double nearMeters = 100,
  }) {
    if (path.length < 2) return path;
    var out = List<LatLng>.from(path);

    if (start != null) {
      var firstNear = -1;
      for (var i = 0; i < out.length; i++) {
        final d = GeoUtils.distanceMeters(
          out[i].latitude,
          out[i].longitude,
          start.latitude,
          start.longitude,
        );
        if (d <= nearMeters) {
          firstNear = i;
          break;
        }
      }
      if (firstNear < 0) {
        var bestI = 0;
        var bestD = double.infinity;
        final limit = (out.length * 0.4).ceil().clamp(3, out.length);
        for (var i = 0; i < limit; i++) {
          final d = GeoUtils.distanceMeters(
            out[i].latitude,
            out[i].longitude,
            start.latitude,
            start.longitude,
          );
          if (d < bestD) {
            bestD = d;
            bestI = i;
          }
        }
        if (bestD <= 450) firstNear = bestI;
      }

      if (firstNear > 0) {
        final d0 = GeoUtils.distanceMeters(
          out.first.latitude,
          out.first.longitude,
          start.latitude,
          start.longitude,
        );
        if (d0 > nearMeters) {
          out = out.sublist(firstNear);
        }
      }

      if (out.isEmpty ||
          GeoUtils.distanceMeters(
                out.first.latitude,
                out.first.longitude,
                start.latitude,
                start.longitude,
              ) >
              25) {
        out = [start, ...out];
      } else {
        out[0] = start;
      }
    }

    if (end != null && out.length >= 2) {
      var lastNear = -1;
      for (var i = out.length - 1; i >= 0; i--) {
        final d = GeoUtils.distanceMeters(
          out[i].latitude,
          out[i].longitude,
          end.latitude,
          end.longitude,
        );
        if (d <= nearMeters) {
          lastNear = i;
          break;
        }
      }
      if (lastNear >= 0 && lastNear < out.length - 1) {
        final dLast = GeoUtils.distanceMeters(
          out.last.latitude,
          out.last.longitude,
          end.latitude,
          end.longitude,
        );
        if (dLast > nearMeters) {
          out = out.sublist(0, lastNear + 1);
        }
      }
      if (GeoUtils.distanceMeters(
            out.last.latitude,
            out.last.longitude,
            end.latitude,
            end.longitude,
          ) >
          25) {
        out = [...out, end];
      } else {
        out[out.length - 1] = end;
      }
    }

    return out;
  }

  /// Remove side-street rectangular loops that leave the corridor and return
  /// near the same junction (Snap noise / GPS scribble into bungalows).
  ///
  /// If path length i→j is long but chord i→j is short, drop i+1…j−1 so the
  /// trail stays on the main road (the "black" route, not the yellow detour).
  static List<LatLng> stripDetourLoops(
    List<LatLng> points, {
    double maxReturnChordMeters = 75,
    double minLoopPathMeters = 100,
    double minPathVsChordRatio = 2.6,
    double maxLoopPathMeters = 2200,
  }) {
    if (points.length < 5) return points;
    var work = List<LatLng>.from(points);

    for (var pass = 0; pass < 5; pass++) {
      int? bestI;
      int? bestJ;
      var bestPath = 0.0;

      for (var i = 0; i < work.length - 4; i++) {
        var pathFromI = 0.0;
        for (var j = i + 1; j < work.length; j++) {
          pathFromI += GeoUtils.distanceMeters(
            work[j - 1].latitude,
            work[j - 1].longitude,
            work[j].latitude,
            work[j].longitude,
          );
          if (pathFromI > maxLoopPathMeters) break;
          if (j < i + 3) continue;
          if (pathFromI < minLoopPathMeters) continue;

          final chord = GeoUtils.distanceMeters(
            work[i].latitude,
            work[i].longitude,
            work[j].latitude,
            work[j].longitude,
          );
          if (chord > maxReturnChordMeters) continue;

          final isLoop = chord <= 30
              ? pathFromI >= minLoopPathMeters
              : pathFromI >= chord * minPathVsChordRatio;
          if (!isLoop) continue;

          if (pathFromI > bestPath) {
            bestPath = pathFromI;
            bestI = i;
            bestJ = j;
          }
        }
      }

      if (bestI == null || bestJ == null || bestJ <= bestI + 1) break;


      final next = <LatLng>[
        ...work.sublist(0, bestI + 1),
        ...work.sublist(bestJ),
      ];
      // Collapse near-duplicate junction after cut.
      if (next.length > bestI + 1) {
        final d = GeoUtils.distanceMeters(
          next[bestI].latitude,
          next[bestI].longitude,
          next[bestI + 1].latitude,
          next[bestI + 1].longitude,
        );
        if (d < 18) next.removeAt(bestI + 1);
      }
      if (next.length >= work.length) break;
      work = next;
    }

    return work;
  }

  /// Drop V-spikes and A→B→back-toward-A scribble from the painted polyline.
  List<LatLng> _stripLatLngSpikesAndBacktracks(List<LatLng> points) {
    if (points.length < 3) return points;
    var work = List<LatLng>.from(points);
    for (var pass = 0; pass < 3; pass++) {
      final spiked = <LatLng>[work.first];
      for (var i = 1; i < work.length - 1; i++) {
        final prev = spiked.last;
        final mid = work[i];
        final next = work[i + 1];
        final dPrev = GeoUtils.distanceMeters(
          prev.latitude,
          prev.longitude,
          mid.latitude,
          mid.longitude,
        );
        final dNext = GeoUtils.distanceMeters(
          mid.latitude,
          mid.longitude,
          next.latitude,
          next.longitude,
        );
        final dSkip = GeoUtils.distanceMeters(
          prev.latitude,
          prev.longitude,
          next.latitude,
          next.longitude,
        );
        if (dPrev > 40 &&
            dNext > 40 &&
            dSkip < 120 &&
            dSkip < dPrev * 0.55 &&
            dSkip < dNext * 0.55) {
          continue;
        }
        // Long thin V (map end-spike / wrong-way spur).
        if (dPrev > 80 &&
            dNext > 80 &&
            dSkip < dPrev * 0.35 &&
            dSkip < dNext * 0.35) {
          continue;
        }
        spiked.add(mid);
      }
      spiked.add(work.last);

      final out = <LatLng>[spiked.first];
      for (var i = 1; i < spiked.length; i++) {
        final next = spiked[i];
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
          if (dAB >= 20 && dBN >= 12 && dAN < dAB * 0.6 && dAN < dBN) {
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
      if (out.length >= work.length) {
        work = out;
        break;
      }
      work = out;
    }
    return work;
  }

  Future<RoadAlignedRoute> _alignLocally(List<GpsGapInputPoint> points) async {
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
    if (joined.length < 2) {
      return RoadAlignedRoute(
        points: points.map((p) => LatLng(p.lat, p.lng)).toList(),
        distanceKm: 0,
        engine: 'gps_only',
      );
    }

    final snapped = await _distance.snapPathToRoads(joined);
    if (snapped.length >= 2 && _isSane(joined, snapped)) {
      final stitched = await _stitchLongEdges(snapped);
      return RoadAlignedRoute(
        points: stitched,
        distanceKm: _pathKm(stitched),
        engine: gapsFilled > 0
            ? 'google_roads+directions_gaps'
            : 'google_roads_snap',
        gapsFilled: gapsFilled,
      );
    }

    final corridor = await _directionsCorridorAlongGps(joined);
    if (corridor.points.length >= 2 && _isSane(joined, corridor.points)) {
      final stitched = await _stitchLongEdges(corridor.points);
      return RoadAlignedRoute(
        points: stitched,
        distanceKm: _pathKm(stitched),
        engine: gapsFilled > 0
            ? 'directions_corridor+gaps'
            : 'directions_corridor',
        gapsFilled: gapsFilled,
      );
    }

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
      } else {
        // Never paint a false river/building chord — leave hop for edge break.
        out.add(b);
      }
    }

    if (stitches > 0) {
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
  ///
  /// By the time a route reaches here it has already been through the full
  /// gap-fill → snap-to-roads → directions-corridor → stitch pipeline in
  /// [align] — every real GPS-silence gap it was possible to bridge already
  /// has road geometry painted into it. A long edge that *still* survives all
  /// of that is either (a) a hop where Directions genuinely had no route
  /// (offline / API miss) and we fell back to a straight connector, which
  /// should still be drawn so the trip looks continuous like Google Maps, or
  /// (b) a true teleport / wrong-country GPS error, which must never be
  /// drawn. [GpsGapRoadFill.maxStraightLineMeters] is the line between those
  /// two — anything shorter is a real (if imperfect) connection.
  List<List<LatLng>> toMapPieces(RoadAlignedRoute route) {
    if (route.points.length < 2) return const [];
    // Every engine that reaches here (snap, corridor, or the gps_cleaned
    // fallback) already ran the same gap-fill + stitch pass in `align`, so
    // they all get the same lenient teleport-only break threshold.
    return [
      for (final piece in breakLongMapEdges(
        simplifyRoutePointsForMap(route.points),
        maxEdgeMeters: GpsGapRoadFill.maxStraightLineMeters,
      ))
        if (piece.length >= 2) piece,
    ];
  }
}

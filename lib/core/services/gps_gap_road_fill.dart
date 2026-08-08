import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/app_constants.dart';
import '../utils/geo_utils.dart';
import '../../modules/travel/data/models/route_point_model.dart';
import 'distance_service.dart';

/// Policy + runner for filling GPS kill / signal-loss gaps with Google Directions.
///
/// Real silence gaps become driving roads. True teleport spikes (return near
/// previous) are dropped. Short noise hops break — never paint river chords.
abstract final class GpsGapRoadFill {
  /// Keep tiny GPS jitter as raw samples.
  static const double minStraightLineMeters = 150;
  static const double maxStraightLineMeters = 15000;

  /// Never paint a straight chord longer than this when unfilled.
  static const double breakChordMeters = 250;

  /// Map paint: roadify chords at/above this (building corner cuts).
  /// Kept for tests; display roadify is DISABLED — use RoadAlignedRouteService.
  static const double displayRoadifyMinMeters = 60;

  static const String fillerSource = 'google_gap_filler';
  static const String policyVersion = 'v7-roadify';

  /// Classic kill / background silence (matches Nest catch-up).
  static const Duration minTimeGap = Duration(
    seconds: AppConstants.trackingGapThresholdSeconds,
  );

  /// Soft kill only — must stay well above normal GPS sample gaps
  /// (traveling ~5s, paused ~25s) or every hop triggers Directions and stalls tracking.
  static const Duration softFillMinTimeGap = Duration(seconds: 60);
  static const double softFillMinMeters = 400;

  /// Neighbors must be this close to treat mid point as a teleport spike.
  static const double spikeSkipMaxMeters = 120;

  /// Mid point must be at least this far off the skip chord to count as a spike.
  static const double spikeOutMinMeters = 40;

  /// Reject Directions detours that invent long loops.
  /// Short hops get a tight cap (stops 61m → 267m fake roads).
  static const double maxRoadVsStraightRatio = 2.0;
  static const double maxRoadVsStraightExtraMeters = 600;

  /// Kill / long-silence: real roads often bend far from the chord (river, one-way).
  static const double killGapMaxRoadVsStraightRatio = 8.0;
  static const double killGapMaxRoadExtraMeters = 12000;
  static const double killGapHardMaxRoadMeters = 50000;

  /// Whether a Directions result is a plausible road between the two GPS fixes.
  ///
  /// [forKillGap]: app was closed — accept longer driving detours instead of
  /// painting a straight chord through rivers/buildings.
  static bool isSaneRoadFill({
    required double straightLineMeters,
    required double roadMeters,
    bool forKillGap = false,
  }) {
    if (roadMeters < 1 || straightLineMeters < 1) return false;
    if (roadMeters < straightLineMeters * 0.5) return false;
    if (forKillGap) {
      if (roadMeters > killGapHardMaxRoadMeters) return false;
      if (roadMeters <= straightLineMeters * killGapMaxRoadVsStraightRatio) {
        return true;
      }
      return roadMeters <= straightLineMeters + killGapMaxRoadExtraMeters;
    }
    final maxExtra = straightLineMeters < 150
        ? 80.0
        : straightLineMeters < 400
            ? 250.0
            : maxRoadVsStraightExtraMeters;
    final maxRatio = straightLineMeters < 150 ? 1.6 : maxRoadVsStraightRatio;
    if (roadMeters <= straightLineMeters * maxRatio) return true;
    return roadMeters <= straightLineMeters + maxExtra;
  }

  /// Pick shortest sane alternative; null if all are absurd detours.
  ///
  /// [forKillGap]: if tight checks reject everything, still take the shortest
  /// driving route under [killGapHardMaxRoadMeters] — never a raw GPS chord.
  static DrivingRouteOption? pickSaneRoute(
    List<DrivingRouteOption> routes,
    double straightLineMeters, {
    bool forKillGap = false,
  }) {
    DrivingRouteOption? best;
    for (final r in routes) {
      final roadM = r.distanceKm * 1000.0;
      if (!isSaneRoadFill(
        straightLineMeters: straightLineMeters,
        roadMeters: roadM,
        forKillGap: forKillGap,
      )) {
        continue;
      }
      if (best == null || r.distanceKm < best.distanceKm) best = r;
    }
    if (best != null) return best;
    if (!forKillGap || routes.isEmpty) return null;
    DrivingRouteOption? shortest;
    for (final r in routes) {
      final roadM = r.distanceKm * 1000.0;
      if (roadM < 1 || roadM > killGapHardMaxRoadMeters) continue;
      if (shortest == null || r.distanceKm < shortest.distanceKm) {
        shortest = r;
      }
    }
    return shortest;
  }

  /// Whether the chord between two fixes should be replaced with a road route.
  ///
  /// [fillLargeHopsWithoutTime]: map paint / align — when timestamps were lost
  /// (common after kill → sync), a large spatial hop must still get Directions
  /// or the map shows a blank gap between trail pieces.
  static bool isFillableGap({
    required Duration timeGap,
    required double straightLineMeters,
    bool fillLargeHopsWithoutTime = false,
  }) {
    if (straightLineMeters <= breakChordMeters ||
        straightLineMeters > maxStraightLineMeters) {
      return false;
    }
    if (timeGap >= minTimeGap) return true;
    if (timeGap >= softFillMinTimeGap &&
        straightLineMeters >= softFillMinMeters) {
      return true;
    }
    // Unknown / zero dt + real displacement ≈ kill gap with missing clocks.
    if (fillLargeHopsWithoutTime &&
        timeGap <= Duration.zero &&
        straightLineMeters > breakChordMeters) {
      return true;
    }
    return false;
  }

  /// Map-only: roadify medium chords that cut corners/buildings (no long silence).
  static bool isDisplayRoadifyGap(double straightLineMeters) {
    return straightLineMeters >= displayRoadifyMinMeters &&
        straightLineMeters <= maxStraightLineMeters;
  }

  /// Parse API / Hive timestamps (ISO-8601, epoch ms, or epoch seconds).
  static DateTime? parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int || raw is double) {
      final n = (raw as num).toDouble();
      if (n <= 0) return null;
      // Heuristic: ms since epoch vs seconds.
      if (n > 1e12) {
        return DateTime.fromMillisecondsSinceEpoch(n.round(), isUtc: true);
      }
      if (n > 1e9) {
        return DateTime.fromMillisecondsSinceEpoch(
          (n * 1000).round(),
          isUtc: true,
        );
      }
      return null;
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final asNum = double.tryParse(s);
    if (asNum != null &&
        s.length >= 10 &&
        !s.contains('-') &&
        !s.contains('T')) {
      return parseTimestamp(asNum);
    }
    return DateTime.tryParse(s);
  }

  /// Whether an unfilled hop must break the polyline (no building-cutting chord).
  static bool shouldBreakUnfilledChord(double straightLineMeters) {
    return straightLineMeters > breakChordMeters;
  }

  /// Drop A→B→toward-A GPS loops that paint as "extra lines" / spaghetti.
  static List<GpsGapInputPoint> stripBacktrackLoops(
    List<GpsGapInputPoint> points, {
    double minLegMeters = 20,
  }) {
    if (points.length < 3) return points;
    final out = <GpsGapInputPoint>[points.first];
    for (var i = 1; i < points.length; i++) {
      final next = points[i];
      while (out.length >= 2) {
        final a = out[out.length - 2];
        final b = out.last;
        final dAB = GeoUtils.distanceMeters(a.lat, a.lng, b.lat, b.lng);
        final dAN = GeoUtils.distanceMeters(a.lat, a.lng, next.lat, next.lng);
        final dBN = GeoUtils.distanceMeters(b.lat, b.lng, next.lat, next.lng);
        // Went A→B then next is closer to A than B was → drop B (backtrack).
        if (dAB >= minLegMeters &&
            dBN >= 12 &&
            dAN < dAB * 0.6 &&
            dAN < dBN) {
          out.removeLast();
          continue;
        }
        break;
      }
      if (out.isNotEmpty) {
        final prev = out.last;
        final d = GeoUtils.distanceMeters(
          prev.lat,
          prev.lng,
          next.lat,
          next.lng,
        );
        if (d < 8) continue;
      }
      out.add(next);
    }
    return out;
  }

  /// Drop thin V / hairpin spikes (including near the end of the trail).
  static List<GpsGapInputPoint> stripSpikePoints(
      List<GpsGapInputPoint> points) {
    if (points.length < 3) return points;
    var work = List<GpsGapInputPoint>.from(points);
    // Multiple passes — nested spikes / long V loops.
    for (var pass = 0; pass < 3; pass++) {
      final out = <GpsGapInputPoint>[work.first];
      for (var i = 1; i < work.length - 1; i++) {
        final prev = out.last;
        final mid = work[i];
        final next = work[i + 1];
        final dPrev =
            GeoUtils.distanceMeters(prev.lat, prev.lng, mid.lat, mid.lng);
        final dNext =
            GeoUtils.distanceMeters(mid.lat, mid.lng, next.lat, next.lng);
        final dSkip =
            GeoUtils.distanceMeters(prev.lat, prev.lng, next.lat, next.lng);
        if (dPrev > spikeOutMinMeters &&
            dNext > spikeOutMinMeters &&
            dSkip < spikeSkipMaxMeters &&
            dSkip < dPrev * 0.55 &&
            dSkip < dNext * 0.55) {
          continue;
        }
        // Long thin spike: out-and-back where return nearly retraces.
        if (dPrev > 80 &&
            dNext > 80 &&
            dSkip < dPrev * 0.35 &&
            dSkip < dNext * 0.35) {
          continue;
        }
        out.add(mid);
      }
      out.add(work.last);
      final nextWork = stripDetourLoops(stripBacktrackLoops(out));
      if (nextWork.length >= work.length) {
        work = nextWork;
        break;
      }
      work = nextWork;
    }
    return work;
  }

  /// Drop GPS detours that leave and return near the same point (bungalow loops).
  static List<GpsGapInputPoint> stripDetourLoops(
    List<GpsGapInputPoint> points, {
    double maxReturnChordMeters = 75,
    double minLoopPathMeters = 100,
    double minPathVsChordRatio = 2.6,
    double maxLoopPathMeters = 2200,
  }) {
    if (points.length < 5) return points;
    var work = List<GpsGapInputPoint>.from(points);

    for (var pass = 0; pass < 5; pass++) {
      int? bestI;
      int? bestJ;
      var bestPath = 0.0;

      for (var i = 0; i < work.length - 4; i++) {
        var pathFromI = 0.0;
        for (var j = i + 1; j < work.length; j++) {
          pathFromI += GeoUtils.distanceMeters(
            work[j - 1].lat,
            work[j - 1].lng,
            work[j].lat,
            work[j].lng,
          );
          if (pathFromI > maxLoopPathMeters) break;
          if (j < i + 3) continue;
          if (pathFromI < minLoopPathMeters) continue;

          final chord = GeoUtils.distanceMeters(
            work[i].lat,
            work[i].lng,
            work[j].lat,
            work[j].lng,
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

      final next = <GpsGapInputPoint>[
        ...work.sublist(0, bestI + 1),
        ...work.sublist(bestJ),
      ];
      if (next.length > bestI + 1) {
        final d = GeoUtils.distanceMeters(
          next[bestI].lat,
          next[bestI].lng,
          next[bestI + 1].lat,
          next[bestI + 1].lng,
        );
        if (d < 18) next.removeAt(bestI + 1);
      }
      if (next.length >= work.length) break;
      work = next;
    }

    return work;
  }

  /// Kill/reopen used to persist multiple Directions generations for the same
  /// B→C gap. Keep a single corridor so the map does not paint parallel fakes.
  static List<GpsGapInputPoint> collapseDuplicateFillerRuns(
    List<GpsGapInputPoint> points,
  ) {
    if (points.length < 3) return points;
    final out = <GpsGapInputPoint>[];
    var i = 0;
    while (i < points.length) {
      final p = points[i];
      final isFiller = p.source == fillerSource;
      if (!isFiller) {
        out.add(p);
        i++;
        continue;
      }

      final run = <GpsGapInputPoint>[];
      while (i < points.length && points[i].source == fillerSource) {
        run.add(points[i]);
        i++;
      }

      final groups = <String, List<GpsGapInputPoint>>{};
      for (final f in run) {
        final id = f.pointId ?? '';
        String key;
        if (id.startsWith('gapfill_')) {
          // gapfill_{req}_{from}_{to}_{index} → group by gap window
          final parts = id.split('_');
          key = parts.length >= 4
              ? parts.sublist(0, parts.length - 1).join('_')
              : id;
        } else if (id.startsWith('gap_')) {
          final parts = id.split('_');
          key = parts.length >= 3
              ? parts.sublist(0, parts.length - 1).join('_')
              : id;
        } else {
          key = 'legacy';
        }
        groups.putIfAbsent(key, () => []).add(f);
      }

      if (groups.length <= 1) {
        out.addAll(_thinSpatial(run, minSeparationM: 25));
        continue;
      }

      // Prefer deterministic gapfill_/gap_ groups over legacy UUID spam.
      final ranked = groups.entries.toList()
        ..sort((a, b) {
          final aDet = a.key != 'legacy' ? 1 : 0;
          final bDet = b.key != 'legacy' ? 1 : 0;
          if (aDet != bDet) return bDet - aDet;
          return b.value.length.compareTo(a.value.length);
        });
      out.addAll(_thinSpatial(ranked.first.value, minSeparationM: 25));
    }
    return out;
  }

  static List<GpsGapInputPoint> _thinSpatial(
    List<GpsGapInputPoint> points, {
    required double minSeparationM,
  }) {
    if (points.length <= 1) return points;
    final out = <GpsGapInputPoint>[points.first];
    for (var i = 1; i < points.length; i++) {
      final prev = out.last;
      final next = points[i];
      final d =
          GeoUtils.distanceMeters(prev.lat, prev.lng, next.lat, next.lng);
      if (d >= minSeparationM) out.add(next);
    }
    return out;
  }

  /// Fill gaps in ordered GPS samples. Failed / non-fillable large hops start a
  /// new contiguous segment so callers never paint a false straight chord.
  ///
  /// [forDisplay]: treat large hops with missing timestamps as kill gaps and
  /// fill them (app-kill → reopen maps often lose dt on synced points).
  static Future<GpsGapFillResult> fillPoints({
    required List<GpsGapInputPoint> points,
    DistanceService? distanceService,
    bool forDisplay = false,
  }) async {
    final cleaned = stripSpikePoints(collapseDuplicateFillerRuns(points));
    if (cleaned.isEmpty) {
      return const GpsGapFillResult(
        segments: [],
        roadFillMeters: 0,
        gapsFilled: 0,
        gapsSkipped: 0,
      );
    }

    final service = distanceService ?? DistanceService();
    final segments = <List<GpsGapOutputPoint>>[];
    var current = <GpsGapOutputPoint>[
      GpsGapOutputPoint.fromInput(cleaned.first),
    ];
    var roadFillMeters = 0.0;
    var gapsFilled = 0;
    var gapsSkipped = 0;

    void breakTo(GpsGapInputPoint next) {
      gapsSkipped++;
      if (current.isNotEmpty) segments.add(current);
      current = <GpsGapOutputPoint>[GpsGapOutputPoint.fromInput(next)];
    }

    for (var i = 1; i < cleaned.length; i++) {
      final prev = cleaned[i - 1];
      final next = cleaned[i];
      final directDist = GeoUtils.distanceMeters(
        prev.lat,
        prev.lng,
        next.lat,
        next.lng,
      );

      final prevTime = prev.time;
      final nextTime = next.time;
      final hasTimes = prevTime != null && nextTime != null;
      final timeDiff = hasTimes ? nextTime.difference(prevTime) : Duration.zero;

      // Kill / long-silence gaps. Map paint also fills large hops with no dt.
      final wantsFill = isFillableGap(
        timeGap: timeDiff,
        straightLineMeters: directDist,
        fillLargeHopsWithoutTime: forDisplay || !hasTimes,
      );

      if (wantsFill) {
        DrivingRouteOption? route;
        try {
          final routes = await service.fetchDrivingRoutesWithAlternatives(
            originLatitude: prev.lat,
            originLongitude: prev.lng,
            destinationLatitude: next.lat,
            destinationLongitude: next.lng,
          );
          // Kill / long silence: allow river-bend detours (not just 2× chord).
          final isKill = timeDiff >= minTimeGap ||
              forDisplay ||
              !hasTimes ||
              directDist >= softFillMinMeters;
          route = pickSaneRoute(
            routes,
            directDist,
            forKillGap: isKill,
          );
          if (route == null && routes.isNotEmpty) {
          }
        } catch (e) {
        }

        if (route != null && route.polylinePoints.length >= 2) {
          final routePoints = route.polylinePoints;
          final stepMs = hasTimes
              ? (timeDiff.inMilliseconds ~/ (routePoints.length + 1))
                  .clamp(1, 1 << 30)
              : 1000;
          final baseTime = prevTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          for (var j = 1; j < routePoints.length - 1; j++) {
            final pt = routePoints[j];
            current.add(
              GpsGapOutputPoint(
                lat: pt.latitude,
                lng: pt.longitude,
                time: baseTime.add(Duration(milliseconds: stepMs * j)),
                source: fillerSource,
              ),
            );
          }
          current.add(GpsGapOutputPoint.fromInput(next));
          roadFillMeters += route.distanceKm * 1000.0;
          gapsFilled++;
          continue;
        }

        breakTo(next);
        continue;
      }

      // Non-fillable but still a large hop: never paint a building-cutting chord.
      if (shouldBreakUnfilledChord(directDist)) {
        breakTo(next);
        continue;
      }

      current.add(GpsGapOutputPoint.fromInput(next));
    }

    if (current.isNotEmpty) segments.add(current);

    return GpsGapFillResult(
      segments: segments,
      roadFillMeters: roadFillMeters,
      gapsFilled: gapsFilled,
      gapsSkipped: gapsSkipped,
    );
  }

  /// Map-oriented fill: contiguous LatLng segments (breaks on failed fills).
  ///
  /// [forDisplay] defaults false — aggressive per-hop Directions made trails
  /// worse when Snap-to-Roads was unavailable. Prefer snap, then kill-gap only.
  static Future<List<List<LatLng>>> fillMapSegments({
    required List<GpsGapInputPoint> points,
    DistanceService? distanceService,
    bool forDisplay = false,
  }) async {
    final result = await fillPoints(
      points: points,
      distanceService: distanceService,
      forDisplay: forDisplay,
    );
    return result.segments
        .map(
          (seg) => seg.map((p) => LatLng(p.lat, p.lng)).toList(growable: false),
        )
        .where((seg) => seg.isNotEmpty)
        .toList(growable: false);
  }

  /// Route-point fill for metrics / Hive. Failed gaps start a new segment so
  /// Haversine never counts the false chord; [roadFillMeters] is Directions km.
  static Future<GpsGapRoutePointsResult> fillRoutePoints({
    required List<RoutePointModel> points,
    required String legId,
    DistanceService? distanceService,
  }) async {
    if (points.isEmpty) {
      return const GpsGapRoutePointsResult(
        segments: [],
        roadFillMeters: 0,
        gapsFilled: 0,
        gapsSkipped: 0,
      );
    }

    final sorted = List<RoutePointModel>.from(points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Drop one-point teleport spikes before metrics fill.
    final spikeFiltered = <RoutePointModel>[];
    if (sorted.isNotEmpty) {
      spikeFiltered.add(sorted.first);
      for (var i = 1; i < sorted.length - 1; i++) {
        final prev = spikeFiltered.last;
        final mid = sorted[i];
        final next = sorted[i + 1];
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
        if (dPrev > spikeOutMinMeters &&
            dNext > spikeOutMinMeters &&
            dSkip < spikeSkipMaxMeters &&
            dSkip < dPrev * 0.45 &&
            dSkip < dNext * 0.45) {
          continue;
        }
        spikeFiltered.add(mid);
      }
      spikeFiltered.add(sorted.last);
    }

    RoutePointModel normalize(RoutePointModel p) => p.legId == legId
        ? p
        : RoutePointModel(
            pointId: p.pointId,
            requestId: p.requestId,
            legId: legId,
            sessionId: p.sessionId,
            timestamp: p.timestamp,
            latitude: p.latitude,
            longitude: p.longitude,
            accuracy: p.accuracy,
            speed: p.speed,
            heading: p.heading,
            altitude: p.altitude,
            isMoving: p.isMoving,
            isStopMarker: p.isStopMarker,
            source: p.source,
            isSynced: p.isSynced,
          );

    final service = distanceService ?? DistanceService();
    final segments = <List<RoutePointModel>>[];
    if (spikeFiltered.isEmpty) {
      return const GpsGapRoutePointsResult(
        segments: [],
        roadFillMeters: 0,
        gapsFilled: 0,
        gapsSkipped: 0,
      );
    }
    var current = <RoutePointModel>[normalize(spikeFiltered.first)];
    var roadFillMeters = 0.0;
    var gapsFilled = 0;
    var gapsSkipped = 0;

    for (var i = 1; i < spikeFiltered.length; i++) {
      final prev = spikeFiltered[i - 1];
      final next = spikeFiltered[i];
      final timeDiff = next.timestamp.difference(prev.timestamp);
      final directDist = GeoUtils.distanceMeters(
        prev.latitude,
        prev.longitude,
        next.latitude,
        next.longitude,
      );

      if (!isFillableGap(
        timeGap: timeDiff,
        straightLineMeters: directDist,
      )) {
        if (shouldBreakUnfilledChord(directDist)) {
          gapsSkipped++;
          if (current.isNotEmpty) segments.add(current);
          current = <RoutePointModel>[normalize(next)];
        } else {
          current.add(normalize(next));
        }
        continue;
      }

      final single = await fillSingleGap(
        fromLat: prev.latitude,
        fromLng: prev.longitude,
        fromTime: prev.timestamp,
        toLat: next.latitude,
        toLng: next.longitude,
        toTime: next.timestamp,
        distanceService: service,
      );

      if (single == null) {
        gapsSkipped++;
        if (current.isNotEmpty) segments.add(current);
        current = <RoutePointModel>[normalize(next)];
        continue;
      }

      for (var j = 0; j < single.midpoints.length; j++) {
        final mid = single.midpoints[j];
        current.add(
          RoutePointModel(
            // Stable id so rematch / reopen does not duplicate Hive rows.
            pointId: 'gap_${prev.pointId}_${next.pointId}_$j',
            requestId: prev.requestId,
            legId: legId,
            sessionId: prev.sessionId,
            timestamp: mid.time ?? prev.timestamp,
            latitude: mid.lat,
            longitude: mid.lng,
            accuracy: 10.0,
            speed: 0.0,
            heading: 0.0,
            altitude: 0.0,
            isMoving: true,
            isStopMarker: false,
            source: fillerSource,
            isSynced: false,
          ),
        );
      }
      current.add(normalize(next));
      roadFillMeters += single.roadMeters;
      gapsFilled++;
    }

    if (current.isNotEmpty) segments.add(current);

    return GpsGapRoutePointsResult(
      segments: segments,
      roadFillMeters: roadFillMeters,
      gapsFilled: gapsFilled,
      gapsSkipped: gapsSkipped,
    );
  }

  /// Directions path between two fixes (resume / single gap).
  static Future<GpsGapSingleFill?> fillSingleGap({
    required double fromLat,
    required double fromLng,
    required DateTime fromTime,
    required double toLat,
    required double toLng,
    required DateTime toTime,
    DistanceService? distanceService,
  }) async {
    final timeDiff = toTime.difference(fromTime);
    final directDist = GeoUtils.distanceMeters(fromLat, fromLng, toLat, toLng);
    if (!isFillableGap(timeGap: timeDiff, straightLineMeters: directDist)) {
      return null;
    }

    final service = distanceService ?? DistanceService();
    try {
      final routes = await service.fetchDrivingRoutesWithAlternatives(
        originLatitude: fromLat,
        originLongitude: fromLng,
        destinationLatitude: toLat,
        destinationLongitude: toLng,
      );
      if (routes.isEmpty) {
        return null;
      }
      final route = pickSaneRoute(routes, directDist, forKillGap: true);
      if (route == null || route.polylinePoints.length < 2) {
        return null;
      }
      final mid = <GpsGapOutputPoint>[];
      final stepMs =
          timeDiff.inMilliseconds ~/ (route.polylinePoints.length + 1);
      for (var j = 1; j < route.polylinePoints.length - 1; j++) {
        final pt = route.polylinePoints[j];
        mid.add(
          GpsGapOutputPoint(
            lat: pt.latitude,
            lng: pt.longitude,
            time: fromTime.add(Duration(milliseconds: stepMs * j)),
            source: fillerSource,
          ),
        );
      }
      return GpsGapSingleFill(
        midpoints: mid,
        roadMeters: route.distanceKm * 1000.0,
        straightLineMeters: directDist,
      );
    } catch (e) {
      return null;
    }
  }
}

class GpsGapInputPoint {
  final double lat;
  final double lng;
  final DateTime? time;
  final String? source;
  final String? pointId;

  const GpsGapInputPoint({
    required this.lat,
    required this.lng,
    this.time,
    this.source,
    this.pointId,
  });
}

class GpsGapOutputPoint {
  final double lat;
  final double lng;
  final DateTime? time;
  final String? source;

  const GpsGapOutputPoint({
    required this.lat,
    required this.lng,
    this.time,
    this.source,
  });

  factory GpsGapOutputPoint.fromInput(GpsGapInputPoint p) => GpsGapOutputPoint(
        lat: p.lat,
        lng: p.lng,
        time: p.time,
        source: null,
      );
}

class GpsGapFillResult {
  final List<List<GpsGapOutputPoint>> segments;
  final double roadFillMeters;
  final int gapsFilled;
  final int gapsSkipped;

  const GpsGapFillResult({
    required this.segments,
    required this.roadFillMeters,
    required this.gapsFilled,
    required this.gapsSkipped,
  });

  List<GpsGapOutputPoint> get allPoints =>
      segments.expand((s) => s).toList(growable: false);
}

class GpsGapRoutePointsResult {
  final List<List<RoutePointModel>> segments;
  final double roadFillMeters;
  final int gapsFilled;
  final int gapsSkipped;

  const GpsGapRoutePointsResult({
    required this.segments,
    required this.roadFillMeters,
    required this.gapsFilled,
    required this.gapsSkipped,
  });

  List<RoutePointModel> get allPoints =>
      segments.expand((s) => s).toList(growable: false);
}

class GpsGapSingleFill {
  final List<GpsGapOutputPoint> midpoints;
  final double roadMeters;
  final double straightLineMeters;

  const GpsGapSingleFill({
    required this.midpoints,
    required this.roadMeters,
    required this.straightLineMeters,
  });
}

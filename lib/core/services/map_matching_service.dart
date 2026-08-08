import 'dart:async';

import '../database/hive_database.dart';
import '../di/service_locator.dart';
import '../network/models/api_result.dart';
import '../utils/distance_sanity.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../modules/travel/data/models/route_segment_model.dart';
import '../../modules/travel/data/models/travel_request_model.dart';

/// Fetches / caches Nest map-match results and merges official km into trips.
class MapMatchingService {
  MapMatchingService({
    TravelRequestRemoteDataSource? travelApi,
    HiveDatabase? db,
  })  : _travelApi = travelApi,
        _db = db ?? HiveDatabase.instance;

  final TravelRequestRemoteDataSource? _travelApi;
  final HiveDatabase _db;

  final _matchedController =
      StreamController<MatchedRouteResult>.broadcast();

  /// Emits whenever a match result is applied (REST or WS).
  Stream<MatchedRouteResult> get matchedRouteUpdates =>
      _matchedController.stream;

  TravelRequestRemoteDataSource _api() =>
      _travelApi ?? ServiceLocator.I.get<TravelRequestRemoteDataSource>();

  /// Load cached match, then refresh from API when online.
  Future<MatchedRouteResult?> fetchMatchedRoute(
    String requestId, {
    bool preferNetwork = true,
  }) async {
    if (requestId.isEmpty) return null;

    MatchedRouteResult? cached;
    final cachedMap = await _db.getMatchedRouteCache(requestId);
    if (cachedMap != null) {
      cached = MatchedRouteResult.fromMap(cachedMap);
    }

    if (!preferNetwork) return cached;

    try {
      final res = await _api().getMatchedRoute(requestId);
      if (res case ApiSuccess(:final data)) {
        await _db.saveMatchedRouteCache(requestId, data.toMap());
        _matchedController.add(data);
        return data;
      }
    } catch (_) {}

    return cached;
  }

  /// Ask Nest to rematch after GPS catch-up / trip end.
  Future<MatchedRouteResult?> triggerMatch(
    String requestId, {
    String reason = 'catch_up',
  }) async {
    if (requestId.isEmpty) return null;
    try {
      final res = await _api().triggerRouteMatch(requestId, reason: reason);
      if (res case ApiSuccess(:final data)) {
        if (data.isReady) {
          await _db.saveMatchedRouteCache(requestId, data.toMap());
          _matchedController.add(data);
        }
        return data;
      }
    } catch (_) {}
    return null;
  }

  /// Apply WS / REST match payload into local cache + return updated trip.
  Future<TravelRequestModel> applyMatchToRequest(
    TravelRequestModel request,
    MatchedRouteResult match,
  ) async {
    final id = request.restResourceId.isNotEmpty
        ? request.restResourceId
        : request.requestId;
    if (id.isNotEmpty) {
      await _db.saveMatchedRouteCache(id, match.toMap());
    }
    _matchedController.add(match);

    if (!match.isReady && match.legs.isEmpty && match.segments.isEmpty) {
      return request;
    }

    final byLeg = <String, MatchedLegMetrics>{
      for (final leg in match.legs)
        if (leg.legId.isNotEmpty) leg.legId: leg,
    };

    final updatedLegs = request.tripLegs.map((leg) {
      final m = byLeg[leg.legId];
      if (m == null) {
        // Trip-level official only: never overwrite stored GPS km.
        if (match.officialDistanceKm != null && request.tripLegs.length == 1) {
          final gps = leg.provisionalDistanceKm ??
              leg.actualDistanceKmFromTrack ??
              match.provisionalDistanceKm;
          final official = match.officialDistanceKm!;
          if (DistanceSanity.isOfficialAbsurd(
            officialKm: official,
            gpsKm: gps,
            plannedKm: leg.plannedDistanceKm,
            travelMinutes: leg.travelDurationMinutes,
          )) {
            return leg.copyWith(
              provisionalDistanceKm: gps ?? leg.provisionalDistanceKm,
              clearOfficialDistanceKm: true,
              clearMatchedRoutePolylineEncoded: true,
            );
          }
          return leg.copyWith(
            officialDistanceKm: official,
            provisionalDistanceKm: gps ?? leg.provisionalDistanceKm,
            matchedRoutePolylineEncoded: match.segments.isNotEmpty
                ? _joinSegmentPolylines(match.segments)
                : leg.matchedRoutePolylineEncoded,
          );
        }
        return leg;
      }

      // Prefer already-persisted GPS over Nest match provisional (stable cards).
      final gps = leg.provisionalDistanceKm ??
          leg.actualDistanceKmFromTrack ??
          m.provisionalDistanceKm;
      final official = m.officialDistanceKm;
      if (official != null &&
          DistanceSanity.isOfficialAbsurd(
            officialKm: official,
            gpsKm: gps,
            plannedKm: leg.plannedDistanceKm,
            travelMinutes: leg.travelDurationMinutes,
          )) {
        return leg.copyWith(
          provisionalDistanceKm: gps ?? leg.provisionalDistanceKm,
          clearOfficialDistanceKm: true,
          clearMatchedRoutePolylineEncoded: true,
          clearMatchConfidence: true,
          clearEstimatedPct: true,
        );
      }

      return leg.copyWith(
        officialDistanceKm: official,
        provisionalDistanceKm: gps ?? leg.provisionalDistanceKm,
        matchedRoutePolylineEncoded: m.matchedPolylineEncoded,
        matchConfidence: m.confidence,
        estimatedPct: m.estimatedPct,
      );
    }).toList();

    final updated = request
        .copyWith(tripLegs: updatedLegs)
        .sanitizeAbsurdOfficialDistances()
        .withRecalculatedSummary();
    try {
      await _db.saveTravelRequest(updated.toMap());
    } catch (_) {}
    return updated;
  }

  /// Fetch match (cache→network) and merge into [request].
  Future<TravelRequestModel> enhanceWithOfficialMatch(
    TravelRequestModel request,
  ) async {
    final id = request.restResourceId.isNotEmpty
        ? request.restResourceId
        : request.requestId;
    final match = await fetchMatchedRoute(id);
    if (match == null || (!match.isReady && match.legs.isEmpty)) {
      return request;
    }
    return applyMatchToRequest(request, match);
  }

  /// Segments for map Layer B (official). Prefers cache.
  Future<List<RouteSegmentModel>> loadSegmentsForRequest(
    String requestId,
  ) async {
    final match = await fetchMatchedRoute(requestId, preferNetwork: false);
    if (match == null) return const [];
    if (match.segments.isNotEmpty) return match.segments;
    final out = <RouteSegmentModel>[];
    for (final leg in match.legs) {
      out.addAll(leg.segments);
    }
    return out;
  }

  static String _joinSegmentPolylines(List<RouteSegmentModel> segments) {
    final parts = <String>[];
    for (final s in segments) {
      for (final part in s.polylineEncoded.split('|')) {
        final t = part.trim();
        if (t.isNotEmpty) parts.add(t);
      }
    }
    return parts.join('|');
  }

  void dispose() {
    _matchedController.close();
  }
}

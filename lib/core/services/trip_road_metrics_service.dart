import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/google_maps_config.dart';
import '../database/hive_database.dart';
import '../di/service_locator.dart';
import '../network/models/api_result.dart';
import '../utils/geo_utils.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../modules/travel/data/models/route_point_model.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'distance_service.dart';
import 'gps_gap_road_fill.dart';
import 'sync_service.dart';
import 'track_analytics.dart';

/// Recomputes leg GPS km + allowance so list cards match detail/route paint.
///
/// Home cards used stale API totals until the detail screen ran this logic.
class TripRoadMetricsService {
  TripRoadMetricsService({
    TravelRequestRemoteDataSource? travelApi,
    HiveDatabase? hive,
    DistanceService? distanceService,
  })  : _travelApi = travelApi,
        _hive = hive ?? HiveDatabase.instance,
        _distance = distanceService ?? DistanceService();

  final TravelRequestRemoteDataSource? _travelApi;
  final HiveDatabase _hive;
  final DistanceService _distance;

  TravelRequestRemoteDataSource? get _api {
    if (_travelApi != null) return _travelApi;
    if (ServiceLocator.I.has<TravelRequestRemoteDataSource>()) {
      return ServiceLocator.I.get<TravelRequestRemoteDataSource>();
    }
    return null;
  }

  /// Enhance one request from Hive/API GPS; persists + syncs when changed.
  Future<TravelRequestModel> enhance(
    TravelRequestModel current, {
    bool persist = true,
  }) async {
    if (!_needsEnhance(current)) {
      return current.sanitizeAbsurdOfficialDistances().withRecalculatedSummary();
    }

    final pointsRaw = await _hive.getRoutePointsForRequest(current.requestId);
    var allPoints = pointsRaw.map(RoutePointModel.fromMap).toList();

    if (allPoints.isEmpty && current.routePoints.isNotEmpty) {
      allPoints =
          current.routePoints.map(RoutePointModel.fromMap).toList();
    }

    final api = _api;
    if (allPoints.isEmpty &&
        api != null &&
        current.restResourceId.isNotEmpty) {
      try {
        final res = await api.listRoutePoints(current.restResourceId);
        if (res case ApiSuccess(:final data)) {
          allPoints = data.map(RoutePointModel.fromMap).toList();
        }
      } catch (_) {}
    }

    var updatedLegs = <TripLegModel>[];
    var changed = false;

    for (final leg in current.tripLegs) {
      if (leg.departurePunch == null) {
        updatedLegs.add(leg);
        continue;
      }

      final start = leg.departurePunch!.time.toUtc();
      final end = leg.arrivalPunch?.time.toUtc() ?? DateTime.now().toUtc();
      final legPoints = allPoints.where((p) {
        if (p.legId == leg.legId) return true;
        final t = p.timestamp.toUtc();
        return !t.isBefore(start) && !t.isAfter(end);
      }).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (legPoints.length >= 2) {
        final filled = await GpsGapRoadFill.fillRoutePoints(
          points: legPoints,
          legId: leg.legId,
          distanceService: _distance,
        );

        var totalKm = 0.0;
        var movingMinutes = 0;
        var stoppedMinutes = 0;
        final coords = <List<double>>[];

        for (final seg in filled.segments) {
          if (seg.isEmpty) continue;
          if (seg.length < 2) {
            coords.add([seg.first.latitude, seg.first.longitude]);
            continue;
          }
          final segStart =
              seg.first.timestamp.isBefore(start) ? start : seg.first.timestamp;
          final segEnd =
              seg.last.timestamp.isAfter(end) ? end : seg.last.timestamp;
          final legMetrics = TrackAnalytics.computeLegMetrics(
            points: seg,
            legId: leg.legId,
            startInclusive: segStart,
            endInclusive: segEnd,
            vehicleType: current.vehicleType,
          );
          totalKm += legMetrics.distanceKm;
          movingMinutes += legMetrics.movingMinutes;
          stoppedMinutes += legMetrics.stoppedMinutes;
          for (final p in seg) {
            coords.add([p.latitude, p.longitude]);
          }
        }

        if (filled.roadFillMeters > 0) {
          final fillerHaversineKm = _estimateFillerHaversineKm(filled.segments);
          final directionsAwareKm =
              totalKm - fillerHaversineKm + (filled.roadFillMeters / 1000.0);
          if (directionsAwareKm > 0) totalKm = directionsAwareKm;
        }

        if (filled.gapsFilled > 0) {
          unawaited(_persistGapFillersToHive(filled.segments));
        }

        final encodedPolyline = coords.isEmpty
            ? ''
            : coords.map((c) => '${c[0]},${c[1]}').join('|');

        if (totalKm > 0 && encodedPolyline.isNotEmpty) {
          final prev = leg.actualDistanceKmFromTrack ??
              leg.provisionalDistanceKm ??
              0;
          if ((prev - totalKm).abs() > 0.05 ||
              leg.routePolylineEncoded != encodedPolyline) {
            updatedLegs.add(
              leg.copyWith(
                actualDistanceKmFromTrack: totalKm,
                provisionalDistanceKm: totalKm,
                routePolylineEncoded: encodedPolyline,
                trackMovingDurationMinutes: movingMinutes,
                trackStoppedDurationMinutes: stoppedMinutes,
              ),
            );
            changed = true;
            continue;
          }
          updatedLegs.add(leg);
          continue;
        }
      }

      final needsMetrics = leg.actualDistanceKmFromTrack == null ||
          leg.routePolylineEncoded == null ||
          leg.routePolylineEncoded!.isEmpty;

      if (needsMetrics &&
          leg.arrivalPunch != null &&
          GoogleMapsConfig.isConfigured) {
        try {
          final routes = await _distance.fetchDrivingRoutesWithAlternatives(
            originLatitude: leg.departurePunch!.latitude,
            originLongitude: leg.departurePunch!.longitude,
            destinationLatitude: leg.arrivalPunch!.latitude,
            destinationLongitude: leg.arrivalPunch!.longitude,
          );
          if (routes.isNotEmpty) {
            final best = routes.first;
            final encoded = best.polylinePoints
                .map((p) => '${p.latitude},${p.longitude}')
                .join('|');
            updatedLegs.add(
              leg.copyWith(
                actualDistanceKmFromTrack: best.distanceKm,
                provisionalDistanceKm: best.distanceKm,
                routePolylineEncoded: encoded,
              ),
            );
            changed = true;
            continue;
          }
        } catch (_) {}
      }
      updatedLegs.add(leg);
    }

    var updated = current.copyWith(tripLegs: updatedLegs);
    updated = updated.sanitizeAbsurdOfficialDistances().withRecalculatedSummary();

    if (changed ||
        (updated.totalDistanceKm - current.totalDistanceKm).abs() > 0.05 ||
        (updated.travelAllowance - current.travelAllowance).abs() > 0.5) {
      if (persist) unawaited(_persist(updated));
      return updated;
    }
    return updated;
  }

  /// Enhance many requests for list/home cards (sequential, non-blocking UI).
  Future<List<TravelRequestModel>> enhanceAll(
    List<TravelRequestModel> requests, {
    bool persist = true,
  }) async {
    final out = <TravelRequestModel>[];
    for (final r in requests) {
      try {
        out.add(await enhance(r, persist: persist));
      } catch (_) {
        out.add(r.sanitizeAbsurdOfficialDistances().withRecalculatedSummary());
      }
    }
    return out;
  }

  bool _needsEnhance(TravelRequestModel r) {
    final s = r.status.trim();
    if (s == 'Ready To Start' || s == 'Start Missing' || s == 'Cancelled') {
      return false;
    }
    return r.tripLegs.any((l) => l.departurePunch != null);
  }

  double _estimateFillerHaversineKm(List<List<RoutePointModel>> segments) {
    var meters = 0.0;
    for (final seg in segments) {
      for (var i = 1; i < seg.length; i++) {
        final a = seg[i - 1];
        final b = seg[i];
        if (a.source == GpsGapRoadFill.fillerSource ||
            b.source == GpsGapRoadFill.fillerSource) {
          meters += GeoUtils.distanceMeters(
            a.latitude,
            a.longitude,
            b.latitude,
            b.longitude,
          );
        }
      }
    }
    return meters / 1000.0;
  }

  Future<void> _persistGapFillersToHive(
    List<List<RoutePointModel>> segments,
  ) async {
    try {
      final reqId = segments
          .expand((s) => s)
          .map((p) => p.requestId)
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      if (reqId.isEmpty) return;
      final existing = await _hive.getRoutePointsForRequest(reqId);
      final existingIds = {
        for (final m in existing) m['pointId']?.toString(),
      }..removeWhere((id) => id == null || id.isEmpty);

      var saved = 0;
      for (final seg in segments) {
        for (final p in seg) {
          if (p.source != GpsGapRoadFill.fillerSource) continue;
          if (existingIds.contains(p.pointId)) continue;
          await _hive.saveRoutePoint(p.copyWith(isSynced: false).toHiveMap());
          saved++;
        }
      }
      if (saved == 0) return;
      if (ServiceLocator.I.has<SyncService>()) {
        unawaited(
          ServiceLocator.I.get<SyncService>().uploadPendingRoutePoints(),
        );
      }
    } catch (e) {
      debugPrint('TripRoadMetricsService: gap-filler persist failed: $e');
    }
  }

  Future<void> _persist(TravelRequestModel updated) async {
    try {
      await _hive.saveTravelRequest(updated.toMap());
      final api = _api;
      if (api == null || updated.restResourceId.isEmpty) return;
      await api.update(updated.restResourceId, {
        'tripLegs': updated.tripLegs.map((l) => l.toMap()).toList(),
        'totalDistanceKm': updated.totalDistanceKm,
        'travelAllowance': updated.travelAllowance,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }
}

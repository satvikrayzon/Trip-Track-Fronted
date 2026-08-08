import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/google_maps_config.dart';
import '../database/hive_database.dart';
import '../di/service_locator.dart';
import '../network/models/api_result.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../modules/travel/data/models/route_point_model.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'distance_service.dart';
import 'gps_gap_road_fill.dart';
import 'road_aligned_route_service.dart';
import 'sync_service.dart';
import 'track_analytics.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Recomputes leg GPS km + allowance so list cards / admin match the GPS trail.
///
/// - Details open: [syncFromTrack] false — do not rewrite locked km.
/// - Admin list / report: [syncFromTrack] true — recompute from route
///   points once and PATCH server so everyone sees the same actual km.
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
  ///
  /// [force] recomputes even when locked.
  /// [syncFromTrack] refreshes completed-leg km from route points (admin/list).
  Future<TravelRequestModel> enhance(
    TravelRequestModel current, {
    bool persist = true,
    bool force = false,
    bool syncFromTrack = false,
  }) async {
    if (!_needsEnhance(
      current,
      force: force,
      syncFromTrack: syncFromTrack,
    )) {
      return current.sanitizeAbsurdOfficialDistances().withRecalculatedSummary();
    }

    final allPoints = await _loadAllRoutePoints(current);
    var updatedLegs = <TripLegModel>[];
    var changed = false;

    for (final leg in current.tripLegs) {
      if (leg.departurePunch == null) {
        updatedLegs.add(leg);
        continue;
      }

      final storedGps =
          leg.provisionalDistanceKm ?? leg.actualDistanceKmFromTrack;

      // Details mode: freeze completed legs that already have GPS km.
      if (!force &&
          !syncFromTrack &&
          leg.arrivalPunch != null &&
          storedGps != null &&
          storedGps > 0.05) {
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
        // Same road-align engine as the map — km matches what the user sees.
        final alignInput = legPoints
            .map(
              (p) => GpsGapInputPoint(
                lat: p.latitude,
                lng: p.longitude,
                time: p.timestamp,
                source: p.source,
                pointId: p.pointId,
              ),
            )
            .toList(growable: false);
        final aligned = await RoadAlignedRouteService().align(
          gpsPoints: alignInput,
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

        var totalKm = aligned.isEmpty ? 0.0 : aligned.distanceKm;
        var movingMinutes = 0;
        var stoppedMinutes = 0;

        // Moving/stopped minutes from raw GPS (legId-tolerant).
        final legMetrics = TrackAnalytics.computeLegMetrics(
          points: legPoints,
          legId: leg.legId,
          startInclusive: start,
          endInclusive: end,
          vehicleType: current.vehicleType,
        );
        movingMinutes = legMetrics.movingMinutes;
        stoppedMinutes = legMetrics.stoppedMinutes;
        if (totalKm <= 0.05 && legMetrics.distanceKm > 0.05) {
          totalKm = legMetrics.distanceKm;
        }

        final filled = await GpsGapRoadFill.fillRoutePoints(
          points: legPoints,
          legId: leg.legId,
          distanceService: _distance,
        );
        if (filled.gapsFilled > 0) {
          unawaited(_persistGapFillersToHive(filled.segments));
        }

        final coords = <List<double>>[];
        if (aligned.points.length >= 2) {
          for (final p in aligned.points) {
            coords.add([p.latitude, p.longitude]);
          }
        } else {
          for (final seg in filled.segments) {
            for (final p in seg) {
              coords.add([p.latitude, p.longitude]);
            }
          }
        }

        final encodedPolyline = coords.isEmpty
            ? ''
            : coords.map((c) => '${c[0]},${c[1]}').join('|');

        if (totalKm > 0) {
          final prev = storedGps ?? 0;
          // Never overwrite a higher stored GPS km with a lower recompute
          // (that was PATCHing 17.78 over the real ~20.5).
          if (prev > 0.05 && totalKm < prev - 0.15 && !force) {
            updatedLegs.add(leg);
            continue;
          }
          final kmChanged = (prev - totalKm).abs() > 0.15;
          final polyMissing = encodedPolyline.isNotEmpty &&
              (leg.routePolylineEncoded == null ||
                  leg.routePolylineEncoded!.isEmpty);
          if (kmChanged || polyMissing || prev <= 0) {
            updatedLegs.add(
              leg.copyWith(
                actualDistanceKmFromTrack: totalKm,
                provisionalDistanceKm: totalKm,
                routePolylineEncoded: encodedPolyline.isNotEmpty
                    ? encodedPolyline
                    : leg.routePolylineEncoded,
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
          (leg.provisionalDistanceKm == null ||
              leg.provisionalDistanceKm! <= 0);

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
    updated =
        updated.sanitizeAbsurdOfficialDistances().withRecalculatedSummary();

    if (changed ||
        (updated.totalDistanceKm - current.totalDistanceKm).abs() > 0.05 ||
        (updated.travelAllowance - current.travelAllowance).abs() > 0.5) {
      if (persist) await _persist(updated);
      return updated;
    }
    return updated;
  }

  /// Enhance many requests for list/home/report cards.
  Future<List<TravelRequestModel>> enhanceAll(
    List<TravelRequestModel> requests, {
    bool persist = true,
    bool force = false,
    bool syncFromTrack = false,
  }) async {
    final out = <TravelRequestModel>[];
    for (final r in requests) {
      try {
        out.add(
          await enhance(
            r,
            persist: persist,
            force: force,
            syncFromTrack: syncFromTrack,
          ),
        );
      } catch (_) {
        out.add(r.sanitizeAbsurdOfficialDistances().withRecalculatedSummary());
      }
    }
    return out;
  }

  Future<List<RoutePointModel>> _loadAllRoutePoints(
    TravelRequestModel current,
  ) async {
    final pointsRaw = await _hive.getRoutePointsForRequest(current.requestId);
    var allPoints = pointsRaw.map(RoutePointModel.fromMap).toList();

    if (allPoints.isEmpty && current.routePoints.isNotEmpty) {
      allPoints = current.routePoints.map(RoutePointModel.fromMap).toList();
    }

    final api = _api;
    // Always prefer server trail for admin/list sync (user device Hive may be empty).
    if (api != null && current.restResourceId.isNotEmpty) {
      try {
        final res = await api.listRoutePoints(current.restResourceId);
        if (res case ApiSuccess(:final data)) {
          final server = data.map(RoutePointModel.fromMap).toList();
          if (server.length >= allPoints.length) {
            allPoints = server;
          } else if (allPoints.isEmpty) {
            allPoints = server;
          }
        }
      } catch (_) {}
    }
    return allPoints;
  }

  bool _needsEnhance(
    TravelRequestModel r, {
    bool force = false,
    bool syncFromTrack = false,
  }) {
    final s = r.status.trim();
    if (s == 'Ready To Start' || s == 'Start Missing' || s == 'Cancelled') {
      return false;
    }
    if (force || syncFromTrack) {
      return r.tripLegs.any((l) => l.departurePunch != null);
    }

    final inProgressTravel = r.tripLegs.any(
      (l) => l.departurePunch != null && l.arrivalPunch == null,
    );

    final completed =
        r.tripLegs.where((l) => l.arrivalPunch != null).toList();
    if (!inProgressTravel &&
        completed.isNotEmpty &&
        completed.every((l) {
          final g = l.provisionalDistanceKm ?? l.actualDistanceKmFromTrack;
          return g != null && g > 0.05;
        })) {
      return false;
    }

    return r.tripLegs.any((l) {
      if (l.departurePunch == null) return false;
      final gps = l.provisionalDistanceKm ?? l.actualDistanceKmFromTrack;
      if (l.arrivalPunch == null) return true;
      return gps == null || gps <= 0.05;
    });
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
      final id = updated.restResourceId;
      if (api == null || id.isEmpty) {
        debugPrint(
          'TripRoadMetricsService: persist skipped '
          '(api=${api != null} id="$id")',
        );
        return;
      }

      final legs = updated.tripLegs.map((l) {
        final m = Map<String, dynamic>.from(l.toMap());
        // Nest / older DTOs sometimes use short aliases.
        if (l.provisionalDistanceKm != null) {
          m['provisionalKm'] = l.provisionalDistanceKm;
        }
        if (l.actualDistanceKmFromTrack != null) {
          m['trackKm'] = l.actualDistanceKmFromTrack;
        }
        if (l.officialDistanceKm != null) {
          m['officialKm'] = l.officialDistanceKm;
        }
        return m;
      }).toList();

      final patch = <String, dynamic>{
        'tripLegs': legs,
        'stops': legs,
        'totalDistanceKm': updated.totalDistanceKm,
        'travelAllowance': updated.travelAllowance,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

      var result = await api.update(id, patch);
      if (result is ApiFailure) {
        debugPrint(
          'TripRoadMetricsService: update() failed, retry patchTravelRequest: '
          '${result.failureOrNull?.message}',
        );
        final retry = await api.patchTravelRequest(id, patch);
        if (retry is ApiFailure) {
          debugPrint(
            'TripRoadMetricsService: PATCH km FAILED id=$id '
            'km=${updated.totalDistanceKm.toStringAsFixed(2)} '
            'err=${retry.failureOrNull?.message}',
          );
          return;
        }
      }
      debugPrint(
        'TripRoadMetricsService: PATCH km OK id=$id '
        'km=${updated.totalDistanceKm.toStringAsFixed(2)}',
      );
    } catch (e) {
      debugPrint('TripRoadMetricsService: persist exception: $e');
    }
  }
}

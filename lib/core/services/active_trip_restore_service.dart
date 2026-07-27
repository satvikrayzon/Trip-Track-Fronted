import 'package:flutter/foundation.dart';



import '../database/hive_database.dart';

import '../network/models/api_result.dart';

import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';

import '../../modules/travel/data/models/travel_request_model.dart';



/// Restores the user's in-progress trip after app restart.

class ActiveTripRestoreService {

  ActiveTripRestoreService(

    this._travelApi, {

    HiveDatabase? hive,

  }) : _hive = hive ?? HiveDatabase.instance;



  final TravelRequestRemoteDataSource _travelApi;

  final HiveDatabase _hive;



  /// Instant — Hive only (no network).

  Future<TravelRequestModel?> peekFromCache() async {

    final savedTripId = _hive.getActiveTripIdSync();

    if (savedTripId == null || savedTripId.isEmpty) return null;

    return _readCachedOnly(savedTripId);

  }



  /// Network refresh; safe to call in background.

  Future<TravelRequestModel?> refreshInBackground() async {

    try {

      return await resolveActiveTrip().timeout(const Duration(seconds: 5));

    } catch (e) {


      return peekFromCache();

    }

  }



  Future<TravelRequestModel?> resolveActiveTrip() async {

    final activeResult = await _travelApi.getActiveTravelRequest();

    switch (activeResult) {

      case ApiSuccess(:final data):

        if (data == null) {

          await _hive.clearActiveTripId();

          return null;

        }

        final restored =

            await restoreActiveTrip(TravelRequestModel.fromMap(data));

        return _hydrateRoutePoints(restored);

      case ApiFailure(:final failure):

        if (kDebugMode && failure.statusCode != 404) {


        }

        if (failure.statusCode == 404) {

          await _hive.clearActiveTripId();

          return null;

        }

        return peekFromCache();

    }

  }



  Future<TravelRequestModel> restoreActiveTrip(TravelRequestModel remote) async {

    final key = remote.requestId.isNotEmpty

        ? remote.requestId

        : remote.restResourceId;

    final cached = key.isNotEmpty ? await _readCached(key) : null;

    var merged = remote.ensureTripLegs();

    if (cached != null) {

      merged = merged.mergePreservingLocalProgress(cached).ensureTripLegs();

    }

    await _hive.saveTravelRequest(merged.toMap());

    final pinId = merged.restResourceId;

    if (pinId.isNotEmpty) {

      await _hive.saveActiveTripId(pinId);

    }

    return merged;

  }



  Future<TravelRequestModel> _hydrateRoutePoints(

    TravelRequestModel trip,

  ) async {

    if (trip.routePoints.isNotEmpty) {

      await _cacheRoutePoints(trip.requestId, trip.routePoints);

      return trip;

    }



    final id = trip.restResourceId;

    if (id.isEmpty) return trip;



    final result = await _travelApi.listRoutePoints(id);

    switch (result) {

      case ApiSuccess(:final data):

        if (data.isEmpty) return trip;

        await _cacheRoutePoints(trip.requestId, data);

        return trip.copyWith(routePoints: data);

      case ApiFailure():

        return trip;

    }

  }



  Future<void> _cacheRoutePoints(

    String requestId,

    List<Map<String, dynamic>> points,

  ) async {

    if (requestId.isEmpty || points.isEmpty) return;

    for (var i = 0; i < points.length; i++) {

      final p = points[i];

      final lat = (p['latitude'] as num?)?.toDouble();

      final lng = (p['longitude'] as num?)?.toDouble();

      if (lat == null || lng == null) continue;

      await _hive.saveRoutePoint({

        'pointId': p['pointId']?.toString() ?? '${requestId}_route_$i',

        'requestId': requestId,

        'legId': p['legId']?.toString() ?? '',

        'sessionId': p['sessionId']?.toString() ?? '',

        'timestamp': p['timestamp']?.toString() ??

            DateTime.now().toIso8601String(),

        'latitude': lat,

        'longitude': lng,

        'isSynced': true,

      });

    }

  }



  Future<void> pinActiveTrip(TravelRequestModel trip) async {

    final id = trip.restResourceId;

    if (id.isEmpty) return;

    await _hive.saveActiveTripId(id);

    await _hive.saveTravelRequest(trip.toMap());

  }



  Future<void> clearActiveTripIfCompleted(TravelRequestModel trip) async {

    if (trip.status == 'Completed' && !trip.needsReturnArrivalPunch) {

      await _hive.clearActiveTripId();

    }

  }

  /// Clears pinned active trip when it matches [tripId] or any [alternateIds].
  Future<void> clearIfMatches(
    String tripId, [
    Iterable<String> alternateIds = const [],
  ]) async {
    final active = _hive.getActiveTripIdSync();
    if (active == null || active.isEmpty) return;

    final ids = <String>{tripId, ...alternateIds}.where((id) => id.isNotEmpty);
    if (ids.contains(active)) {
      await _hive.clearActiveTripId();
    }
  }



  Future<TravelRequestModel?> _readCachedOnly(String key) async {

    final cached = await _readCached(key);

    if (cached == null) return null;

    return cached.ensureTripLegs();

  }



  Future<TravelRequestModel?> _readCached(String key) async {

    try {

      final allRequests = await _hive.getAllOfflineTravelRequests();

      for (final row in allRequests) {

        final map = Map<String, dynamic>.from(row);

        final rid = map['requestId']?.toString() ?? '';

        final mongo = map['_id']?.toString() ?? '';

        final tripId = map['tripId']?.toString() ?? map['id']?.toString() ?? '';

        if (rid == key || mongo == key || tripId == key) {

          return TravelRequestModel.fromMap(map);

        }

      }

    } catch (_) {}

    return null;

  }

}


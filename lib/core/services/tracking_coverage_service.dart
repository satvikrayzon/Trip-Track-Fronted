import 'package:flutter/foundation.dart';

import '../database/hive_database.dart';
import '../di/service_locator.dart';
import '../network/models/api_result.dart';
import '../services/connectivity_service.dart';
import '../services/track_analytics.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../modules/travel/data/models/route_point_model.dart';
import '../../modules/travel/data/models/tracking_coverage_model.dart';
import '../../modules/travel/data/models/travel_request_model.dart';

/// Loads tracking coverage — local from Hive when offline, remote when online.
class TrackingCoverageService {
  TrackingCoverageService({
    TravelRequestRemoteDataSource? travelApi,
    HiveDatabase? hive,
    ConnectivityService? connectivity,
  })  : _travelApi = travelApi,
        _hive = hive ?? HiveDatabase.instance,
        _connectivity = connectivity;

  final TravelRequestRemoteDataSource? _travelApi;
  final HiveDatabase _hive;
  final ConnectivityService? _connectivity;

  TravelRequestRemoteDataSource _api() =>
      _travelApi ?? ServiceLocator.I.get<TravelRequestRemoteDataSource>();

  bool get _isOnline => _connectivity?.isConnected.value ?? true;

  Future<TrackingCoverageResult> loadCoverage(TravelRequestModel request) async {
    final local = await _computeLocal(request);

    if (!_isOnline) {
      final cached = await _readCache(request.requestId);
      return cached ?? local;
    }

    final apiId = request.restResourceId;
    if (apiId.isEmpty) return local;

    final result = await _api().getTrackingCoverage(apiId);
    switch (result) {
      case ApiSuccess(:final data):
        await _hive.saveTrackingCoverageCache(
          request.requestId,
          data.toMap(),
        );
        return data;
      case ApiFailure(:final failure):
        final cached = await _readCache(request.requestId);
        return cached ?? local;
    }
  }

  Future<TrackingCoverageResult> _computeLocal(
    TravelRequestModel request,
  ) async {
    final raw = await _hive.getRoutePointsForRequest(request.requestId);
    final points = raw.map((e) => RoutePointModel.fromMap(e)).toList();

    if (points.isEmpty && request.routePoints.isNotEmpty) {
      for (final p in request.routePoints) {
        points.add(RoutePointModel.fromMap(p));
      }
    }

    return TrackAnalytics.computeTripCoverage(
      request: request.ensureTripLegs(),
      points: points,
    );
  }

  Future<TrackingCoverageResult?> _readCache(String requestId) async {
    final row = await _hive.getTrackingCoverageCache(requestId);
    if (row == null) return null;
    return TrackingCoverageResult.fromMap({
      ...row,
      'source': CoverageSource.cached.name,
    });
  }
}

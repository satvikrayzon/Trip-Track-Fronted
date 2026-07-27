import '../../../core/database/hive_database.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/models/api_result.dart';
import '../../../core/services/active_trip_restore_service.dart';
import '../../../core/services/sync_service.dart';
import '../data/datasources/travel_request_remote_datasource.dart';
import '../data/models/travel_request_model.dart';

/// Deletes a travel request via API and purges related local cache.
class TravelRequestDeleteService {
  TravelRequestDeleteService({
    TravelRequestRemoteDataSource? travelApi,
    HiveDatabase? hive,
    ActiveTripRestoreService? activeTripRestore,
    SyncService? syncService,
  })  : _travelApi = travelApi ?? ServiceLocator.I.get(),
        _hive = hive ?? HiveDatabase.instance,
        _activeTripRestore = activeTripRestore ??
            ActiveTripRestoreService(
              travelApi ?? ServiceLocator.I.get(),
              hive: hive ?? HiveDatabase.instance,
            ),
        _syncService = syncService ??
            (ServiceLocator.I.has<SyncService>()
                ? ServiceLocator.I.get<SyncService>()
                : null);

  final TravelRequestRemoteDataSource _travelApi;
  final HiveDatabase _hive;
  final ActiveTripRestoreService _activeTripRestore;
  final SyncService? _syncService;

  /// Returns `true` when the trip is removed (API success or 404 orphan cleanup).
  Future<bool> delete(TravelRequestModel request) async {
    final apiId = request.restResourceId;
    if (apiId.isEmpty) return false;

    final result = await _travelApi.delete(apiId);
    switch (result) {
      case ApiSuccess():
        await _cleanupLocal(request);
        return true;
      case ApiFailure(:final failure):
        if (failure.statusCode == 404) {
          await _cleanupLocal(request);
          return true;
        }
        throw failure;
    }
  }

  Future<void> _cleanupLocal(TravelRequestModel request) async {
    final ids = <String>{
      if (request.requestId.isNotEmpty) request.requestId,
      if (request.tripId.isNotEmpty) request.tripId,
      if (request.restResourceId.isNotEmpty) request.restResourceId,
      if (request.mongoDocumentId != null &&
          request.mongoDocumentId!.isNotEmpty)
        request.mongoDocumentId!,
    };

    for (final id in ids) {
      await _hive.deleteTravelRequest(id);
      await _hive.deleteRoutePointsForRequest(id);
      await _hive.deleteOfflineImagesForRequest(id);
      await _hive.purgeSyncQueueForDocument(id);
      await _activeTripRestore.clearIfMatches(id, ids);
      await _syncService?.purgeSyncQueueForDocument(id);
    }

    final rows = await _hive.getAllOfflineTravelRequests();
    for (final row in rows) {
      final rid = row['requestId']?.toString() ?? '';
      final tripId = row['tripId']?.toString() ?? row['id']?.toString() ?? '';
      final mongo = row['_id']?.toString() ?? '';
      if (ids.contains(rid) || ids.contains(tripId) || ids.contains(mongo)) {
        if (rid.isNotEmpty) await _hive.deleteTravelRequest(rid);
      }
    }
  }
}

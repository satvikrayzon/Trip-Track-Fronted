import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../database/hive_database.dart';
import '../di/api_registrar.dart';
import '../network/models/api_result.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../modules/travel/data/models/route_point_model.dart';
import '../../modules/travel/data/models/tracking_event_model.dart';
import 'connectivity_service.dart';

/// Offline-to-online sync (REST + Hive).
class SyncService {
  SyncService({
    required ConnectivityService connectivity,
    TravelRequestRemoteDataSource? travelApi,
    HiveDatabase? db,
  })  : _connectivity = connectivity,
        _travelApi = travelApi,
        _db = db ?? HiveDatabase.instance;

  final HiveDatabase _db;
  final ConnectivityService _connectivity;
  final TravelRequestRemoteDataSource? _travelApi;

  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingSyncCount = ValueNotifier<int>(0);
  final ValueNotifier<String> syncStatus = ValueNotifier<String>('Ready');

  Timer? _syncTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isDisposed = false;

  TravelRequestRemoteDataSource _api() =>
      _travelApi ?? travelRequestApiFromHive();

  void init() {
    if (_isDisposed || _connectivitySubscription != null) return;

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((connected) {
      if (_isDisposed) return;
      if (connected) {
        _startAutoSync();
        unawaited(performSync());
      } else {
        _stopAutoSync();
      }
    });

    if (_connectivity.isConnected.value) {
      _startAutoSync();
      unawaited(performSync());
    }

    unawaited(_updatePendingCount());
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncTimer = null;
    _connectivitySubscription = null;
    isSyncing.dispose();
    pendingSyncCount.dispose();
    syncStatus.dispose();
  }

  void _startAutoSync() {
    if (_isDisposed) return;
    _stopAutoSync();
    _syncTimer = Timer.periodic(
      AppConstants.backgroundSyncInterval,
      (_) {
        if (!_isDisposed) unawaited(performSync());
      },
    );
  }

  void _stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<bool> performBackgroundSync() async {
    try {
      if (_isDisposed || !_connectivity.isConnected.value) return false;
      await performSync();
      return !_isDisposed;
    } catch (e) {
      return false;
    }
  }

  Future<void> performSync() async {
    if (_isDisposed || isSyncing.value || !_connectivity.isConnected.value) {
      return;
    }

    isSyncing.value = true;
    syncStatus.value = 'Syncing...';

    try {
      await _syncQueueItems();
      await uploadPendingRoutePoints();
      await uploadPendingTrackingEvents();
      await _syncOfflineImages();

      if (_isDisposed) return;
      syncStatus.value = 'Synced';
      await _updatePendingCount();
    } catch (e) {
      if (!_isDisposed) syncStatus.value = 'Sync Failed';
    } finally {
      if (!_isDisposed) isSyncing.value = false;
    }
  }

  Future<void> _syncQueueItems() async {
    final queueItems = await _db.getSyncQueueItems();

    for (final item in queueItems) {
      try {
        await _processQueueItem(item);
        await _db.removeFromSyncQueue(item['id']);
      } catch (e) {
        final newRetryCount = (item['retryCount'] ?? 0) + 1;
        if (newRetryCount >= AppConstants.maxRetryAttempts) {
          await _db.removeFromSyncQueue(item['id']);
        } else {
          await _db.updateSyncQueueRetry(
            item['id'],
            newRetryCount,
            e.toString(),
          );
        }
      }
    }
  }

  Future<void> _processQueueItem(dynamic item) async {
    if (item is! Map) return;

    final envelope = Map<String, dynamic>.from(item);
    Map<String, dynamic>? payload;

    if (envelope['operation'] != null) {
      payload = envelope;
    } else if (envelope['data'] is Map) {
      payload = Map<String, dynamic>.from(envelope['data'] as Map);
    }

    if (payload == null) return;

    final operation = payload['operation'] as String?;
    final collection = payload['collection'] as String?;
    final documentId = payload['documentId'] as String?;
    final data = payload['data'];

    if (operation == null || collection == null || documentId == null) return;

    if (collection != AppConstants.travelRequestsCollection) return;

    final api = _api();
    final map = Map<String, dynamic>.from(data as Map);

    switch (operation) {
      case 'create':
        final r = await api.create(map);
        if (r case ApiFailure(:final failure)) {
          throw Exception(failure.message);
        }
        break;
      case 'update':
        final r = await api.update(documentId, map);
        if (r case ApiFailure(:final failure)) {
          throw Exception(failure.message);
        }
        break;
      case 'delete':
        final r = await api.delete(documentId);
        if (r case ApiFailure(:final failure)) {
          throw Exception(failure.message);
        }
        break;
    }
  }

  Future<void> uploadPendingRoutePoints() async {
    if (!_connectivity.isConnected.value) return;

    while (true) {
      final batchMaps = await _db.getUnsyncedRoutePoints(
        limit: AppConstants.routePointsUploadBatchSize,
      );
      if (batchMaps.isEmpty) break;

      final api = _api();
      final byRequest = <String, List<Map<String, dynamic>>>{};

      for (final raw in batchMaps) {
        final m = RoutePointModel.fromMap(raw);
        if (m.pointId.isEmpty || m.requestId.isEmpty) continue;
        byRequest.putIfAbsent(m.requestId, () => []).add(m.toApiJson());
      }

      final syncedIds = <String>[];
      var anyFailure = false;
      for (final entry in byRequest.entries) {
        final result = await api.postRoutePointsBatch(entry.key, entry.value);
        if (result.isSuccess) {
          for (final p in entry.value) {
            final id = p['pointId'] as String?;
            if (id != null) syncedIds.add(id);
          }
        } else {
          anyFailure = true;
        }
      }

      if (syncedIds.isNotEmpty) {
        await _db.markRoutePointsSynced(syncedIds);
        await _updatePendingCount();
      }

      if (anyFailure || syncedIds.isEmpty) {
        break;
      }
    }
  }

  Future<void> uploadPendingTrackingEvents() async {
    if (!_connectivity.isConnected.value) return;

    while (true) {
      final batchMaps = await _db.getUnsyncedTrackingEvents(
        limit: AppConstants.trackingEventsUploadBatchSize,
      );
      if (batchMaps.isEmpty) break;

      final api = _api();
      final byRequest = <String, List<Map<String, dynamic>>>{};
      final eventIdsByRequest = <String, List<String>>{};

      for (final raw in batchMaps) {
        final event = TrackingEventModel.fromMap(raw);
        if (event.requestId.isEmpty || event.eventId.isEmpty) continue;
        byRequest.putIfAbsent(event.requestId, () => []).add(event.toApiJson());
        eventIdsByRequest
            .putIfAbsent(event.requestId, () => [])
            .add(event.eventId);
      }

      final syncedIds = <String>[];
      var anyFailure = false;
      for (final entry in byRequest.entries) {
        final result =
            await api.postTrackingEventsBatch(entry.key, entry.value);
        if (result.isSuccess) {
          syncedIds.addAll(eventIdsByRequest[entry.key] ?? const []);
        } else {
          anyFailure = true;
        }
      }

      if (syncedIds.isNotEmpty) {
        await _db.markTrackingEventsSynced(syncedIds);
        await _updatePendingCount();
      }

      if (anyFailure || syncedIds.isEmpty) {
        break;
      }
    }
  }

  Future<void> _syncOfflineImages() async {}

  Future<void> addToSyncQueue({
    required String operation,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _db.addToSyncQueue('$operation:$collection:$documentId', {
      'operation': operation,
      'collection': collection,
      'documentId': documentId,
      'data': data,
    });

    await _updatePendingCount();
    if (_connectivity.isConnected.value && !isSyncing.value) {
      unawaited(performSync());
    }
  }

  Future<void> purgeSyncQueueForDocument(String documentId) async {
    await _db.purgeSyncQueueForDocument(documentId);
    await _updatePendingCount();
  }

  Future<void> _updatePendingCount() async {
    if (_isDisposed) return;
    final stats = await _db.getSyncStatistics();
    if (_isDisposed) return;
    pendingSyncCount.value = stats['pendingSync']! +
        stats['offlineImages']! +
        stats['offlineRequests']! +
        (stats['routePoints'] ?? 0) +
        (stats['trackingEvents'] ?? 0);
  }

  Future<void> forceSync() async {
    if (!_connectivity.isConnected.value) {
      return;
    }
    await performSync();
  }

  Future<Map<String, int>> getSyncStatistics() async {
    return await _db.getSyncStatistics();
  }
}

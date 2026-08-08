import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/database/hive_database.dart';

import '../../../../core/di/service_locator.dart';

import '../../../../core/network/models/api_result.dart';
import '../../../../core/network/failures/network_failure.dart';

import '../../../../core/services/active_trip_restore_service.dart';
import '../../../../core/services/background_location_service.dart';
import '../../../../core/services/punch_reminder_service.dart';
import '../../../../core/services/tracking_session_service.dart';
import '../../../../core/services/trip_road_metrics_service.dart';

import '../../../../core/utils/travel_request_debug_log.dart';
import '../../../../core/utils/app_debug_log.dart';

import '../../../auth/presentation/controllers/app_auth_controller.dart';

import '../../../travel/data/datasources/travel_request_remote_datasource.dart';

import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/services/travel_request_delete_service.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';
import '../../../../features/tracking/data/services/trip_realtime_binder.dart';
import '../../../../core/widgets/trip_route_map_data.dart';

/// User home — server-first list; Hive only for offline fallback and punch merge.

class UserHomeController {
  UserHomeController({
    TravelRequestRemoteDataSource? travelApi,
    AppAuthController? authController,
    HiveDatabase? hive,
  })  : _travelApi = travelApi ?? ServiceLocator.I.get(),
        _authController = authController ?? ServiceLocator.I.get(),
        _hive = hive ?? HiveDatabase.instance;

  static const int _pageSize = 10;

  final TravelRequestRemoteDataSource _travelApi;

  final AppAuthController _authController;

  final HiveDatabase _hive;

  late final ActiveTripRestoreService _activeTripRestore =
      ActiveTripRestoreService(_travelApi, hive: _hive);

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  final ValueNotifier<bool> isRefreshing = ValueNotifier<bool>(false);

  final ValueNotifier<int> totalRequests = ValueNotifier<int>(0);

  final ValueNotifier<int> pendingRequests = ValueNotifier<int>(0);

  final ValueNotifier<int> completedRequests = ValueNotifier<int>(0);

  final ValueNotifier<List<TravelRequestModel>> recentRequests =
      ValueNotifier<List<TravelRequestModel>>([]);

  final ValueNotifier<TravelRequestModel?> activeTrip =
      ValueNotifier<TravelRequestModel?>(null);

  final ValueNotifier<String?> deletingRequestId = ValueNotifier<String?>(null);

  Timer? _pollTimer;
  TripRealtimeBinder? _tripRealtime;

  bool _initialLoadComplete = false;

  void start() {
    unawaited(_load());

    _tripRealtime = TripRealtimeBinder(
      onTripUpdate: updateRequestLocally,
      onTripDelete: deleteTripLocally,
    )..start();

    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_tripRealtime?.isLive == true) return;
      unawaited(_load(silent: true));
    });
  }

  void dispose() {
    _pollTimer?.cancel();
    _tripRealtime?.dispose();
    _tripRealtime = null;

    isLoading.dispose();

    isRefreshing.dispose();

    totalRequests.dispose();

    pendingRequests.dispose();

    completedRequests.dispose();

    recentRequests.dispose();

    activeTrip.dispose();

    deletingRequestId.dispose();
  }

  Future<void> refresh() => _load(silent: false, forceRefresh: true);

  Future<void> _load({bool silent = false, bool forceRefresh = false}) async {
    final userId = _authController.currentUserApiId;

    if (userId == null || userId.isEmpty) {
      if (!_initialLoadComplete) {
        isLoading.value = false;

        _initialLoadComplete = true;
      }

      return;
    }

    final showBlockingSpinner = !_initialLoadComplete && !silent;

    if (showBlockingSpinner) isLoading.value = true;

    try {
      await _authController.ensureSessionReady();

      if (!silent || forceRefresh) {
        await _restoreActiveTripFromCache();
      }

      if (silent) {
        isRefreshing.value = true;
      }

      await _refreshFromApi(userId);
    } catch (e, st) {
    } finally {
      if (showBlockingSpinner) {
        isLoading.value = false;

        _initialLoadComplete = true;
      }

      isRefreshing.value = false;
    }
  }

  /// Only restores in-progress trip banner from Hive — not the recent list.

  Future<void> _restoreActiveTripFromCache() async {
    final cachedActive = await _activeTripRestore.peekFromCache();

    if (cachedActive != null) {
      activeTrip.value = cachedActive;
      _checkAndResumeTracking(cachedActive);
      _syncPunchReminder(cachedActive);
    }
  }

  void _syncPunchReminder(TravelRequestModel? trip) {
    if (!ServiceLocator.I.has<PunchReminderService>()) return;
    final reminders = ServiceLocator.I.get<PunchReminderService>();
    if (trip == null) {
      reminders.clear();
    } else {
      reminders.watch(trip);
    }
  }

  Future<void> _refreshFromApi(String userId) async {
    final listResult = await _travelApi.listTravelRequests(
      page: 1,
      limit: _pageSize,
      mine: true,
    );

    final summaryResult = await _travelApi.getSummary(mine: true);

    if (summaryResult case ApiSuccess(:final data)) {
      totalRequests.value = data.total;

      pendingRequests.value = data.pending;

      completedRequests.value = data.completed;
    }

    switch (listResult) {
      case ApiSuccess(:final data):
        final hiveById = await _hiveIndex(userId);

        final requests = <TravelRequestModel>[];

        for (final m in data.items) {
          var parsed = TravelRequestModel.fromMap(m);

          if (parsed.userId.isEmpty) {
            parsed = parsed.copyWith(userId: userId);
          }

          final merged = _mergeWithCache(parsed, hiveById);

          TravelRequestDebugLog.logParsedComparison(
            source: 'UserHome',
            raw: m,
            parsed: parsed,
            afterMerge: merged,
          );

          requests.add(merged);
        }

        requests.sort((a, b) => b.requestDate.compareTo(a.requestDate));

        // Recompute GPS km + allowance so cards match detail route (not stale API).
        List<TravelRequestModel> enhanced = requests;
        if (ServiceLocator.I.has<TripRoadMetricsService>()) {
          enhanced = await ServiceLocator.I
              .get<TripRoadMetricsService>()
              .enhanceAll(requests.take(10).toList());
          // Keep rest of page unenhanced if list was longer than 10.
          if (requests.length > enhanced.length) {
            enhanced = [...enhanced, ...requests.skip(enhanced.length)];
          }
        }

        if (summaryResult is! ApiSuccess) {
          final pending = data.pending ??
              enhanced.where((r) => r.status != 'Completed').length;

          final completed = data.completed ??
              enhanced.where((r) => r.status == 'Completed').length;

          totalRequests.value = data.total;

          pendingRequests.value = pending;

          completedRequests.value = completed;
        }

        final previousById = <String, TravelRequestModel>{
          for (final r in recentRequests.value)
            if (r.requestId.isNotEmpty) r.requestId: r,
        };
        recentRequests.value = enhanced.take(5).map((item) {
          final prev = previousById[item.requestId];
          if (prev == null) return item;
          return item.mergePreservingLocalProgress(prev);
        }).toList();

        if (enhanced.isNotEmpty) {
          await _syncHiveWithServer(userId, enhanced);
        }

        unawaited(_refreshActiveTripInBackground());

      case ApiFailure(:final failure):
        if (failure.statusCode == 401) {
          await _loadRecentFromHiveFallback(userId);
          await _authController.onApiUnauthorized();
          return;
        }
        if (failure.isTransientNetworkError) {
          await _loadRecentFromHiveFallback(userId);
          return;
        }
        if (recentRequests.value.isEmpty) {
          await _loadRecentFromHiveFallback(userId);
        }
    }
  }

  Future<void> _syncHiveWithServer(
    String userId,
    List<TravelRequestModel> serverItems,
  ) async {
    final keepIds = <String>{};

    for (final request in serverItems) {
      final id = request.requestId;

      if (id.isEmpty) continue;

      keepIds.add(id);

      final data = request
          .copyWith(userId: request.userId.isEmpty ? userId : request.userId)
          .toMap();

      await _hive.saveTravelRequest(data);

      await _hive.updateTravelRequest(id, {
        'isSynced': true,
        'userId': userId,
        'lastSyncAt': DateTime.now().toIso8601String(),
      });
    }

    await _hive.pruneOfflineTravelRequestsForUser(userId, keepIds);
  }

  Future<void> _loadRecentFromHiveFallback(String userId) async {
    final rows = await _hive.getOfflineTravelRequestsForUser(userId);

    final requests = rows
        .map((r) => TravelRequestModel.fromMap(Map<String, dynamic>.from(r)))
        .map((r) => r.ensureTripLegs())
        .toList()
      ..sort((a, b) => b.requestDate.compareTo(a.requestDate));

    _applyRequestStats(requests, total: requests.length);

    recentRequests.value = requests.take(5).toList();
  }

  Future<void> _refreshActiveTripInBackground() async {
    final restored = await _activeTripRestore.refreshInBackground();

    if (restored == null) {
      if (activeTrip.value != null) activeTrip.value = null;
      _syncPunchReminder(null);
      return;
    }

    activeTrip.value = restored;
    _checkAndResumeTracking(restored);
    _syncPunchReminder(restored);

    final list = List<TravelRequestModel>.from(recentRequests.value);

    final index = list.indexWhere((r) => r.requestId == restored.requestId);

    if (index != -1) {
      list[index] = restored.mergePreservingLocalProgress(list[index]);
      recentRequests.value = list;
    }
  }

  void _checkAndResumeTracking(TravelRequestModel trip) {
    final isTrackingActive =
        (trip.status == 'Travelling' || trip.status == 'Returning') ||
            trip.trackingStatus == 'tracking';
    if (isTrackingActive) {
      final bg = ServiceLocator.I.get<BackgroundLocationService>();
      if (!bg.isRunning) {
        final session = ServiceLocator.I.get<TrackingSessionService>();
        unawaited(session.onTravelDeparture(
          requestId: trip.requestId,
          legId: trip.activeLeg?.legId ?? '',
          sessionId: trip.trackingSessionId ?? '',
        ));
      }
    }
  }

  Future<Map<String, TravelRequestModel>> _hiveIndex(String userId) async {
    final rows = await _hive.getOfflineTravelRequestsForUser(userId);

    final index = <String, TravelRequestModel>{};

    for (final row in rows) {
      final model = TravelRequestModel.fromMap(Map<String, dynamic>.from(row))
          .ensureTripLegs();

      if (model.requestId.isNotEmpty) index[model.requestId] = model;

      final mongo = model.mongoDocumentId;

      if (mongo != null && mongo.isNotEmpty) index[mongo] = model;
    }

    return index;
  }

  TravelRequestModel _mergeWithCache(
    TravelRequestModel remote,
    Map<String, TravelRequestModel> hiveById,
  ) {
    final cached = hiveById[remote.requestId] ??
        (remote.mongoDocumentId != null
            ? hiveById[remote.mongoDocumentId]
            : null);

    if (cached == null) return remote.ensureTripLegs();

    return remote.mergePreservingLocalProgress(cached).ensureTripLegs();
  }

  void _applyRequestStats(
    List<TravelRequestModel> requests, {
    required int total,
  }) {
    totalRequests.value = total;

    pendingRequests.value =
        requests.where((r) => r.status != 'Completed').length;

    completedRequests.value =
        requests.where((r) => r.status == 'Completed').length;
  }

  void updateRequestLocally(TravelRequestModel updatedRequest) {
    if (updatedRequest.userId != _authController.currentUserApiId) return;

    if (activeTrip.value?.requestId == updatedRequest.requestId) {
      final mergedActive =
          updatedRequest.mergePreservingLocalProgress(activeTrip.value!);
      if (mergedActive.status == 'Completed' &&
          !mergedActive.needsReturnArrivalPunch) {
        activeTrip.value = null;
        _syncPunchReminder(null);
      } else {
        activeTrip.value = mergedActive;
        _syncPunchReminder(mergedActive);
      }
    } else if (updatedRequest.status != 'Completed' &&
        updatedRequest.status != 'Cancelled' &&
        (activeTrip.value == null ||
            activeTrip.value!.requestId == updatedRequest.requestId)) {
      final status = updatedRequest.status;
      if (status == 'Travelling' ||
          status == 'Returning' ||
          status == 'In Meeting' ||
          status == 'At Client' ||
          status == 'Ready To Start' ||
          status == 'Ready For Next' ||
          status == 'Ready To Return') {
        final seed = activeTrip.value;
        final mergedActive = seed != null
            ? updatedRequest.mergePreservingLocalProgress(seed)
            : updatedRequest;
        activeTrip.value = mergedActive;
        _syncPunchReminder(mergedActive);
      }
    }

    final list = List<TravelRequestModel>.from(recentRequests.value);

    final index = list.indexWhere(
      (r) =>
          tripMatchesRealtimeKey(r, updatedRequest.requestId) ||
          tripMatchesRealtimeKey(r, updatedRequest.restResourceId) ||
          (updatedRequest.tripId.isNotEmpty &&
              tripMatchesRealtimeKey(r, updatedRequest.tripId)),
    );

    if (index != -1) {
      final oldRequest = list[index];
      // Merge so partial WS / details payloads don't wipe card fields
      // (fuel, meetings, duration, vehicle, allowance, etc.).
      final merged =
          updatedRequest.mergePreservingLocalProgress(oldRequest);
      list[index] = merged;
      recentRequests.value = list;

      if (oldRequest.status != merged.status) {
        if (oldRequest.status == 'Completed') {
          completedRequests.value =
              (completedRequests.value - 1).clamp(0, 999999);
        } else {
          pendingRequests.value = (pendingRequests.value - 1).clamp(0, 999999);
        }

        if (merged.status == 'Completed') {
          completedRequests.value++;
        } else {
          pendingRequests.value++;
        }
      }
    } else {
      list.insert(0, updatedRequest);
      list.sort((a, b) => b.requestDate.compareTo(a.requestDate));
      recentRequests.value = list.take(5).toList();

      totalRequests.value++;
      if (updatedRequest.status == 'Completed') {
        completedRequests.value++;
      } else {
        pendingRequests.value++;
      }
    }
  }

  void deleteTripLocally(String id) {
    evictRoutePointsCache(id);
    final list = List<TravelRequestModel>.from(recentRequests.value);
    final index = list.indexWhere(
      (r) => r.requestId == id || r.restResourceId == id,
    );
    if (index != -1) {
      final removed = list.removeAt(index);
      recentRequests.value = list;

      totalRequests.value = (totalRequests.value - 1).clamp(0, 999999);
      if (removed.status == 'Completed') {
        completedRequests.value =
            (completedRequests.value - 1).clamp(0, 999999);
      } else {
        pendingRequests.value = (pendingRequests.value - 1).clamp(0, 999999);
      }

      if (activeTrip.value?.requestId == id ||
          activeTrip.value?.restResourceId == id) {
        activeTrip.value = null;
      }
    }
  }

  Future<bool> deleteTravelRequest(TravelRequestModel request) async {
    final apiId = request.restResourceId;
    if (apiId.isEmpty) return false;

    deletingRequestId.value = apiId;
    try {
      final deleted = await TravelRequestDeleteService(
        travelApi: _travelApi,
        hive: _hive,
        activeTripRestore: _activeTripRestore,
      ).delete(request);
      if (!deleted) return false;

      evictRoutePointsCache(request.requestId);
      evictRoutePointsCache(apiId);

      final list = List<TravelRequestModel>.from(recentRequests.value);
      list.removeWhere(
        (r) =>
            travelRequestMatchesId(r, request.requestId) ||
            travelRequestMatchesId(r, apiId),
      );
      recentRequests.value = list;

      if (activeTrip.value != null &&
          (travelRequestMatchesId(activeTrip.value!, request.requestId) ||
              travelRequestMatchesId(activeTrip.value!, apiId))) {
        activeTrip.value = null;
      }

      totalRequests.value = (totalRequests.value - 1).clamp(0, 999999);
      if (request.status != 'Completed') {
        pendingRequests.value = (pendingRequests.value - 1).clamp(0, 999999);
      } else {
        completedRequests.value =
            (completedRequests.value - 1).clamp(0, 999999);
      }

      return true;
    } on NetworkFailure {
      rethrow;
    } finally {
      deletingRequestId.value = null;
    }
  }
}

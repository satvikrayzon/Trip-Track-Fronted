import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/database/hive_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../../core/services/trip_road_metrics_service.dart';
import '../../../../core/utils/app_debug_log.dart';
import '../../../../features/tracking/data/services/trip_realtime_binder.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';
import '../../../travel/data/datasources/travel_request_remote_datasource.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/services/travel_request_delete_service.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';

class UserRequestsController {
  UserRequestsController({
    TravelRequestRemoteDataSource? travelApi,
    AppAuthController? authController,
  })  : _travelApi = travelApi ?? ServiceLocator.I.get(),
        _authController = authController ?? ServiceLocator.I.get();

  static const int pageSize = 10;

  final TravelRequestRemoteDataSource _travelApi;
  final AppAuthController _authController;
  final HiveDatabase _hiveDb = HiveDatabase.instance;

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLoadingMore = ValueNotifier<bool>(false);
  final ValueNotifier<bool> hasMore = ValueNotifier<bool>(true);
  final ValueNotifier<List<TravelRequestModel>> requests =
      ValueNotifier<List<TravelRequestModel>>([]);
  final ValueNotifier<String> filterStatus = ValueNotifier<String>('all');

  final ValueNotifier<String?> deletingRequestId = ValueNotifier<String?>(null);

  List<TravelRequestModel> _allMine = [];
  String _searchQuery = '';
  int _page = 1;
  TripRealtimeBinder? _tripRealtime;

  void start() {
    unawaited(loadRequests());
    _tripRealtime = TripRealtimeBinder(
      onTripUpdate: applyTripUpdate,
      onTripDelete: deleteTripLocally,
    )..start();
  }

  void dispose() {
    _tripRealtime?.dispose();
    _tripRealtime = null;
    isLoading.dispose();
    isLoadingMore.dispose();
    hasMore.dispose();
    requests.dispose();
    filterStatus.dispose();
    deletingRequestId.dispose();
  }

  void applyTripUpdate(TravelRequestModel updatedRequest) {
    final userId = _authController.currentUserApiId;
    if (userId != null &&
        userId.isNotEmpty &&
        updatedRequest.userId.isNotEmpty &&
        updatedRequest.userId != userId) {
      return;
    }

    final index = _allMine.indexWhere(
      (r) =>
          tripMatchesRealtimeKey(r, updatedRequest.requestId) ||
          tripMatchesRealtimeKey(r, updatedRequest.restResourceId) ||
          (updatedRequest.tripId.isNotEmpty &&
              tripMatchesRealtimeKey(r, updatedRequest.tripId)),
    );
    if (index == -1) {
      _allMine.insert(0, updatedRequest.ensureTripLegs());
      _allMine.sort((a, b) => b.requestDate.compareTo(a.requestDate));
    } else {
      final old = _allMine[index];
      _allMine[index] =
          updatedRequest.mergePreservingLocalProgress(old).ensureTripLegs();
    }
    _applyFilters();
  }

  void deleteTripLocally(String id) {
    _allMine.removeWhere(
      (r) => r.requestId == id || r.restResourceId == id || r.tripId == id,
    );
    _applyFilters();
  }

  Future<void> loadRequests({bool reset = true}) async {
    final userId = _authController.currentUserApiId;
    if (userId == null || userId.isEmpty) return;

    if (reset) {
      _page = 1;
      hasMore.value = true;
      isLoading.value = true;
    }

    try {
      final result = await _travelApi.listTravelRequests(
        page: _page,
        limit: pageSize,
        mine: true,
      );

      switch (result) {
        case ApiSuccess(:final data):
          final hiveById = await _hiveIndexForUser(userId);
          final pageItems = data.items.map((m) {
            var parsed = TravelRequestModel.fromMap(m);
            if (parsed.userId.isEmpty) {
              parsed = parsed.copyWith(userId: userId);
            }
            return _mergeWithCache(parsed, hiveById);
          }).toList();

          if (reset) {
            final previousById = <String, TravelRequestModel>{
              for (final r in _allMine)
                if (r.requestId.isNotEmpty) r.requestId: r,
            };
            _allMine = pageItems.map((item) {
              final prev = previousById[item.requestId];
              if (prev == null) return item;
              return item.mergePreservingLocalProgress(prev).ensureTripLegs();
            }).toList();
            if (_allMine.isNotEmpty) {
              await _syncHiveWithServer(userId, _allMine);
            }
          } else {
            final seen = _allMine.map((r) => r.requestId).toSet();
            final previousById = <String, TravelRequestModel>{
              for (final r in _allMine)
                if (r.requestId.isNotEmpty) r.requestId: r,
            };
            for (final item in pageItems) {
              if (seen.contains(item.requestId)) {
                final idx =
                    _allMine.indexWhere((r) => r.requestId == item.requestId);
                if (idx != -1) {
                  _allMine[idx] =
                      item.mergePreservingLocalProgress(_allMine[idx]);
                }
                continue;
              }
              final prev = previousById[item.requestId];
              _allMine.add(
                prev == null
                    ? item
                    : item.mergePreservingLocalProgress(prev),
              );
            }
          }

          _allMine.sort((a, b) => b.requestDate.compareTo(a.requestDate));

          hasMore.value = data.hasMore;
          if (data.hasMore) _page++;
          // Paint list first — enhance missing km in background (no Snap-all).
          _applyFilters();

          if (ServiceLocator.I.has<TripRoadMetricsService>()) {
            unawaited(() async {
              try {
                final enhanced = await ServiceLocator.I
                    .get<TripRoadMetricsService>()
                    .enhanceAll(
                      _allMine,
                      persist: true,
                      syncFromTrack: false,
                    );
                _allMine = enhanced;
                if (reset && _allMine.isNotEmpty) {
                  await _syncHiveWithServer(userId, _allMine);
                }
                _applyFilters();
              } catch (_) {}
            }());
          }
        case ApiFailure(:final failure):
          if (reset && _allMine.isEmpty) {
            _allMine = _modelsFromHive(await _hiveIndexForUser(userId));
            _applyFilters();
          }
      }
    } catch (e, st) {
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || isLoading.value) return;
    isLoadingMore.value = true;
    try {
      await loadRequests(reset: false);
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<Map<String, TravelRequestModel>> _hiveIndexForUser(
    String userId,
  ) async {
    final rows = await _hiveDb.getOfflineTravelRequestsForUser(userId);
    final index = <String, TravelRequestModel>{};
    for (final row in rows) {
      final model =
          TravelRequestModel.fromMap(Map<String, dynamic>.from(row)).ensureTripLegs();
      _indexTrip(model, index);
    }
    return index;
  }

  void _indexTrip(
    TravelRequestModel model,
    Map<String, TravelRequestModel> index,
  ) {
    void put(String? key) {
      if (key == null || key.isEmpty) return;
      index[key] = model;
    }

    put(model.requestId);
    put(model.mongoDocumentId);
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

  List<TravelRequestModel> _modelsFromHive(
    Map<String, TravelRequestModel> hiveById,
  ) {
    final seen = <String>{};
    final list = <TravelRequestModel>[];
    for (final model in hiveById.values) {
      final key = model.requestId.isNotEmpty
          ? model.requestId
          : model.mongoDocumentId ?? '';
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      list.add(model);
    }
    list.sort((a, b) => b.requestDate.compareTo(a.requestDate));
    return list;
  }

  void searchRequests(String query) {
    _searchQuery = query.toLowerCase();
    _applyFilters();
  }

  void filterByStatus(String status) {
    filterStatus.value = status;
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = List<TravelRequestModel>.from(_allMine);

    if (filterStatus.value != 'all') {
      filtered =
          filtered.where((r) => r.status == filterStatus.value).toList();
    }

    final q = _searchQuery;
    if (q.isNotEmpty) {
      filtered = filtered.where((request) {
        final matchesLeg = request.tripLegs.any((leg) {
          return leg.clientName.toLowerCase().contains(q) ||
              leg.purpose.toLowerCase().contains(q) ||
              leg.toLocation.toLowerCase().contains(q);
        });
        return request.userName.toLowerCase().contains(q) ||
            request.clientName.toLowerCase().contains(q) ||
            request.fromLocation.toLowerCase().contains(q) ||
            request.toLocation.toLowerCase().contains(q) ||
            matchesLeg;
      }).toList();
    }

    requests.value = filtered;
  }

  Future<void> refresh() => loadRequests(reset: true);

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
      await _hiveDb.saveTravelRequest(data);
      await _hiveDb.updateTravelRequest(id, {
        'isSynced': true,
        'userId': userId,
        'lastSyncAt': DateTime.now().toIso8601String(),
      });
    }
    await _hiveDb.pruneOfflineTravelRequestsForUser(userId, keepIds);
  }

  Future<bool> deleteTravelRequest(TravelRequestModel request) async {
    final apiId = request.restResourceId;
    if (apiId.isEmpty) return false;

    deletingRequestId.value = apiId;
    try {
      final deleted = await TravelRequestDeleteService(
        travelApi: _travelApi,
        hive: _hiveDb,
      ).delete(request);
      if (!deleted) return false;

      _allMine.removeWhere(
        (r) => travelRequestMatchesId(r, request.requestId) ||
            travelRequestMatchesId(r, apiId),
      );
      _applyFilters();
      return true;
    } on NetworkFailure {
      rethrow;
    } finally {
      deletingRequestId.value = null;
    }
  }
}

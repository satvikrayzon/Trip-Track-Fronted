import 'dart:async';

import 'dart:io';
import 'package:flutter/foundation.dart';



import '../../../../core/app_messenger.dart';

import '../../../../core/di/service_locator.dart';

import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/network/models/api_result.dart';

import '../../../../core/theme/app_colors.dart';

import '../../../auth/data/datasources/users_remote_datasource.dart';

import '../../../travel/data/datasources/travel_request_remote_datasource.dart';

import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/services/travel_request_delete_service.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';
import '../../../../features/tracking/data/services/trip_realtime_binder.dart';
import '../../../../core/widgets/trip_route_map_data.dart';



class AdminTravelRequestsController {

  AdminTravelRequestsController({
    TravelRequestRemoteDataSource? travelApi,
    UsersRemoteDataSource? usersApi,
  })  : _travelApi = travelApi ?? ServiceLocator.I.get(),
        _usersApi = usersApi ?? ServiceLocator.I.get();



  final TravelRequestRemoteDataSource _travelApi;

  final UsersRemoteDataSource _usersApi;



  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  final ValueNotifier<List<TravelRequestModel>> requests =

      ValueNotifier<List<TravelRequestModel>>([]);

  final ValueNotifier<String> searchQuery = ValueNotifier<String>('');

  final ValueNotifier<String> filterStatus = ValueNotifier<String>('all');
  final ValueNotifier<String?> deletingRequestId = ValueNotifier<String?>(null);
  
  final ValueNotifier<DateTime?> startDate = ValueNotifier<DateTime?>(null);
  final ValueNotifier<DateTime?> endDate = ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> selectedUserId = ValueNotifier<String?>(null);

  List<TravelRequestModel> _allRequests = [];

  Timer? _pollTimer;
  TripRealtimeBinder? _tripRealtime;

  void start() {
    loadRequests();
    _tripRealtime = TripRealtimeBinder(
      onTripUpdate: applyTripUpdate,
      onTripRefetch: (id) => unawaited(_refetchTripById(id)),
      onTripDelete: deleteTripLocally,
    )..start();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_tripRealtime?.isLive == true) return;
      unawaited(loadRequests(silent: true));
    });
  }

  void dispose() {
    _pollTimer?.cancel();
    _tripRealtime?.dispose();
    _tripRealtime = null;
    isLoading.dispose();

    requests.dispose();

    searchQuery.dispose();
    filterStatus.dispose();
    deletingRequestId.dispose();
    startDate.dispose();
    endDate.dispose();
    selectedUserId.dispose();
  }



  Future<void> loadRequests({bool silent = false}) async {

    try {

      if (!silent) {
        isLoading.value = true;
      }



      final fetchedItems = <TravelRequestModel>[];
      int page = 1;
      bool hasMore = true;

      while (hasMore) {
        final result = await _travelApi.listTravelRequests(
          page: page,
          limit: 50,
          mine: false,
        );

        switch (result) {
          case ApiSuccess(:final data):
            for (final m in data.items) {
              try {
                final req = TravelRequestModel.fromMap(m);
                fetchedItems.add(req);
              } catch (e) {
              }
            }
            if (data.items.length < 50 || !data.hasMore) {
              hasMore = false;
            } else {
              page++;
            }
          case ApiFailure():
            hasMore = false;
        }
      }


      if (fetchedItems.isNotEmpty) {
        _allRequests = fetchedItems;
        _allRequests.sort((a, b) => b.requestDate.compareTo(a.requestDate));

          // `/travel-requests` may omit `user.name` / `user.employeeCode` for
          // some backend versions. Enrich from `/users` so the admin/manager UI
          // can always show identity fields.
          try {
            final usersRes = await _usersApi.listUsers();
            switch (usersRes) {
              case ApiSuccess(:final data):
                final userByUid = {for (final u in data) u.uid: u};
                _allRequests = _allRequests.map((r) {
                  final u = userByUid[r.userId];
                  if (u == null) return r;
                  final nameMissing = r.userName.trim().isEmpty;
                  final codeMissing = (r.employeeCode ?? '').trim().isEmpty;
                  if (!nameMissing && !codeMissing) return r;
                  return r.copyWith(
                    userName: nameMissing ? u.name : r.userName,
                    employeeCode: codeMissing ? u.employeeCode : r.employeeCode,
                  );
                }).toList();
              case ApiFailure():
            }
          } catch (e, st) {
          }

        _applyFilters();
      } else {
        _allRequests = [];
        requests.value = [];
      }

    } catch (e, st) {
      // Do not clear _allRequests completely on unexpected errors if we already fetched them!
      // But if it failed BEFORE fetching, we must show empty.
      if (_allRequests.isEmpty) {
        requests.value = [];
      }
    } finally {

      if (!silent) {
        isLoading.value = false;
      }

    }

  }



  void searchRequests(String query) {

    searchQuery.value = query.toLowerCase();

    _applyFilters();

  }



  void filterByStatus(String status) {
    filterStatus.value = status;
    _applyFilters();
  }

  void setDateRange(DateTime? start, DateTime? end) {
    startDate.value = start;
    endDate.value = end;
    _applyFilters();
  }

  void setSelectedUser(String? userId) {
    selectedUserId.value = userId;
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = List<TravelRequestModel>.from(_allRequests);

    if (selectedUserId.value != null) {
      filtered = filtered.where((req) => req.userId == selectedUserId.value).toList();
    }

    if (startDate.value != null) {
      final start = startDate.value!;
      final s = DateTime(start.year, start.month, start.day);
      filtered = filtered.where((req) {
        final rd = req.requestDate.toLocal();
        return !DateTime(rd.year, rd.month, rd.day).isBefore(s);
      }).toList();
    }

    if (endDate.value != null) {
      final end = endDate.value!;
      final e = DateTime(end.year, end.month, end.day);
      filtered = filtered.where((req) {
        final rd = req.requestDate.toLocal();
        return !DateTime(rd.year, rd.month, rd.day).isAfter(e);
      }).toList();
    }

    if (filterStatus.value != 'all') {
      filtered = filtered
          .where((request) => request.status == filterStatus.value)
          .toList();
    }

    if (searchQuery.value.isNotEmpty) {
      final q = searchQuery.value.toLowerCase();
      filtered = filtered.where((request) {
        final matchesLeg = request.tripLegs.any((leg) {
          return leg.clientName.toLowerCase().contains(q) ||
              (leg.purpose ?? '').toLowerCase().contains(q) ||
              leg.fromLocation.toLowerCase().contains(q) ||
              leg.toLocation.toLowerCase().contains(q);
        });

        return request.userName.toLowerCase().contains(q) ||
            (request.employeeCode?.toLowerCase().contains(q) ?? false) ||
            request.clientName.toLowerCase().contains(q) ||
            request.fromLocation.toLowerCase().contains(q) ||
            request.toLocation.toLowerCase().contains(q) ||
            matchesLeg;
      }).toList();
    }



    requests.value = filtered;

  }



  Future<void> refresh() => loadRequests();



  void applyTripUpdate(TravelRequestModel updatedRequest) {
    final index = _allRequests.indexWhere(
      (r) =>
          tripMatchesRealtimeKey(r, updatedRequest.requestId) ||
          tripMatchesRealtimeKey(r, updatedRequest.restResourceId) ||
          (updatedRequest.tripId.isNotEmpty &&
              tripMatchesRealtimeKey(r, updatedRequest.tripId)),
    );
    if (index == -1) {
      _allRequests.insert(0, updatedRequest);
      _allRequests.sort((a, b) => b.requestDate.compareTo(a.requestDate));
    } else {
      _allRequests[index] = updatedRequest;
    }
    _applyFilters();
  }

  void deleteTripLocally(String id) {
    evictRoutePointsCache(id);
    _allRequests.removeWhere((r) => r.requestId == id || r.restResourceId == id);
    _applyFilters();
  }

  Future<void> _refetchTripById(String id) async {
    if (id.isEmpty) return;
    final result = await _travelApi.getById(id);
    switch (result) {
      case ApiSuccess(:final data):
        applyTripUpdate(TravelRequestModel.fromMap(data).ensureTripLegs());
      case ApiFailure():
        break;
    }
  }



  Future<bool> deleteRequest(TravelRequestModel request) async {
    final apiId = request.restResourceId;
    if (apiId.isEmpty) return false;

    deletingRequestId.value = apiId;
    try {
      final deleted =
          await TravelRequestDeleteService(travelApi: _travelApi).delete(request);
      if (!deleted) return false;

      evictRoutePointsCache(request.requestId);
      evictRoutePointsCache(apiId);

      _allRequests.removeWhere(
        (r) => travelRequestMatchesId(r, request.requestId) ||
            travelRequestMatchesId(r, apiId),
      );
      _applyFilters();

      showAppSnackBar(
        title: 'Deleted',
        message: 'Travel request deleted',
        backgroundColor: AppColors.success,
      );
      return true;
    } on NetworkFailure catch (failure) {
      showAppSnackBar(
        title: 'Error',
        message: deleteTravelRequestUserMessage(failure),
        backgroundColor: AppColors.error,
      );
      return false;
    } catch (e) {
      showAppSnackBar(
        title: 'Error',
        message: 'Unable to delete travel request',
        backgroundColor: AppColors.error,
      );
      return false;
    } finally {
      deletingRequestId.value = null;
    }
  }

}



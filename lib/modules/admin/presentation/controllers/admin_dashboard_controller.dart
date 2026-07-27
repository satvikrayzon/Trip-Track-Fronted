import 'dart:async';



import 'package:flutter/foundation.dart';



import '../../../../core/di/service_locator.dart';

import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/network/models/api_result.dart';

import '../../../auth/data/datasources/users_remote_datasource.dart';

import '../../../auth/data/models/user_model.dart';

import '../../../auth/presentation/controllers/app_auth_controller.dart';

import '../../../travel/data/datasources/travel_request_remote_datasource.dart';

import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/services/travel_request_delete_service.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';
import '../../../../features/tracking/data/services/trip_realtime_binder.dart';



/// Admin dashboard — polls REST API for recent data.

///

/// Background polls do not toggle [isLoading] (avoids dashboard blink).

class AdminDashboardController {

  AdminDashboardController({

    TravelRequestRemoteDataSource? travelApi,

    UsersRemoteDataSource? usersApi,

    AppAuthController? authController,

  })  : _travelApi = travelApi ?? ServiceLocator.I.get(),

        _usersApi = usersApi ?? ServiceLocator.I.get(),

        _authController = authController ?? ServiceLocator.I.get();



  final TravelRequestRemoteDataSource _travelApi;

  final UsersRemoteDataSource _usersApi;

  final AppAuthController _authController;



  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  final ValueNotifier<int> totalUsers = ValueNotifier<int>(0);

  final ValueNotifier<int> totalRequests = ValueNotifier<int>(0);

  final ValueNotifier<int> pendingRequests = ValueNotifier<int>(0);

  final ValueNotifier<int> completedRequests = ValueNotifier<int>(0);

  final ValueNotifier<List<TravelRequestModel>> recentRequests =

      ValueNotifier<List<TravelRequestModel>>([]);

  final ValueNotifier<List<UserModel>> recentUsers =

      ValueNotifier<List<UserModel>>([]);

  final ValueNotifier<String?> deletingRequestId = ValueNotifier<String?>(null);



  Timer? _pollTimer;
  TripRealtimeBinder? _tripRealtime;

  bool _initialLoadComplete = false;

  String? _lastSnapshot;



  void start() {

    unawaited(_startAfterSessionReady());

    _tripRealtime = TripRealtimeBinder(
      onTripUpdate: updateRequestLocally,
      onTripRefetch: (id) => unawaited(_refetchTripById(id)),
    )..start();

    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {

      if (!_authController.isHodOrAdmin) return;
      if (_tripRealtime?.isLive == true) return;

      unawaited(_refresh());

    });

  }



  void dispose() {

    _pollTimer?.cancel();
    _tripRealtime?.dispose();
    _tripRealtime = null;

    isLoading.dispose();

    totalUsers.dispose();

    totalRequests.dispose();

    pendingRequests.dispose();

    completedRequests.dispose();

    recentRequests.dispose();

    recentUsers.dispose();

    deletingRequestId.dispose();

  }



  Future<void> _startAfterSessionReady() async {

    await _authController.ensureSessionReady();

    if (!_authController.isHodOrAdmin) return;

    await _refresh();

  }



  String _snapshot(

    List<UserModel> users,

    List<TravelRequestModel> requests,

    int pending,

    int completed,

  ) {

    final u = users.take(5).map((e) => '${e.uid}:${e.name}').join(',');

    final r =

        requests.take(5).map((e) => '${e.requestId}:${e.status}').join(',');

    return '${users.length}|$u|${requests.length}|$pending|$completed|$r';

  }



  Future<void> _refresh() async {

    if (!_authController.isAdmin) return;

    final showBlockingSpinner = !_initialLoadComplete;

    if (showBlockingSpinner) {

      isLoading.value = true;

    }



    try {

      List<UserModel> users = [];

      List<TravelRequestModel> requests = [];



      final usersRes = await _usersApi.listUsers();

      switch (usersRes) {

        case ApiSuccess(:final data):

          users = data;

          users.sort((a, b) => a.name.compareTo(b.name));

        case ApiFailure():

          break;

      }



      final reqRes = await _travelApi.listTravelRequests(
        page: 1,
        limit: 20,
        mine: false,
      );

      switch (reqRes) {

        case ApiSuccess(:final data):

          requests = data.items

              .map((m) => TravelRequestModel.fromMap(m))

              .toList();

          requests.sort((a, b) => b.requestDate.compareTo(a.requestDate));

        case ApiFailure():

          break;

      }



      // `/travel-requests` may omit `user.name` / `user.employeeCode` on some
      // backend versions. We already fetched the full user list above, so
      // enrich missing identity fields from it to keep admin UI correct.
      if (users.isNotEmpty && requests.isNotEmpty) {
        final userByUid = {for (final u in users) u.uid: u};
        requests = requests.map((r) {
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
      }

      final pending =

          requests.where((r) => r.status != 'Completed').length;

      final completed =

          requests.where((r) => r.status == 'Completed').length;

      final snap = _snapshot(users, requests, pending, completed);

      if (snap != _lastSnapshot) {

        _lastSnapshot = snap;

        totalUsers.value = users.length;

        recentUsers.value = users.take(5).toList();

        recentRequests.value = requests.take(5).toList();

        totalRequests.value = requests.length;

        pendingRequests.value = pending;

        completedRequests.value = completed;

      }

    } catch (e) {


    } finally {

      if (showBlockingSpinner) {

        isLoading.value = false;

        _initialLoadComplete = true;

      }

    }

  }



  Future<void> refresh() => _refresh();



  void updateRequestLocally(TravelRequestModel updatedRequest) {

    final list = List<TravelRequestModel>.from(recentRequests.value);

    final index = list.indexWhere(
      (r) =>
          tripMatchesRealtimeKey(r, updatedRequest.requestId) ||
          tripMatchesRealtimeKey(r, updatedRequest.restResourceId) ||
          (updatedRequest.tripId.isNotEmpty &&
              tripMatchesRealtimeKey(r, updatedRequest.tripId)),
    );

    if (index != -1) {

      list[index] = updatedRequest;

      recentRequests.value = list;

      pendingRequests.value =

          list.where((r) => r.status != 'Completed').length;

      completedRequests.value =

          list.where((r) => r.status == 'Completed').length;

      _lastSnapshot = null;

    }

  }

  Future<void> _refetchTripById(String id) async {
    if (id.isEmpty) return;
    final result = await _travelApi.getById(id);
    switch (result) {
      case ApiSuccess(:final data):
        updateRequestLocally(
          TravelRequestModel.fromMap(data).ensureTripLegs(),
        );
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

      final list = List<TravelRequestModel>.from(recentRequests.value);
      list.removeWhere(
        (r) => travelRequestMatchesId(r, request.requestId) ||
            travelRequestMatchesId(r, apiId),
      );
      recentRequests.value = list;
      totalRequests.value = list.length;
      pendingRequests.value =
          list.where((r) => r.status != 'Completed').length;
      completedRequests.value =
          list.where((r) => r.status == 'Completed').length;
      _lastSnapshot = null;

      return true;
    } on NetworkFailure {
      rethrow;
    } catch (_) {
      return false;
    } finally {
      deletingRequestId.value = null;
    }
  }

}



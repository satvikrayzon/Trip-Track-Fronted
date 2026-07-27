import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../tracking/domain/entities/employee_tracking_status.dart';
import '../../../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../../../modules/travel/data/models/travel_request_model.dart';
import '../../data/live_map_location_resolver.dart';

class LiveMapState {
  const LiveMapState({
    this.isLoading = true,
    this.isConnected = false,
    this.liveViaSocket = false,
    this.employees = const [],
    this.teams = const [],
    this.lastRefreshError,
  });

  final bool isLoading;
  final bool isConnected;

  /// True when positions are driven by WebSocket (not HTTP polling).
  final bool liveViaSocket;
  final List<TrackedEmployee> employees;
  final List<String> teams;
  final String? lastRefreshError;

  LiveMapState copyWith({
    bool? isLoading,
    bool? isConnected,
    bool? liveViaSocket,
    List<TrackedEmployee>? employees,
    List<String>? teams,
    String? lastRefreshError,
  }) {
    return LiveMapState(
      isLoading: isLoading ?? this.isLoading,
      isConnected: isConnected ?? this.isConnected,
      liveViaSocket: liveViaSocket ?? this.liveViaSocket,
      employees: employees ?? this.employees,
      teams: teams ?? this.teams,
      lastRefreshError: lastRefreshError,
    );
  }
}

class LiveMapNotifier extends StateNotifier<LiveMapState> {
  LiveMapNotifier(this._ref) : super(const LiveMapState());

  final Ref _ref;
  StreamSubscription<List<TrackedEmployee>>? _sub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Map<String, dynamic>>? _locSub;
  Timer? _fallbackPollTimer;

  final Map<String, TrackedEmployee> _roster = {};
  bool _started = false;
  DateTime? _lastSocketLocationAt;

  static const _socketFreshness = Duration(seconds: 45);
  static const _socketMetadataSync = Duration(minutes: 2);
  static const _httpFallbackPoll = Duration(seconds: 60);

  Future<void> start() async {
    if (_started || !mounted) return;
    _started = true;

    final ws = _ref.read(webSocketTrackingProvider);

    _connSub = ws.connectionStream.listen((connected) {
      if (!mounted) return;
      state = state.copyWith(isConnected: connected);
      if (!connected) {
        state = state.copyWith(liveViaSocket: false);
      }
      _syncFallbackPolling();
    });

    _sub = ws.employeesStream.listen((employees) {
      if (!mounted || employees.isEmpty) return;
      _lastSocketLocationAt = DateTime.now();
      for (final e in employees) {
        final prev = _roster[e.id];
        _roster[e.id] = prev == null ? e : _mergeProfile(prev, e);
      }
      _applyEmployees(liveViaSocket: true);
    });

    _locSub = ws.locationUpdates.listen((data) {
      if (!mounted) return;
      _lastSocketLocationAt = DateTime.now();

      final userId = data['userId']?.toString() ?? '';
      final requestId = data['requestId']?.toString() ?? '';
      final tripId = data['tripId']?.toString() ?? '';

      String? foundKey;
      TrackedEmployee? existing;
      if (userId.isNotEmpty && _roster.containsKey(userId)) {
        foundKey = userId;
        existing = _roster[userId];
      } else if (requestId.isNotEmpty && _roster.containsKey(requestId)) {
        foundKey = requestId;
        existing = _roster[requestId];
      } else {
        for (final entry in _roster.entries) {
          if ((requestId.isNotEmpty && entry.value.activeTripId == requestId) ||
              (tripId.isNotEmpty && entry.value.activeTripId == tripId) ||
              (userId.isNotEmpty && entry.key == userId)) {
            foundKey = entry.key;
            existing = entry.value;
            break;
          }
        }
      }

      if (foundKey != null && existing != null) {
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
          final bearing = (data['heading'] ?? data['bearing'] as num?)?.toDouble() ?? 0.0;
          final newPoint = LatLng(lat, lng);

          final updatedEmployee = existing.copyWith(
            position: newPoint,
            path: existing.path.isEmpty
                ? [existing.position, newPoint]
                : (existing.path.last != newPoint ? [...existing.path, newPoint] : existing.path),
            speedKmh: speed * 3.6,
            bearing: bearing,
            lastUpdated: DateTime.tryParse(data['timestamp']?.toString() ?? '') ?? DateTime.now(),
          );
          _roster[foundKey] = updatedEmployee;
          _applyEmployees(liveViaSocket: true);
        }
      }
    });

    // One-time bootstrap: who is on a trip + profile/trip metadata.
    await refresh(force: true, bootstrap: true);

    if (!ws.isBackendUnavailable) {
      await ws.connect();
    }
    if (!mounted) return;

    state = state.copyWith(
      isConnected: ws.isConnected,
      liveViaSocket: false,
    );
    _syncFallbackPolling();
  }

  void _syncFallbackPolling() {
    _fallbackPollTimer?.cancel();

    final ws = _ref.read(webSocketTrackingProvider);
    if (ws.isBackendUnavailable) {
      _fallbackPollTimer = Timer.periodic(_httpFallbackPoll, (_) {
        unawaited(refresh(quiet: true));
      });
      return;
    }

    final socketFresh = _lastSocketLocationAt != null &&
        DateTime.now().difference(_lastSocketLocationAt!) < _socketFreshness;

    if (ws.isConnected && socketFresh) {
      // Socket is live — only occasional HTTP sync for new trips / profile fields.
      _fallbackPollTimer = Timer.periodic(_socketMetadataSync, (_) {
        unawaited(refresh(quiet: true));
      });
      return;
    }

    // Socket down or silent — slower HTTP fallback.
    _fallbackPollTimer = Timer.periodic(_httpFallbackPoll, (_) {
      unawaited(refresh(quiet: true));
    });
  }

  TrackedEmployee _mergeProfile(TrackedEmployee base, TrackedEmployee update) {
    final List<LatLng> mergedPath;
    if (update.path.isNotEmpty) {
      mergedPath = update.path;
    } else if (base.path.isEmpty) {
      mergedPath = [base.position, update.position];
    } else if (base.path.last != update.position) {
      mergedPath = [...base.path, update.position];
    } else {
      mergedPath = base.path;
    }

    return base.copyWith(
      position: update.position,
      speedKmh: update.speedKmh,
      batteryPercent: update.batteryPercent,
      bearing: update.bearing,
      status: update.status,
      lastUpdated: update.lastUpdated,
      hasActiveTrip: update.hasActiveTrip || base.hasActiveTrip,
      activeTripId: update.activeTripId ?? base.activeTripId,
      name: !isGenericEmployeeLabel(update.name) ? update.name : base.name,
      team: update.team ?? base.team,
      email: update.email ?? base.email,
      employeeCode: update.employeeCode ?? base.employeeCode,
      mobile: update.mobile ?? base.mobile,
      role: update.role ?? base.role,
      reportingManagerName:
          update.reportingManagerName ?? base.reportingManagerName,
      tripStatus: update.tripStatus ?? base.tripStatus,
      tripFrom: update.tripFrom ?? base.tripFrom,
      tripTo: update.tripTo ?? base.tripTo,
      path: mergedPath,
    );
  }

  void _applyEmployees({required bool liveViaSocket}) {
    final employees = _roster.values.toList();
    final teams = employees
        .map((e) => e.team)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    state = state.copyWith(
      isLoading: false,
      employees: employees,
      teams: teams,
      liveViaSocket: liveViaSocket,
      lastRefreshError: null,
    );
  }

  TrackedEmployee _toTrackedEmployee({
    required TravelRequestModel model,
    required Map<String, dynamic> row,
    required LatLng position,
    required DateTime now,
    List<LatLng> path = const [],
  }) {
    final status = model.trackingStatus?.toLowerCase();
    final markerStatus = switch (status) {
      'tracking' => TrackingMarkerStatus.active,
      'paused' => TrackingMarkerStatus.gpsStopped,
      _ => model.status == 'Travelling' || model.status == 'Returning'
          ? TrackingMarkerStatus.active
          : TrackingMarkerStatus.online,
    };

    final profile = profileHintsFromTravelRow(row);

    final List<LatLng> parsedPath;
    if (path.isNotEmpty) {
      parsedPath = path;
    } else if (model.routePoints.isNotEmpty) {
      parsedPath = model.routePoints
          .map((p) {
            final lat = (p['latitude'] as num?)?.toDouble();
            final lng = (p['longitude'] as num?)?.toDouble();
            return lat != null && lng != null ? LatLng(lat, lng) : null;
          })
          .whereType<LatLng>()
          .toList();
    } else {
      parsedPath = const [];
    }

    return TrackedEmployee(
      id: liveMapEmployeeId(model),
      name: resolveEmployeeName(row, model),
      team: liveMapTeamLabel(row, model),
      position: position,
      status: markerStatus,
      hasActiveTrip: true,
      activeTripId: model.requestId,
      lastUpdated: now,
      email: profile.email,
      employeeCode: profile.employeeCode,
      mobile: profile.mobile,
      role: profile.role,
      reportingManagerName: profile.reportingManagerName,
      tripStatus: model.status,
      tripFrom: model.fromLocation,
      tripTo: model.toLocation,
      path: parsedPath,
    );
  }

  Future<void> _fetchLastRoutePoint(
    TravelRequestRemoteDataSource api,
    TravelRequestModel model,
    Map<String, dynamic> row,
    DateTime now,
    Map<String, TrackedEmployee> byUser,
  ) async {
    final result = await api.listRoutePoints(model.restResourceId);
    switch (result) {
      case ApiSuccess(:final data):
        final pos = lastPointFromRoutePayload(data);
        if (pos == null) return;
        final id = liveMapEmployeeId(model);
        if (id.isEmpty) return;
        final initialPath = <LatLng>[];
        for (final p in data) {
          final lat = (p['latitude'] as num?)?.toDouble();
          final lng = (p['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            initialPath.add(LatLng(lat, lng));
          }
        }
        byUser[id] = _toTrackedEmployee(
          model: model,
          row: row,
          position: pos,
          now: now,
          path: initialPath,
        );
      case ApiFailure():
        break;
    }
  }

  /// HTTP bootstrap / fallback. Skipped while WebSocket is actively pushing GPS.
  Future<void> refresh({
    bool force = false,
    bool quiet = false,
    bool bootstrap = false,
  }) async {
    if (!mounted) return;

    final ws = _ref.read(webSocketTrackingProvider);
    final socketFresh = _lastSocketLocationAt != null &&
        DateTime.now().difference(_lastSocketLocationAt!) < _socketFreshness;

    if (!force &&
        !bootstrap &&
        ws.isConnected &&
        socketFresh &&
        _roster.isNotEmpty) {
      return;
    }

    if (!quiet && _roster.isEmpty) {
      state = state.copyWith(isLoading: true);
    }

    final api = _ref.read(travelApiProvider);
    final result =
        await api.listTravelRequests(page: 1, limit: 100, mine: false);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        final now = DateTime.now();
        final activeIds = <String>{};
        final pendingRouteFetch = <(TravelRequestModel, Map<String, dynamic>)>[];

        for (final row in data.items) {
          final model = TravelRequestModel.fromMap(row).ensureTripLegs();
          if (!isLiveTravelTrip(model)) continue;

          final id = liveMapEmployeeId(model);
          if (id.isEmpty) continue;
          activeIds.add(id);

          // Join socket room for this trip to receive real-time location broadcasts
          ws.joinTripRoom(model.requestId);

          var position = resolveLivePositionFromRow(row);
          position ??= resolveLivePositionFromRequest(model);

          final existing = _roster[id];
          final preserveSocketPosition = existing != null &&
              ws.isConnected &&
              socketFresh;

          if (position != null) {
            var built = _toTrackedEmployee(
              model: model,
              row: row,
              position: position,
              now: now,
            );
            if (preserveSocketPosition) {
              built = built.copyWith(
                position: existing.position,
                lastUpdated: existing.lastUpdated,
              );
            }
            _roster[id] =
                existing == null ? built : _mergeProfile(existing, built);
          } else if (!preserveSocketPosition) {
            pendingRouteFetch.add((model, row));
          } else {
            final built = _toTrackedEmployee(
              model: model,
              row: row,
              position: existing.position,
              now: existing.lastUpdated,
            );
            _roster[id] = _mergeProfile(existing, built);
          }
        }

        // Leave socket rooms for employees whose trips are no longer active.
        for (final id in _roster.keys) {
          if (!activeIds.contains(id)) {
            final emp = _roster[id];
            if (emp != null && emp.activeTripId != null) {
              ws.leaveTripRoom(emp.activeTripId!);
            }
          }
        }

        // Drop employees whose trips are no longer active.
        _roster.removeWhere((id, _) => !activeIds.contains(id));

        if (pendingRouteFetch.isNotEmpty && !(ws.isConnected && socketFresh)) {
          final fetched = <String, TrackedEmployee>{};
          await Future.wait(
            pendingRouteFetch.map(
              (entry) => _fetchLastRoutePoint(
                api,
                entry.$1,
                entry.$2,
                now,
                fetched,
              ),
            ),
          );
          for (final e in fetched.entries) {
            final prev = _roster[e.key];
            _roster[e.key] =
                prev == null ? e.value : _mergeProfile(prev, e.value);
          }
        }

        if (!mounted) return;
        _applyEmployees(liveViaSocket: ws.isConnected && socketFresh);
        _syncFallbackPolling();
      case ApiFailure(:final failure):
        if (!mounted) return;
        state = state.copyWith(
          isLoading: false,
          lastRefreshError: failure.message,
        );
    }
  }

  void stop() {
    _started = false;
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
    unawaited(_sub?.cancel());
    unawaited(_connSub?.cancel());
    unawaited(_locSub?.cancel());
    _sub = null;
    _connSub = null;
    _locSub = null;

    // Leave all active trip rooms we joined
    final ws = _ref.read(webSocketTrackingProvider);
    for (final emp in _roster.values) {
      if (emp.activeTripId != null) {
        ws.leaveTripRoom(emp.activeTripId!);
      }
    }

    _roster.clear();
    unawaited(_ref.read(webSocketTrackingProvider).disconnect());
  }
}

final liveMapProvider =
    StateNotifierProvider.autoDispose<LiveMapNotifier, LiveMapState>((ref) {
  final notifier = LiveMapNotifier(ref);
  ref.onDispose(notifier.stop);
  return notifier;
});

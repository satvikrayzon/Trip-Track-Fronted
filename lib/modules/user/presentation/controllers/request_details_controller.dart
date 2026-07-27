import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/app_messenger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/hive_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../../core/services/background_location_service.dart';
import '../../../../core/services/location_permission_service.dart';
import '../../../../core/services/punch_location_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/tracking_coverage_service.dart';
import '../../../../core/services/tracking_event_service.dart';
import '../../../../core/services/tracking_session_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/tracking/data/services/trip_realtime_binder.dart';
import '../../../../features/tracking/data/services/websocket_tracking_service.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';
import '../../../../core/services/active_trip_restore_service.dart';
import '../../../../core/widgets/trip_route_map_data.dart';
import '../../../travel/data/datasources/travel_request_remote_datasource.dart';
import '../../../../core/utils/app_debug_log.dart';
import '../../../travel/data/models/tracking_coverage_model.dart';
import '../../../../core/services/distance_service.dart';
import '../../../../core/config/google_maps_config.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/services/travel_request_delete_service.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/services/track_analytics.dart';
import '../../../travel/data/models/route_point_model.dart';
import '../../../../core/utils/geo_utils.dart';

/// Controller for Request Details Screen with offline support.
class RequestDetailsController {
  RequestDetailsController({
    this.initialRequest,
    TravelRequestRemoteDataSource? travelApi,
  }) : _travelApi = travelApi ?? ServiceLocator.I.get() {
    _trackingSession = ServiceLocator.I.get<TrackingSessionService>();
    _punchLocation = ServiceLocator.I.get<PunchLocationService>();
    _activeTripRestore = ActiveTripRestoreService(_travelApi);
    if (ServiceLocator.I.has<TrackingCoverageService>()) {
      _coverageService = ServiceLocator.I.get<TrackingCoverageService>();
    }
  }

  TrackingCoverageService? _coverageService;

  /// When set (e.g. GoRouter deep link), used instead of route arguments.
  final TravelRequestModel? initialRequest;
  final TravelRequestRemoteDataSource _travelApi;
  final HiveDatabase _hiveDb = HiveDatabase.instance;
  late final TrackingSessionService _trackingSession;
  late final PunchLocationService _punchLocation;
  late final ActiveTripRestoreService _activeTripRestore;

  Timer? _pollTimer;
  Timer? _adminLiveMapTimer;
  TripRealtimeBinder? _tripRealtime;
  StreamSubscription<Map<String, dynamic>>? _locationSub;
  StreamSubscription<bool>? _connSubDetail;

  /// Stable business id (UUID) for Hive offline rows — not the Mongo `_id` URL segment.
  late final String _offlineRequestKey;

  final ValueNotifier<TravelRequestModel?> request =
      ValueNotifier<TravelRequestModel?>(null);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isPunching = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isDeleting = ValueNotifier<bool>(false);

  /// Server GPS trail for admin live map (`GET …/route-points`).
  final ValueNotifier<List<LatLng>> adminLivePath =
      ValueNotifier<List<LatLng>>([]);

  final ValueNotifier<TrackingCoverageResult?> trackingCoverage =
      ValueNotifier<TrackingCoverageResult?>(null);
  final ValueNotifier<bool> isCoverageLoading = ValueNotifier<bool>(false);

  void start() {
    final args = initialRequest ?? AppNavigation.arguments;
    if (args is! TravelRequestModel) {
      return;
    }
    final TravelRequestModel resolved = args;
    _offlineRequestKey = resolved.requestId.isNotEmpty
        ? resolved.requestId
        : resolved.restResourceId;
    unawaited(_bootstrapRequest(resolved));
  }

  void dispose() {
    _pollTimer?.cancel();
    _adminLiveMapTimer?.cancel();
    _tripRealtime?.dispose();
    _tripRealtime = null;
    _locationSub?.cancel();
    _locationSub = null;
    _connSubDetail?.cancel();
    _connSubDetail = null;
    if (request.value != null) {
      if (ServiceLocator.I.has<WebSocketTrackingService>()) {
        final ws = ServiceLocator.I.get<WebSocketTrackingService>();
        ws.leaveTripRoom(request.value!.requestId);
      }
    }
    request.dispose();
    isLoading.dispose();
    isOnline.dispose();
    isPunching.dispose();
    isDeleting.dispose();
    adminLivePath.dispose();
    trackingCoverage.dispose();
    isCoverageLoading.dispose();
  }

  Future<void> _bootstrapRequest(TravelRequestModel initialRequest) async {
    final cached = await _readCachedRequest(_offlineRequestKey);
    var seed = initialRequest.ensureTripLegs();
    if (cached != null) {
      seed = seed.mergePreservingLocalProgress(cached).ensureTripLegs();
    }

    final savedId = _hiveDb.getActiveTripIdSync();
    final isLikelyActive = savedId != null &&
        (savedId == seed.requestId ||
            savedId == seed.restResourceId ||
            savedId == _offlineRequestKey);
    if (isLikelyActive) {
      final restored = await _activeTripRestore.resolveActiveTrip();
      if (restored != null &&
          (restored.requestId == seed.requestId ||
              restored.restResourceId == seed.restResourceId)) {
        seed = restored;
        if (ServiceLocator.I.has<TrackingEventService>()) {
          final trackingActive = seed.trackingStatus == 'tracking' ||
              seed.isActive ||
              seed.hasDeparted && !seed.canMarkArrival;
          unawaited(
            ServiceLocator.I.get<TrackingEventService>().checkOsKillSuspected(
                  requestId: seed.requestId,
                  trackingWasActive: trackingActive,
                ),
          );
        }
        if (seed.status == 'Travelling' || seed.status == 'Returning' || seed.trackingStatus == 'tracking') {
          final bg = ServiceLocator.I.get<BackgroundLocationService>();
          if (!bg.isRunning) {
            final session = ServiceLocator.I.get<TrackingSessionService>();
            unawaited(session.onTravelDeparture(
              requestId: seed.requestId,
              legId: seed.activeLeg?.legId ?? seed.tripLegs.firstOrNull?.legId ?? '',
              sessionId: seed.trackingSessionId ?? '',
            ));
          }
        }
      }
    }

    seed = await enhanceRequestWithRoadMetrics(seed);
    request.value = seed;
    _syncAdminLiveMapTimer(seed);
    if (seed.status == AppConstants.statusReadyToStart) {
      unawaited(_punchLocation.prewarm());
    }
    unawaited(_ensureMapCoordinates(seed));
    unawaited(_loadTrackingCoverage(seed));
    final apiId =
        seed.requestId.isNotEmpty ? seed.requestId : _offlineRequestKey;
    _listenToRequestUpdates(apiId);
  }

  Future<TravelRequestModel?> _readCachedRequest(String key) async {
    if (key.isEmpty) return null;
    try {
      final allRequests = await _hiveDb.getAllOfflineTravelRequests();
      for (final row in allRequests) {
        final map = Map<String, dynamic>.from(row);
        final rid = map['requestId']?.toString() ?? '';
        final mongo = map['_id']?.toString() ?? '';
        final tripId = map['tripId']?.toString() ?? map['id']?.toString() ?? '';
        if (rid == key || mongo == key || tripId == key) {
          return TravelRequestModel.fromMap(map).ensureTripLegs();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Geocodes from/to when the API omitted coordinates so the map can center on start.
  Future<void> _ensureMapCoordinates(TravelRequestModel current) async {
    var updated = current;
    var changed = false;

    if (updated.startCoordinates == null) {
      final resolved = await _punchLocation.resolveStartCoordinates(updated);
      if (resolved != null) {
        updated = updated.copyWith(startCoordinates: resolved);
        changed = true;
      }
    }

    if (updated.endCoordinates == null) {
      final leg = updated.activeLeg ??
          (updated.tripLegs.isNotEmpty ? updated.tripLegs.first : null);
      if (leg != null) {
        final resolved = await _punchLocation.resolveDestinationCoordinates(
          updated,
          leg,
        );
        if (resolved != null) {
          updated = updated.copyWith(endCoordinates: resolved);
          changed = true;
        }
      }
    }

    if (!changed) return;

    final live = request.value;
    if (live != null &&
        live.requestId != updated.requestId &&
        live.restResourceId != updated.restResourceId) {
      return;
    }

    request.value = updated;
    await _hiveDb.saveTravelRequest(updated.toMap());

    final apiId = updated.restResourceId;
    if (apiId.isNotEmpty) {
      final patch = <String, dynamic>{};
      final start = updated.startCoordinates;
      final end = updated.endCoordinates;
      if (start != null) {
        patch['originLat'] = start['latitude'];
        patch['originLng'] = start['longitude'];
      }
      if (end != null) {
        patch['destinationLat'] = end['latitude'];
        patch['destinationLng'] = end['longitude'];
      }
      if (patch.isNotEmpty) {
        unawaited(_travelApi.patchTravelRequest(apiId, patch));
      }
    }
  }

  void _listenToRequestUpdates(String requestId) {
    _pollTimer?.cancel();
    _tripRealtime?.dispose();
    _tripRealtime = TripRealtimeBinder(
      filter: (trip) => tripMatchesRealtimeKey(trip, requestId),
      onTripUpdate: (trip) => unawaited(_applyRemoteTrip(trip)),
      onTripRefetch: (id) {
        if (id == requestId) {
          unawaited(_pullRequestFromApi(requestId));
          return;
        }
        final cur = request.value;
        if (cur != null && tripMatchesRealtimeKey(cur, id)) {
          unawaited(_pullRequestFromApi(requestId));
        }
      },
    )..start();

    final ws = ServiceLocator.I.get<WebSocketTrackingService>();
    ws.joinTripRoom(requestId);
    _locationSub?.cancel();
    _locationSub = ws.locationUpdates.listen((payload) {
      final tid = payload['tripId'] ?? payload['requestId'];
      if (tid == requestId) {
        final lat = (payload['latitude'] as num?)?.toDouble();
        final lng = (payload['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final latLng = LatLng(lat, lng);
          final currentPath = List<LatLng>.from(adminLivePath.value);
          if (currentPath.isEmpty || currentPath.last != latLng) {
            currentPath.add(latLng);
            adminLivePath.value = currentPath;

            final currentRequest = request.value;
            if (currentRequest != null) {
              final updatedRoutePoints = List<Map<String, dynamic>>.from(currentRequest.routePoints)
                ..add(Map<String, dynamic>.from(payload));
              request.value = currentRequest.copyWith(routePoints: updatedRoutePoints);
            }
          }
        }
      }
    });

    _connSubDetail?.cancel();
    _connSubDetail = ws.connectionStream.listen((connected) {
      if (connected) {
        ws.joinTripRoom(requestId);
        _adminLiveMapTimer?.cancel();
        _adminLiveMapTimer = null;
        unawaited(_refreshAdminLivePath());
      } else {
        _syncAdminLiveMapTimer(request.value);
      }
    });

    _pollTimer = Timer.periodic(
      _canFetchServerTrail ? const Duration(seconds: 15) : const Duration(seconds: 30),
      (_) {
        if (_tripRealtime?.isLive == true) return;
        unawaited(_pullRequestFromApi(requestId));
      },
    );
    unawaited(_pullRequestFromApi(requestId));
  }

  bool get _isAdmin =>
      ServiceLocator.I.has<AppAuthController>() &&
      ServiceLocator.I.get<AppAuthController>().isHodOrAdmin;

  bool get _canFetchServerTrail {
    if (!ServiceLocator.I.has<AppAuthController>()) return false;
    final auth = ServiceLocator.I.get<AppAuthController>();
    final curUser = auth.currentUserApiId;
    final reqUser = request.value?.userId;
    return auth.isHodOrAdmin || (curUser != null && curUser == reqUser);
  }

  bool _shouldPollServerTrail(TravelRequestModel r) {
    final ts = r.trackingStatus;
    if (ts == 'tracking' || ts == 'paused') return true;
    const live = {
      'Travelling',
      'Returning',
      'In Meeting',
      'At Client',
    };
    return live.contains(r.status);
  }

  void _syncAdminLiveMapTimer(TravelRequestModel? r) {
    if (!_canFetchServerTrail) {
      _adminLiveMapTimer?.cancel();
      _adminLiveMapTimer = null;
      adminLivePath.value = [];
      return;
    }
    if (r == null) return;

    // Load trail immediately for admin review (completed or live trips).
    unawaited(_refreshAdminLivePath());

    final ws = ServiceLocator.I.get<WebSocketTrackingService>();
    if (_shouldPollServerTrail(r) && !ws.isConnected) {
      _adminLiveMapTimer ??= Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(_refreshAdminLivePath()),
      );
    } else {
      _adminLiveMapTimer?.cancel();
      _adminLiveMapTimer = null;
    }
  }

  Future<void> _refreshAdminLivePath() async {
    if (!_canFetchServerTrail) return;
    final r = request.value;
    if (r == null) return;
    final result = await _travelApi.listRoutePoints(r.restResourceId);
    switch (result) {
      case ApiSuccess(:final data):
        final pts = <LatLng>[];
        for (final raw in data) {
          try {
            final m = Map<String, dynamic>.from(raw as Map);
            final lat = (m['latitude'] as num?)?.toDouble();
            final lng = (m['longitude'] as num?)?.toDouble();
            if (lat == null || lng == null) continue;
            if (lat.abs() < 1e-6 && lng.abs() < 1e-6) continue;
            pts.add(LatLng(lat, lng));
          } catch (_) {}
        }
        if (pts.isEmpty) return;
        final path = List<LatLng>.from(pts);
        cacheServerRoutePoints(r.requestId, path);
        adminLivePath.value = path;

        final rawList = data.map((d) => Map<String, dynamic>.from(d as Map)).toList();
        request.value = r.copyWith(routePoints: rawList);
      case ApiFailure(:final failure):
        break;
    }
  }

  String _punchTimeKey(TripPunchModel? p) =>
      p == null ? '-' : p.time.toIso8601String();

  /// Avoids rebuilding the whole details screen when polling returns the same state.
  String _remotePollSignature(TravelRequestModel r) {
    final legs = r.tripLegs
        .map(
          (l) =>
              '${l.legId}:${_punchTimeKey(l.departurePunch)}:${_punchTimeKey(l.arrivalPunch)}:'
              '${_punchTimeKey(l.meetingStartPunch)}:${_punchTimeKey(l.meetingEndPunch)}',
        )
        .join('|');
    return '${r.requestId}|${r.status}|${r.currentLegIndex}|'
        '${r.totalDistanceKm.toStringAsFixed(2)}|'
        '${r.routePointCount}|${r.trackingSessionId ?? ''}|${r.trackingStatus ?? ''}|$legs';
  }

  Future<void> _pullRequestFromApi(String requestId) async {
    final result = await _travelApi.getById(requestId);
    switch (result) {
      case ApiSuccess(:final data):
        final parsed = TravelRequestModel.fromMap(data);
        final enhanced = await enhanceRequestWithRoadMetrics(parsed);
        await _applyRemoteTrip(enhanced);
      case ApiFailure(:final failure):
        final cached = await _readCachedRequest(_offlineRequestKey);
        if (cached != null) {
          request.value = cached;
        } else {
          await _loadFromHive();
        }
        _syncAdminLiveMapTimer(request.value);
    }
  }

  Future<void> _applyRemoteTrip(TravelRequestModel parsed) async {
    final cur = request.value;
    final merged = cur != null
        ? parsed.mergePreservingLocalProgress(cur)
        : parsed.ensureTripLegs();
    if (cur != null &&
        _remotePollSignature(merged) == _remotePollSignature(cur)) {
      if (!isOnline.value) {
        isOnline.value = true;
      }
      await _hiveDb.saveTravelRequest(merged.toMap());
      _syncAdminLiveMapTimer(merged);
      return;
    }
    request.value = merged;
    await _hiveDb.saveTravelRequest(merged.toMap());
    isOnline.value = true;
    _syncAdminLiveMapTimer(merged);
    unawaited(_loadTrackingCoverage(merged));
  }

  Future<void> _loadFromHive() async {
    try {
      final allRequests = await _hiveDb.getAllOfflineTravelRequests();
      final offlineRequest = allRequests.firstWhere(
        (req) =>
            req['requestId'] == _offlineRequestKey ||
            req['_id']?.toString() == _offlineRequestKey,
        orElse: () => <String, dynamic>{},
      );

      if (offlineRequest.isNotEmpty) {
        request.value = TravelRequestModel.fromMap(
          Map<String, dynamic>.from(offlineRequest),
        );
        isOnline.value = false;
      }
    } catch (_) {
      // Keep the initial request visible if offline cache is unavailable.
    }
  }

  Future<void> refreshRequest() async {
    if (request.value == null) return;

    try {
      isLoading.value = true;
      await _pullRequestFromApi(request.value!.restResourceId);
      final cur = request.value;
      if (cur != null) {
        await _loadTrackingCoverage(cur);
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> deleteTravelRequest() async {
    final current = request.value;
    if (current == null) return false;

    isDeleting.value = true;
    try {
      return await TravelRequestDeleteService(
        travelApi: _travelApi,
        hive: _hiveDb,
        activeTripRestore: _activeTripRestore,
      ).delete(current);
    } on NetworkFailure {
      rethrow;
    } finally {
      isDeleting.value = false;
    }
  }

  Future<void> _loadTrackingCoverage(TravelRequestModel trip) async {
    if (!_isAdmin) {
      trackingCoverage.value = null;
      return;
    }
    final service = _coverageService;
    if (service == null) return;
    if (!trip.tripLegs.any((l) => l.departurePunch != null)) {
      trackingCoverage.value = null;
      return;
    }

    try {
      isCoverageLoading.value = true;
      trackingCoverage.value = await service.loadCoverage(trip);
    } catch (e) {
    } finally {
      isCoverageLoading.value = false;
    }
  }

  String get primaryActionLabel {
    final currentRequest = request.value;
    final leg = currentRequest?.activeLeg;
    if (currentRequest == null || leg == null) return '';
    if (currentRequest.status == 'Completed' &&
        !currentRequest.needsReturnArrivalPunch) {
      return 'Trip Completed';
    }

    switch (currentRequest.nextPunchTypeForActiveLeg) {
      case 'travel_departure':
        return leg.isReturnLeg ? 'Start Return' : 'Start Departure';
      case 'travel_arrival':
        return leg.isReturnLeg ? 'Mark Return Arrival' : 'Mark Arrival';
      case 'meeting_start':
        return 'Start Meeting';
      case 'meeting_end':
        return 'End Meeting';
      default:
        return '';
    }
  }

  Future<void> punchNextStep() async {
    final currentRequest = request.value;
    final activeLeg = currentRequest?.activeLeg;
    if (currentRequest == null || activeLeg == null) return;
    if (currentRequest.status == 'Completed' &&
        !currentRequest.needsReturnArrivalPunch) {
      return;
    }

    try {
      isPunching.value = true;

      final punchType =
          currentRequest.nextPunchTypeForActiveLeg ?? _nextPunchType(activeLeg);
      final punchLabel = _nextPunchLabel(activeLeg);
      if (punchType == null || punchLabel == null) {
        _showError(
          'Cannot determine the next step for this stop. Pull to refresh and try again.',
        );
        return;
      }

      final isReturnArrivalPunch =
          punchType == 'travel_arrival' && activeLeg.isReturnLeg;
      void logReturnArrival(String step) {
        if (!isReturnArrivalPunch) return;
      }

      logReturnArrival('start');
      final punch = await _capturePunch(
        currentRequest: currentRequest,
        activeLeg: activeLeg,
        type: punchType,
        label: punchLabel,
      );
      if (punch == null) {
        logReturnArrival('_capturePunch returned null (aborted)');
        return;
      }
      logReturnArrival('after _capturePunch');

      if (punchType == 'travel_departure' ||
          punchType == 'travel_arrival' ||
          punchType == 'meeting_start' ||
          punchType == 'meeting_end') {
        await _submitPunchToApi(
          currentRequest: currentRequest,
          activeLeg: activeLeg,
          punch: punch,
          punchType: punchType,
          isReturnArrivalPunch: isReturnArrivalPunch,
          logReturnArrival: logReturnArrival,
        );
        return;
      }

      _showError('Unknown punch type: $punchType');
    } catch (e, st) {
      _showError('Unable to save punch: $e');
    } finally {
      isPunching.value = false;
    }
  }

  Future<void> _submitPunchToApi({
    required TravelRequestModel currentRequest,
    required TripLegModel activeLeg,
    required TripPunchModel punch,
    required String punchType,
    required bool isReturnArrivalPunch,
    required void Function(String step) logReturnArrival,
  }) async {
    final live = currentRequest.enableLiveTracking &&
        AppConstants.featureLiveGpsTracking;

    if (punchType == 'travel_departure' && live) {
      final ok = await LocationPermissionService.ensureForLiveTracking();
      if (!ok) {
        _showError('Location permission is required for live trip tracking');
        return;
      }
    }

    final body = <String, dynamic>{
      'timestamp': punch.time.toUtc().toIso8601String(),
      'latitude': punch.latitude,
      'longitude': punch.longitude,
      if (punch.address.isNotEmpty) 'address': punch.address,
    };

    final id = currentRequest.restResourceId;
    final result = switch (punchType) {
      'travel_departure' => await _travelApi.postDeparture(id, body),
      'travel_arrival' => await _travelApi.postArrival(id, body),
      'meeting_start' => await _travelApi.postMeetingStart(id, body),
      'meeting_end' => await _travelApi.postMeetingEnd(id, body),
      _ => throw ArgumentError('Unknown punch type: $punchType'),
    };

    switch (result) {
      case ApiSuccess(:final data):
        var updatedRequest = TravelRequestModel.fromMap(data)
            .mergePreservingLocalProgress(currentRequest)
            .ensureTripLegs();

        var trackingSessionId = updatedRequest.trackingSessionId ??
            currentRequest.trackingSessionId;
        var tripStarted =
            updatedRequest.tripStartedAt ?? currentRequest.tripStartedAt;
        var tripEnded = updatedRequest.tripEndedAt ?? currentRequest.tripEndedAt;
        var trackStatus =
            updatedRequest.trackingStatus ?? currentRequest.trackingStatus;

        if (punchType == 'travel_departure' && live) {
          final sid = trackingSessionId ?? const Uuid().v4();
          trackingSessionId = sid;
          final updatedLeg = updatedRequest.activeLeg ?? activeLeg;
          final bg = ServiceLocator.I.get<BackgroundLocationService>();
          if (bg.isRunning && currentRequest.trackingSessionId != null) {
            await _trackingSession.onNextLegDeparture(updatedLeg.legId);
          } else {
            await _trackingSession.onTravelDeparture(
              requestId: updatedRequest.requestId,
              legId: updatedLeg.legId,
              sessionId: sid,
            );
          }
          tripStarted = tripStarted ?? DateTime.now();
          trackStatus = 'tracking';
        }

        if (punchType == 'travel_arrival') {
          logReturnArrival('travel_arrival: API success');
          final updatedLeg = updatedRequest.activeLeg ?? activeLeg;
          if (updatedLeg.isReturnLeg && live) {
            tripEnded = DateTime.now();
            trackStatus = 'ended';
          }
        }

        updatedRequest = updatedRequest.copyWith(
          trackingSessionId: trackingSessionId,
          tripStartedAt: tripStarted,
          tripEndedAt: tripEnded,
          trackingStatus: trackStatus,
        );

        updatedRequest = await enhanceRequestWithRoadMetrics(updatedRequest);
        request.value = updatedRequest;
        await _hiveDb.saveTravelRequest(updatedRequest.toMap());
        await _activeTripRestore.pinActiveTrip(updatedRequest);
        await _activeTripRestore.clearActiveTripIfCompleted(updatedRequest);
        _syncAdminLiveMapTimer(updatedRequest);

        if (live && punchType == 'travel_arrival') {
          final leg = updatedRequest.activeLeg ?? activeLeg;
          if (leg.isReturnLeg) {
            unawaited(_trackingSession.endEntireTrip());
          } else {
            unawaited(_trackingSession.onTravelArrivalPaused());
          }
        }
        if (live &&
            (punchType == 'meeting_start' || punchType == 'meeting_end')) {
          unawaited(
            _trackingSession.recordMeetingStopMarker(isStopMarker: true),
          );
        }

        unawaited(_syncRoutePointCountToApi(updatedRequest.requestId));
        if (ServiceLocator.I.has<SyncService>()) {
          unawaited(
            ServiceLocator.I.get<SyncService>().uploadPendingRoutePoints(),
          );
        }
        logReturnArrival('done, showing success');
        _showSuccess('Punch saved with time and GPS location');
        unawaited(_loadTrackingCoverage(updatedRequest));
      case ApiFailure(:final failure):
        logReturnArrival('API failure: ${failure.message}');
        _showError(failure.message);
    }
  }

  Future<void> addClientLeg({
    required String clientName,
    required String destination,
    required String purpose,
  }) async {
    final currentRequest = request.value;
    if (currentRequest == null || !currentRequest.canAddNextClient) {
      _showError(
          'Complete the current client meeting before adding next client');
      return;
    }

    try {
      isLoading.value = true;
      final previousLeg = currentRequest.tripLegs.last;
      final result = await _travelApi.postNextClient(
        currentRequest.restResourceId,
        {
          'toLocation': destination,
          'clientName': clientName,
          'purpose': purpose,
          'clientOfficeAddress': destination,
          'fromLocation': previousLeg.toLocation,
          'tripLegs': currentRequest.tripLegs.map((l) => l.toMap()).toList(),
        },
      );

      switch (result) {
        case ApiSuccess(:final data):
          final updatedRequest = _applyNextClientResult(
            current: currentRequest,
            data: data,
            clientName: clientName,
            destination: destination,
            purpose: purpose,
            fromLocation: previousLeg.toLocation,
          );
          request.value = updatedRequest;
          await _hiveDb.saveTravelRequest(updatedRequest.toMap());
          await _activeTripRestore.pinActiveTrip(updatedRequest);
          _syncAdminLiveMapTimer(updatedRequest);
          _showSuccess('Next client added to this trip');
        case ApiFailure(:final failure):
          _showError(failure.message);
      }
    } catch (e, st) {
      _showError('Unable to add client: $e');
    } finally {
      isLoading.value = false;
    }
  }

  TravelRequestModel _applyNextClientResult({
    required TravelRequestModel current,
    required Map<String, dynamic> data,
    required String clientName,
    required String destination,
    required String purpose,
    required String fromLocation,
  }) {
    final parsed = TravelRequestModel.fromMap(data).ensureTripLegs();
    if (parsed.tripLegs.length >= current.tripLegs.length + 1) {
      return parsed
          .mergePreservingLocalProgress(current)
          .ensureTripLegs()
          .copyWith(apiHasDeparted: false, apiCanMarkArrival: false)
          .withRecalculatedSummary(
            statusOverride: AppConstants.statusReadyToStart,
          );
    }

    final newLeg = TripLegModel(
      legId: 'leg_${current.tripLegs.length + 1}_${DateTime.now().millisecondsSinceEpoch}',
      sequence: current.tripLegs.length + 1,
      fromLocation: fromLocation,
      toLocation: destination,
      clientName: clientName,
      purpose: purpose,
      clientOfficeAddress: destination,
    );

    return current
        .copyWith(
          tripLegs: [...current.tripLegs, newLeg],
          toLocation: destination,
          clientName: clientName,
          purpose: purpose,
          apiHasDeparted: false,
          apiCanMarkArrival: false,
        )
        .withRecalculatedSummary(statusOverride: AppConstants.statusReadyToStart);
  }

  Future<void> startReturnTrip() async {
    final currentRequest = request.value;
    if (currentRequest == null || !currentRequest.canStartReturnTrip) {
      _showError('Complete the current meeting before starting return trip');
      return;
    }

    try {
      isLoading.value = true;

      final position = await _punchLocation.getFastPosition();
      if (position == null) {
        _showError(
          'Could not get GPS. Turn on location, wait for signal, and try again.',
        );
        return;
      }

      final body = <String, dynamic>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'latitude': position.latitude,
        'longitude': position.longitude,
      };

      final result = await _travelApi.postReturnStart(
        currentRequest.restResourceId,
        body,
      );

      switch (result) {
        case ApiSuccess(:final data):
          final updatedRequest = TravelRequestModel.fromMap(data)
              .mergePreservingLocalProgress(currentRequest)
              .ensureTripLegs();
          request.value = updatedRequest;
          await _hiveDb.saveTravelRequest(updatedRequest.toMap());
          await _activeTripRestore.pinActiveTrip(updatedRequest);
          _syncAdminLiveMapTimer(updatedRequest);
          _showSuccess('Return leg added. Punch when you leave.');
        case ApiFailure(:final failure):
          _showError(failure.message);
      }
    } catch (e, st) {
      _showError('Unable to start return trip: $e');
    } finally {
      isLoading.value = false;
    }
  }
  Future<void> _syncRoutePointCountToApi(String logicalRequestId) async {
    try {
      final c = await _hiveDb.countRoutePointsForRequest(logicalRequestId);
      final cur = request.value;
      final pathId = cur?.restResourceId ?? logicalRequestId;
      await _travelApi.update(pathId, {
        'routePointCount': c,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      if (cur != null && cur.requestId == logicalRequestId) {
        request.value = cur.copyWith(routePointCount: c);
      }
    } catch (_) {
      // Non-critical; count will refresh on next trip load.
    }
  }

  Future<TravelRequestModel> enhanceRequestWithRoadMetrics(TravelRequestModel current) async {
    final pointsRaw = await _hiveDb.getRoutePointsForRequest(current.requestId);
    var allPoints = pointsRaw.map((e) => RoutePointModel.fromMap(e)).toList();

    if (allPoints.isEmpty && current.routePoints.isNotEmpty) {
      allPoints = current.routePoints.map((e) => RoutePointModel.fromMap(e)).toList();
    }

    if (allPoints.isEmpty && current.restResourceId.isNotEmpty && isOnline.value) {
      try {
        final res = await _travelApi.listRoutePoints(current.restResourceId);
        if (res case ApiSuccess(:final data)) {
          allPoints = data.map((d) => RoutePointModel.fromMap(d)).toList();
        }
      } catch (_) {}
    }

    final distanceService = DistanceService();
    var updatedLegs = <TripLegModel>[];
    var changed = false;

    for (final leg in current.tripLegs) {
      if (leg.departurePunch != null && leg.arrivalPunch != null) {
        final start = leg.departurePunch!.time.toUtc();
        final end = leg.arrivalPunch!.time.toUtc();
        final legPoints = allPoints.where((p) {
          if (p.legId == leg.legId) return true;
          final t = p.timestamp.toUtc();
          return !t.isBefore(start) && !t.isAfter(end);
        }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        if (legPoints.length >= 2) {
          legPoints.sort((a, b) => a.timestamp.compareTo(b.timestamp));

          final filledLegPoints = <RoutePointModel>[];
          filledLegPoints.add(legPoints.first);

          for (int i = 1; i < legPoints.length; i++) {
            final prev = legPoints[i - 1];
            final next = legPoints[i];

            final timeDiff = next.timestamp.difference(prev.timestamp);
            if (timeDiff > const Duration(minutes: 5) && GoogleMapsConfig.isConfigured) {
              final directDist = GeoUtils.distanceMeters(
                prev.latitude, prev.longitude,
                next.latitude, next.longitude,
              );
              if (directDist > 150) {
                try {
                  final routes = await distanceService.fetchDrivingRoutesWithAlternatives(
                    originLatitude: prev.latitude,
                    originLongitude: prev.longitude,
                    destinationLatitude: next.latitude,
                    destinationLongitude: next.longitude,
                  );
                  if (routes.isNotEmpty) {
                    final routePoints = routes.first.polylinePoints;
                    final stepTime = timeDiff.inMilliseconds ~/ (routePoints.length + 1);

                    for (int j = 1; j < routePoints.length - 1; j++) {
                      final pt = routePoints[j];
                      final interpolatedTime = prev.timestamp.add(Duration(milliseconds: stepTime * j));
                      filledLegPoints.add(RoutePointModel(
                        pointId: 'gap_${prev.pointId}_$j',
                        requestId: prev.requestId,
                        legId: leg.legId,
                        sessionId: prev.sessionId,
                        timestamp: interpolatedTime,
                        latitude: pt.latitude,
                        longitude: pt.longitude,
                        accuracy: 10.0,
                        speed: 0.0,
                        heading: 0.0,
                        altitude: 0.0,
                        isMoving: true,
                        isStopMarker: false,
                        source: 'google_gap_filler',
                        isSynced: false,
                      ));
                    }
                  }
                } catch (_) {}
              }
            }
            filledLegPoints.add(next);
          }

          final normalizedPoints = filledLegPoints.map<RoutePointModel>((p) => RoutePointModel(
            pointId: p.pointId,
            requestId: p.requestId,
            legId: leg.legId,
            sessionId: p.sessionId,
            timestamp: p.timestamp,
            latitude: p.latitude,
            longitude: p.longitude,
            accuracy: p.accuracy,
            speed: p.speed,
            heading: p.heading,
            altitude: p.altitude,
            isMoving: p.isMoving,
            isStopMarker: p.isStopMarker,
            source: p.source,
            isSynced: p.isSynced,
          )).toList();

          final legMetrics = TrackAnalytics.computeLegMetrics(
            points: normalizedPoints,
            legId: leg.legId,
            startInclusive: start,
            endInclusive: end,
            vehicleType: current.vehicleType,
          );

          if (legMetrics.distanceKm > 0 && legMetrics.polylineEncoded.isNotEmpty) {
            final actualDistance = legMetrics.distanceKm;
            final encodedPolyline = legMetrics.polylineEncoded;

            if (leg.actualDistanceKmFromTrack != actualDistance ||
                leg.routePolylineEncoded != encodedPolyline) {
              updatedLegs.add(leg.copyWith(
                actualDistanceKmFromTrack: actualDistance,
                routePolylineEncoded: encodedPolyline,
                trackMovingDurationMinutes: legMetrics.movingMinutes,
                trackStoppedDurationMinutes: legMetrics.stoppedMinutes,
              ));
              changed = true;
              continue;
            } else {
              updatedLegs.add(leg);
              continue;
            }
          }
        }

        final needsMetrics = leg.actualDistanceKmFromTrack == null ||
            leg.routePolylineEncoded == null ||
            leg.routePolylineEncoded!.isEmpty;

        if (needsMetrics && GoogleMapsConfig.isConfigured) {
          try {
            final routes = await distanceService.fetchDrivingRoutesWithAlternatives(
              originLatitude: leg.departurePunch!.latitude,
              originLongitude: leg.departurePunch!.longitude,
              destinationLatitude: leg.arrivalPunch!.latitude,
              destinationLongitude: leg.arrivalPunch!.longitude,
            );

            if (routes.isNotEmpty) {
              final bestRoute = routes.first;
              final roadDistance = bestRoute.distanceKm;
              final points = bestRoute.polylinePoints;
              final encodedPolyline = points.map((p) => '${p.latitude},${p.longitude}').join('|');

              updatedLegs.add(leg.copyWith(
                actualDistanceKmFromTrack: roadDistance,
                routePolylineEncoded: encodedPolyline,
              ));
              changed = true;
              continue;
            }
          } catch (e) {
          }
        }
      }
      updatedLegs.add(leg);
    }

    if (changed) {
      final updated = current.copyWith(tripLegs: updatedLegs).withRecalculatedSummary();
      // Asynchronously update server and database
      unawaited(_syncEnhancedMetricsToApi(updated));
      return updated;
    }
    return current;
  }

  Future<void> _syncEnhancedMetricsToApi(TravelRequestModel updated) async {
    try {
      final pathId = updated.restResourceId;
      final legMaps = updated.tripLegs.map((l) => l.toMap()).toList();
      await _travelApi.update(pathId, {
        'tripLegs': legMaps,
        'totalDistanceKm': updated.totalDistanceKm,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      // Save updated request to Hive database
      await _hiveDb.saveTravelRequest(updated.toMap());
    } catch (e) {
    }
  }

  String? _nextPunchType(TripLegModel leg) {
    if (leg.departurePunch == null) return 'travel_departure';
    if (leg.arrivalPunch == null) return 'travel_arrival';
    if (!leg.isReturnLeg && leg.meetingStartPunch == null) {
      return 'meeting_start';
    }
    if (!leg.isReturnLeg && leg.meetingEndPunch == null) {
      return 'meeting_end';
    }
    return null;
  }

  String? _nextPunchLabel(TripLegModel leg) {
    if (leg.departurePunch == null) {
      return leg.isReturnLeg
          ? 'Return started from ${leg.fromLocation}'
          : 'Departed from ${leg.fromLocation}';
    }
    if (leg.arrivalPunch == null) {
      return leg.isReturnLeg
          ? 'Returned to ${leg.toLocation}'
          : 'Arrived at ${leg.toLocation}';
    }
    if (!leg.isReturnLeg && leg.meetingStartPunch == null) {
      return 'Meeting started with ${leg.displayTitle}';
    }
    if (!leg.isReturnLeg && leg.meetingEndPunch == null) {
      return 'Meeting ended with ${leg.displayTitle}';
    }
    return null;
  }

  Future<TripPunchModel?> _capturePunch({
    required TravelRequestModel currentRequest,
    required TripLegModel activeLeg,
    required String type,
    required String label,
  }) async {
    final position = await _punchLocation.getFastPosition();
    if (position == null) {
      if (ServiceLocator.I.has<TrackingEventService>()) {
        unawaited(
          ServiceLocator.I.get<TrackingEventService>().onPermissionDenied(
                requestId: currentRequest.requestId,
              ),
        );
      }
      _showError(
        'Could not get GPS. Turn on location, wait for signal, and try again.',
      );
      return null;
    }

    if (position.accuracy > AppConstants.punchMaxAccuracyMeters) {
      _showError(
        'GPS accuracy is ${position.accuracy.round()}m (need '
        '${AppConstants.punchMaxAccuracyMeters.round()}m or better). '
        'Wait a few seconds in open sky and try again.',
      );
      return null;
    }

    var requestForChecks = await _punchLocation.ensurePlannedCoordinates(
      currentRequest,
      leg: activeLeg,
    );
    if (requestForChecks != currentRequest) {
      request.value = requestForChecks;
      unawaited(_hiveDb.saveTravelRequest(requestForChecks.toMap()));
      final patch = _punchLocation.plannedCoordinatePatch(requestForChecks);
      final apiId = requestForChecks.restResourceId;
      if (patch.isNotEmpty && apiId.isNotEmpty) {
        unawaited(_travelApi.patchTravelRequest(apiId, patch));
      }
    }

    if (type == 'travel_departure') {
      final geoError = await _punchLocation.departureGeofenceError(
        request: requestForChecks,
        activeLeg: activeLeg,
        userLat: position.latitude,
        userLng: position.longitude,
      );
      if (geoError != null) {
        _showError(geoError);
        return null;
      }
    }

    if (type == 'travel_arrival') {
      final geoError = await _punchLocation.arrivalGeofenceError(
        request: requestForChecks,
        leg: activeLeg,
        userLat: position.latitude,
        userLng: position.longitude,
      );
      if (geoError != null) {
        _showError(geoError);
        return null;
      }
    }

    final address = await _punchLocation.addressFromGps(
      position.latitude,
      position.longitude,
    );

    return TripPunchModel(
      punchId: const Uuid().v4(),
      type: type,
      label: label,
      time: DateTime.now(),
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      address: address,
    );
  }

  void _showSuccess(String message) {
    _safeSnackbar(
      title: 'Success',
      message: message,
      backgroundColor: AppColors.success,
    );
  }

  void _showError(String message) {
    _safeSnackbar(
      title: 'Error',
      message: message,
      backgroundColor: AppColors.error,
    );
  }

  bool _tryScaffoldSnackBar({
    required String title,
    required String message,
    required Color backgroundColor,
  }) {
    final rootState = rootScaffoldMessengerKey.currentState;
    if (rootState != null) {
      rootState
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '$title\n$message',
              style: const TextStyle(color: AppColors.white),
            ),
            backgroundColor: backgroundColor,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      return true;
    }

    return false;
  }

  void _safeSnackbar({
    required String title,
    required String message,
    required Color backgroundColor,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tryScaffoldSnackBar(
        title: title,
        message: message,
        backgroundColor: backgroundColor,
      )) {
        return;
      }
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _tryScaffoldSnackBar(
          title: title,
          message: message,
          backgroundColor: backgroundColor,
        );
      });
    });
  }
}

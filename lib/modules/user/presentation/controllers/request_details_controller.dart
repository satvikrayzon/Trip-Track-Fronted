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
import '../../../../core/services/map_matching_service.dart';
import '../../../../core/services/punch_location_service.dart';
import '../../../../core/services/punch_reminder_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/tracking_coverage_service.dart';
import '../../../../core/services/tracking_event_service.dart';
import '../../../../core/services/tracking_session_service.dart';
import '../../../../core/services/trip_road_metrics_service.dart';
import '../../../travel/data/models/route_segment_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/tracking/data/services/trip_realtime_binder.dart';
import '../../../../features/tracking/data/services/websocket_tracking_service.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';
import '../../../../core/services/active_trip_restore_service.dart';
import '../../../../core/widgets/trip_route_map_data.dart';
import '../../../travel/data/datasources/travel_request_remote_datasource.dart';
import '../../../travel/data/models/tracking_coverage_model.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/services/travel_request_delete_service.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/utils/geo_utils.dart';

/// Controller for Request Details Screen with offline support.
class RequestDetailsController {
  RequestDetailsController({
    this.initialRequest,
    TravelRequestRemoteDataSource? travelApi,
  }) : _travelApi = travelApi ?? ServiceLocator.I.get() {
    _trackingSession = ServiceLocator.I.get<TrackingSessionService>();
    _punchLocation = ServiceLocator.I.get<PunchLocationService>();
    if (ServiceLocator.I.has<PunchReminderService>()) {
      _punchReminder = ServiceLocator.I.get<PunchReminderService>();
    }
    _activeTripRestore = ActiveTripRestoreService(_travelApi);
    if (ServiceLocator.I.has<TrackingCoverageService>()) {
      _coverageService = ServiceLocator.I.get<TrackingCoverageService>();
    }
  }

  TrackingCoverageService? _coverageService;
  PunchReminderService? _punchReminder;

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
  StreamSubscription<Map<String, dynamic>>? _routeMatchedSub;
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

  /// Live punch nudge (500m geofence). Backed by [PunchReminderService].
  ValueNotifier<PunchReminderState?> get punchReminder =>
      _punchReminder?.reminder ?? _emptyPunchReminder;

  static final ValueNotifier<PunchReminderState?> _emptyPunchReminder =
      ValueNotifier<PunchReminderState?>(null);

  void start() {
    final args = initialRequest ?? AppNavigation.arguments;
    if (args is! TravelRequestModel) {
      return;
    }
    final TravelRequestModel resolved = args;
    _offlineRequestKey = resolved.requestId.isNotEmpty
        ? resolved.requestId
        : resolved.restResourceId;
    request.addListener(_onRequestChangedForReminder);
    unawaited(_bootstrapRequest(resolved));
  }

  void _onRequestChangedForReminder() {
    final trip = request.value;
    if (trip != null) _syncPunchReminder(trip);
  }

  void dispose() {
    _pollTimer?.cancel();
    _adminLiveMapTimer?.cancel();
    _tripRealtime?.dispose();
    _tripRealtime = null;
    _locationSub?.cancel();
    _locationSub = null;
    _routeMatchedSub?.cancel();
    _routeMatchedSub = null;
    _connSubDetail?.cancel();
    _connSubDetail = null;
    request.removeListener(_onRequestChangedForReminder);
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

  void _syncPunchReminder(TravelRequestModel trip) {
    _punchReminder?.watch(trip);
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
        if (seed.status == 'Travelling' ||
            seed.status == 'Returning' ||
            seed.trackingStatus == 'tracking') {
          final bg = ServiceLocator.I.get<BackgroundLocationService>();
          final stale =
              bg.recentTrackerFix(maxAge: const Duration(seconds: 90));
          if (!bg.isRunning || stale == null) {
            final session = ServiceLocator.I.get<TrackingSessionService>();
            final requestId = seed.requestId.isNotEmpty
                ? seed.requestId
                : seed.restResourceId;
            final legId = seed.activeLeg?.legId ??
                seed.tripLegs.firstOrNull?.legId ??
                '';
            final sessionId = seed.trackingSessionId ?? '';
            if (requestId.isNotEmpty && legId.isNotEmpty) {
              unawaited(session.onTravelDeparture(
                requestId: requestId,
                legId: legId,
                sessionId: sessionId.isNotEmpty ? sessionId : requestId,
              ));
            }
          }
        }
      }
    }

    seed = await enhanceRequestWithRoadMetrics(seed);
    // Official match is for map Layer B only — do not rematch on every open
    // (that was rewriting km). Merge cached match without changing locked GPS.
    seed = await _enhanceWithOfficialMatch(seed, rematchIfCompleted: false);
    seed = seed.sanitizeAbsurdOfficialDistances();
    request.value = seed;
    _syncPunchReminder(seed);
    _syncAdminLiveMapTimer(seed);
    if (seed.status == AppConstants.statusReadyToStart ||
        seed.nextPunchTypeForActiveLeg == 'travel_departure') {
      unawaited(_punchLocation.prewarm());
    }
    unawaited(_ensureMapCoordinates(seed));
    unawaited(_loadTrackingCoverage(seed));
    final apiId =
        seed.requestId.isNotEmpty ? seed.requestId : _offlineRequestKey;
    _listenToRequestUpdates(apiId);
    _listenToRouteMatched(apiId);
  }

  Future<TravelRequestModel> _enhanceWithOfficialMatch(
    TravelRequestModel current, {
    bool rematchIfCompleted = false,
  }) async {
    if (!ServiceLocator.I.has<MapMatchingService>()) return current;
    try {
      final matcher = ServiceLocator.I.get<MapMatchingService>();
      final updated = await matcher.enhanceWithOfficialMatch(current);

      // Rematch only when explicitly requested (e.g. trip just ended) — not
      // every details open.
      final completed = updated.status == AppConstants.statusCompleted ||
          updated.tripEndedAt != null;
      if (rematchIfCompleted && completed) {
        final id = updated.restResourceId.isNotEmpty
            ? updated.restResourceId
            : updated.requestId;
        unawaited(() async {
          final match = await matcher.triggerMatch(id, reason: 'manual');
          if (match == null || !match.isReady) return;
          final cur = request.value;
          if (cur == null) return;
          request.value = await matcher.applyMatchToRequest(cur, match);
        }());
      }
      return updated;
    } catch (_) {
      return current;
    }
  }

  void _listenToRouteMatched(String requestId) {
    _routeMatchedSub?.cancel();
    if (!ServiceLocator.I.has<WebSocketTrackingService>()) return;
    if (!ServiceLocator.I.has<MapMatchingService>()) return;
    final ws = ServiceLocator.I.get<WebSocketTrackingService>();
    final matcher = ServiceLocator.I.get<MapMatchingService>();
    _routeMatchedSub = ws.routeMatchedUpdates.listen((payload) async {
      final match = MatchedRouteResult.fromMap(payload);
      final id = match.requestId;
      final current = request.value;
      if (current == null) return;
      final matches = id.isEmpty ||
          id == current.requestId ||
          id == current.restResourceId ||
          id == requestId;
      if (!matches) return;
      final updated = await matcher.applyMatchToRequest(current, match);
      request.value = updated;
    });
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

    if (GeoUtils.validCoordinates(updated.startCoordinates) == null) {
      final resolved = await _punchLocation.resolveStartCoordinates(updated);
      if (resolved != null) {
        updated = updated.copyWith(startCoordinates: resolved);
        changed = true;
      }
    }

    if (GeoUtils.validCoordinates(updated.endCoordinates) == null) {
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
      final start = GeoUtils.validCoordinates(updated.startCoordinates);
      final end = GeoUtils.validCoordinates(updated.endCoordinates);
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
    final cur = request.value;
    if (cur != null) {
      if (cur.restResourceId.isNotEmpty && cur.restResourceId != requestId) {
        ws.joinTripRoom(cur.restResourceId);
      }
      if (cur.tripId.isNotEmpty && cur.tripId != requestId) {
        ws.joinTripRoom(cur.tripId);
      }
    }
    _locationSub?.cancel();
    _locationSub = ws.locationUpdates.listen((payload) {
      final tid = (payload['tripId'] ?? payload['requestId'])?.toString() ?? '';
      final current = request.value;
      if (tid.isEmpty || current == null) return;
      if (!tripMatchesRealtimeKey(current, tid) && tid != requestId) return;

      final lat = (payload['latitude'] as num?)?.toDouble();
      final lng = (payload['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null || !GeoUtils.isValidLatLng(lat, lng)) {
        return;
      }
      final latLng = LatLng(lat, lng);
      final currentPath = List<LatLng>.from(adminLivePath.value);
      // Drop live teleports so the map cannot paint ocean lines.
      if (currentPath.isNotEmpty) {
        final prev = currentPath.last;
        final jump = GeoUtils.distanceMeters(
          prev.latitude,
          prev.longitude,
          lat,
          lng,
        );
        if (jump > 2500) return;
      }
      if (currentPath.isEmpty || currentPath.last != latLng) {
        currentPath.add(latLng);
        adminLivePath.value = currentPath;
        // Do NOT rewrite request.routePoints every GPS tick — that rebuilt
        // the whole map (loader + erase). Trail paint appends from adminLivePath.
      }
    });

    _connSubDetail?.cancel();
    _connSubDetail = ws.connectionStream.listen((connected) {
      if (connected) {
        ws.joinTripRoom(requestId);
        final live = request.value;
        if (live != null) {
          if (live.restResourceId.isNotEmpty) {
            ws.joinTripRoom(live.restResourceId);
          }
          if (live.tripId.isNotEmpty) {
            ws.joinTripRoom(live.tripId);
          }
        }
        unawaited(_refreshAdminLivePath());
        // Keep a safety poll even while socket is up — location events can
        // be dropped after reconnect until rooms rejoin fully.
        _syncAdminLiveMapTimer(request.value);
      } else {
        _syncAdminLiveMapTimer(request.value);
      }
    });

    _pollTimer = Timer.periodic(
      _canFetchServerTrail
          ? const Duration(seconds: 15)
          : const Duration(seconds: 30),
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

    if (_shouldPollServerTrail(r)) {
      // Always poll for live trips. Socket tips can stall after offline→online
      // even when ws.isConnected is true.
      _adminLiveMapTimer ??= Timer.periodic(
        const Duration(seconds: 15),
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

        final rawList =
            data.map((d) => Map<String, dynamic>.from(d as Map)).toList();
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
        var enhanced = await enhanceRequestWithRoadMetrics(parsed);
        enhanced = await _enhanceWithOfficialMatch(
          enhanced,
          rematchIfCompleted: false,
        );
        enhanced = enhanced.sanitizeAbsurdOfficialDistances();
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
        _showError(
          'Location permission is required for live trip tracking. '
          'Enable Location for Trip Track in Settings (While Using or Always), then try again.',
        );
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
        var tripEnded =
            updatedRequest.tripEndedAt ?? currentRequest.tripEndedAt;
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

        // Calculate GPS km once after arrival (only fills missing); persist to server.
        updatedRequest = await enhanceRequestWithRoadMetrics(updatedRequest);
        updatedRequest = await _enhanceWithOfficialMatch(
          updatedRequest,
          rematchIfCompleted: punchType == 'travel_arrival' &&
              (updatedRequest.activeLeg?.isReturnLeg == true ||
                  updatedRequest.status == AppConstants.statusCompleted),
        );
        updatedRequest = updatedRequest.sanitizeAbsurdOfficialDistances();
        request.value = updatedRequest;
        await _hiveDb.saveTravelRequest(updatedRequest.toMap());
        await _activeTripRestore.pinActiveTrip(updatedRequest);
        await _activeTripRestore.clearActiveTripIfCompleted(updatedRequest);
        _syncAdminLiveMapTimer(updatedRequest);

        if (live && punchType == 'travel_arrival') {
          final leg = updatedRequest.activeLeg ?? activeLeg;
          if (leg.isReturnLeg) {
            unawaited(_trackingSession.endEntireTrip());
            if (ServiceLocator.I.has<MapMatchingService>()) {
              unawaited(
                ServiceLocator.I.get<MapMatchingService>().triggerMatch(
                      updatedRequest.restResourceId,
                      reason: 'trip_end',
                    ),
              );
            }
          } else {
            unawaited(_trackingSession.onTravelArrivalPaused());
            if (ServiceLocator.I.has<MapMatchingService>()) {
              unawaited(
                ServiceLocator.I.get<MapMatchingService>().triggerMatch(
                      updatedRequest.restResourceId,
                      reason: 'incremental',
                    ),
              );
            }
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
          // Trip end: await catch-up so server has resume/filler points before
          // admin/completed maps load from listRoutePoints.
          final ended = punchType == 'travel_arrival' &&
              (updatedRequest.activeLeg ?? activeLeg).isReturnLeg;
          if (ended) {
            await ServiceLocator.I
                .get<SyncService>()
                .uploadPendingRoutePoints();
            if (ServiceLocator.I.has<MapMatchingService>()) {
              unawaited(
                ServiceLocator.I.get<MapMatchingService>().triggerMatch(
                      updatedRequest.restResourceId.isNotEmpty
                          ? updatedRequest.restResourceId
                          : updatedRequest.requestId,
                      reason: 'trip_end',
                    ),
              );
            }
          } else {
            unawaited(
              ServiceLocator.I.get<SyncService>().uploadPendingRoutePoints(),
            );
          }
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
      legId:
          'leg_${current.tripLegs.length + 1}_${DateTime.now().millisecondsSinceEpoch}',
      sequence: current.tripLegs.length + 1,
      fromLocation: fromLocation,
      toLocation: destination,
      clientName: clientName,
      purpose: purpose,
      clientOfficeAddress: destination,
    );

    return current.copyWith(
      tripLegs: [...current.tripLegs, newLeg],
      toLocation: destination,
      clientName: clientName,
      purpose: purpose,
      apiHasDeparted: false,
      apiCanMarkArrival: false,
    ).withRecalculatedSummary(statusOverride: AppConstants.statusReadyToStart);
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

  Future<TravelRequestModel> enhanceRequestWithRoadMetrics(
      TravelRequestModel current) async {
    if (!ServiceLocator.I.has<TripRoadMetricsService>()) {
      return current.sanitizeAbsurdOfficialDistances().withRecalculatedSummary();
    }
    // Don't re-run Snap/Directions on every details open when km already exists —
    // that made the screen feel stuck while the map also aligned.
    final needsKm = current.tripLegs.any((l) {
      if (l.departurePunch == null) return false;
      final gps = l.provisionalDistanceKm ?? l.actualDistanceKmFromTrack;
      return gps == null || gps <= 0.05;
    });
    return ServiceLocator.I.get<TripRoadMetricsService>().enhance(
      current,
      persist: true,
      syncFromTrack: needsKm,
    );
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

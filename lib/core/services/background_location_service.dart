import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:location/location.dart' as loc;
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../database/hive_database.dart';
import '../filter/kalman_filter_2d.dart';
import '../utils/gps_jump_gate.dart';
import '../utils/geo_utils.dart';
import '../../modules/travel/data/models/route_point_model.dart';
import '../di/service_locator.dart';
import '../../features/tracking/data/services/websocket_tracking_service.dart';
import '../../modules/auth/presentation/controllers/app_auth_controller.dart';
import 'connectivity_service.dart';
import 'gps_gap_road_fill.dart';
import 'sync_service.dart';

/// High vs low frequency sampling for adaptive GPS.
enum TrackingPace {
  /// ~3-8s style: 5s interval, 8m filter
  traveling,

  /// ~20-30s style: 25s interval, 35m filter
  paused,
}

/// Continuous GPS for live trip path; persists to Hive.
class BackgroundLocationService {
  final loc.Location _location = loc.Location();
  StreamSubscription<loc.LocationData>? _subscription;

  String? _requestId;
  String? _legId;
  String? _sessionId;
  TrackingPace _pace = TrackingPace.traveling;

  final KalmanFilter2D _kalmanFilter = KalmanFilter2D();

  loc.LocationData? _lastAccepted;
  DateTime? _lastEmitTime;
  String? _lastPointId;
  loc.LocationData? _prevAccepted;
  DateTime? _prevEmitTime;
  String? _prevPointId;
  final ValueNotifier<int> pointsBuffered = ValueNotifier<int>(0);

  String? get activeRequestId => _requestId;
  String? get activeLegId => _legId;
  String? get activeSessionId => _sessionId;
  bool get isRunning => _subscription != null;

  /// Last good fix from the live stream (used when [Location.getLocation] stalls).
  loc.LocationData? recentTrackerFix({
    Duration maxAge = const Duration(minutes: 45),
  }) {
    final last = _lastAccepted;
    final t = _lastEmitTime;
    if (last == null || t == null) return null;
    if (last.latitude == null || last.longitude == null) return null;
    if (DateTime.now().difference(t) > maxAge) return null;
    return last;
  }

  static const double _maxAccuracyM = 80;
  static const double _minRepeatM = 3;
  static const int _minRepeatMs = 2500;

  Future<void> startOrUpdateSession({
    required String requestId,
    required String legId,
    required String sessionId,
    TrackingPace pace = TrackingPace.traveling,
  }) async {
    if (!AppConstants.featureLiveGpsTracking) return;

    final permission = await _location.hasPermission();
    if (permission != loc.PermissionStatus.granted &&
        permission != loc.PermissionStatus.grantedLimited) {
      return;
    }

    final sessionChanged = _requestId != requestId || _sessionId != sessionId;
    if (sessionChanged) {
      _kalmanFilter.reset();
      _lastAccepted = null;
      _lastEmitTime = null;
      _lastPointId = null;
      _prevAccepted = null;
      _prevEmitTime = null;
      _prevPointId = null;
    }

    _requestId = requestId;
    _legId = legId;
    _sessionId = sessionId;
    _pace = pace;

    // Seed last accepted from Hive so post-kill resume rejects teleports.
    if (_lastAccepted == null) {
      await _seedLastAcceptedFromHive(requestId);
    }

    await _applySettings(_pace);
    try {
      final bgOk = await _location.enableBackgroundMode(enable: true);
      if (bgOk != true) {
        // Still track in foreground; background may be denied on some devices.
      }
    } catch (e) {
      debugPrint('Background location mode enable failed: $e');
    }

    if (ServiceLocator.I.has<WebSocketTrackingService>()) {
      final ws = ServiceLocator.I.get<WebSocketTrackingService>();
      if (!ws.isConnected) {
        unawaited(ws.connect());
      }
    }

    await _subscription?.cancel();
    _subscription = _location.onLocationChanged.listen(
      _onLocation,
      onError: (e) => debugPrint('Location stream error: $e'),
    );
  }

  Future<void> setPace(TrackingPace pace) async {
    if (!AppConstants.featureLiveGpsTracking) return;
    if (_pace == pace) return;
    _pace = pace;
    await _applySettings(_pace);
  }

  Future<void> setActiveLeg(String legId) async {
    _legId = legId;
  }

  /// Inserts a marker point (meeting start/end) with current fix.
  Future<void> recordStopMarker({
    required bool isStopMarker,
    required loc.LocationData data,
  }) async {
    if (!AppConstants.featureLiveGpsTracking) return;
    if (_requestId == null || _legId == null || _sessionId == null) return;
    await _persistPoint(
      data,
      isMoving: false,
      isStopMarker: isStopMarker,
    );
  }

  Future<void> stopAll() async {
    await _subscription?.cancel();
    _subscription = null;
    _kalmanFilter.reset();
    // On some devices this never completes and blocks the UI thread of punch flow.
    try {
      await _location
          .enableBackgroundMode(enable: false)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore: stream is already stopped; app can still finish the punch.
    }
    _requestId = null;
    _legId = null;
    _sessionId = null;
    _lastAccepted = null;
    _lastEmitTime = null;
    _lastPointId = null;
    _prevAccepted = null;
    _prevEmitTime = null;
    _prevPointId = null;
    pointsBuffered.value = 0;
  }

  Future<void> _applySettings(TrackingPace pace) async {
    await _location.changeSettings(
      accuracy: loc.LocationAccuracy.high,
      interval: pace == TrackingPace.traveling ? 5000 : 25000,
      distanceFilter: pace == TrackingPace.traveling ? 8 : 35,
    );
  }

  Future<void> _seedLastAcceptedFromHive(String requestId) async {
    try {
      final rows =
          await HiveDatabase.instance.getRoutePointsForRequest(requestId);
      if (rows.isEmpty) return;
      // Walk from newest for a valid non-teleport seed.
      for (var i = rows.length - 1; i >= 0; i--) {
        final lat = (rows[i]['latitude'] as num?)?.toDouble();
        final lng = (rows[i]['longitude'] as num?)?.toDouble();
        final acc = (rows[i]['accuracy'] as num?)?.toDouble() ?? 30;
        if (lat == null || lng == null) continue;
        final decision = GpsJumpGate.evaluate(
          lat: lat,
          lng: lng,
          accuracyM: acc,
          timestamp: DateTime.now(),
        );
        if (!decision.accepted) continue;
        final ts = GpsGapRoadFill.parseTimestamp(rows[i]['timestamp']);
        _lastAccepted = loc.LocationData.fromMap({
          'latitude': lat,
          'longitude': lng,
          'accuracy': acc,
          'speed': (rows[i]['speed'] as num?)?.toDouble() ?? 0,
          'heading': (rows[i]['heading'] as num?)?.toDouble() ?? 0,
        });
        // Must use Hive timestamp — DateTime.now() made kill gaps look like 0s.
        _lastEmitTime = ts ?? DateTime.now();
        return;
      }
    } catch (e) {
      debugPrint('seedLastAcceptedFromHive failed: $e');
    }
  }

  Future<void> _onLocation(loc.LocationData data) async {
    if (_requestId == null || _legId == null || _sessionId == null) return;
    if (!AppConstants.featureLiveGpsTracking) return;

    final lat = data.latitude;
    final lng = data.longitude;
    if (lat == null || lng == null) return;

    final acc = data.accuracy ?? 10.0;
    if (acc > _maxAccuracyM) return;

    final now = DateTime.now();
    final rawSpeed = data.speed;

    // Reject teleports / indoor drift BEFORE Kalman so filter state stays clean.
    final last = _lastAccepted;
    final gate = GpsJumpGate.evaluate(
      lat: lat,
      lng: lng,
      accuracyM: acc,
      timestamp: now,
      speedMps: rawSpeed,
      prevLat: last?.latitude,
      prevLng: last?.longitude,
      prevTimestamp: _lastEmitTime,
    );
    if (!gate.accepted) {
      // Hard teleport: reset Kalman so next good fix isn't pulled toward junk.
      if (gate.reason == 'hard_jump' || gate.reason == 'impossible_speed') {
        _kalmanFilter.reset();
      }
      debugPrint('GPS rejected: ${gate.reason}');
      return;
    }

    // App-kill / long silence resume: reset Kalman so the first fix isn't
    // pulled toward the old location, then road-fill B→C after accept.
    final isGapResume = gate.reason == 'gap_resume';
    if (isGapResume) {
      _kalmanFilter.reset();
    }

    // Apply 2D Extended Kalman Filter to raw coordinates
    final filteredResult = isGapResume
        ? <String, double>{
            'latitude': lat,
            'longitude': lng,
            'speedMps': rawSpeed ?? 0.0,
          }
        : _kalmanFilter.process(
            latitude: lat,
            longitude: lng,
            timestamp: now,
            accuracy: acc,
          );

    final filteredLat = filteredResult['latitude']!;
    final filteredLng = filteredResult['longitude']!;
    final estimatedSpeed = filteredResult['speedMps'] ?? data.speed ?? 0.0;

    // Re-check filtered coords against last accepted (Kalman can lag toward jump).
    // Skip re-gate on gap_resume — we already accepted the raw hop.
    if (!isGapResume) {
      final postGate = GpsJumpGate.evaluate(
        lat: filteredLat,
        lng: filteredLng,
        accuracyM: acc,
        timestamp: now,
        speedMps: estimatedSpeed,
        prevLat: last?.latitude,
        prevLng: last?.longitude,
        prevTimestamp: _lastEmitTime,
      );
      if (!postGate.accepted) {
        _kalmanFilter.reset();
        debugPrint('GPS filtered rejected: ${postGate.reason}');
        return;
      }
    }

    final filteredData = loc.LocationData.fromMap({
      'latitude': filteredLat,
      'longitude': filteredLng,
      'accuracy': acc,
      'altitude': data.altitude,
      'speed': estimatedSpeed,
      'speed_accuracy': data.speedAccuracy,
      'heading': data.heading,
      'time': data.time,
      'isMock': data.isMock,
    });

    if (last != null && last.latitude != null && last.longitude != null) {
      final lastEmit = _lastEmitTime ?? now;
      final dt = now.difference(lastEmit);
      if (dt.inMilliseconds < _minRepeatMs) {
        final d = _haversineM(
          last.latitude!,
          last.longitude!,
          filteredLat,
          filteredLng,
        );
        if (d < _minRepeatM) return;
      }
      // Paused / indoor: require larger movement before storing.
      if (_pace == TrackingPace.paused &&
          _haversineM(
                last.latitude!,
                last.longitude!,
                filteredLat,
                filteredLng,
              ) <
              20) {
        return;
      }
    }

    final speed = filteredData.speed;
    final moving = speed == null
        ? true
        : speed.abs() > 0.4 || _pace == TrackingPace.traveling;

    // Capture previous fix before we overwrite — used for road gap-fill.
    final gapFrom = last;
    final gapFromTime = _lastEmitTime;
    final spikeAnchor = _prevAccepted;
    final spikeMidId = _lastPointId;

    final persisted = await _persistPoint(
      filteredData,
      isMoving: moving,
      isStopMarker: false,
      source: isGapResume ? 'gap_resume' : 'gps',
      timestamp: now,
    );
    if (persisted == null) return;

    // Drop urban GPS V-spikes (A→off-road B→near A) as soon as C arrives.
    if (!isGapResume &&
        spikeAnchor != null &&
        spikeAnchor.latitude != null &&
        spikeAnchor.longitude != null &&
        gapFrom != null &&
        gapFrom.latitude != null &&
        gapFrom.longitude != null &&
        spikeMidId != null &&
        _isUrbanSpike(
          aLat: spikeAnchor.latitude!,
          aLng: spikeAnchor.longitude!,
          bLat: gapFrom.latitude!,
          bLng: gapFrom.longitude!,
          cLat: filteredLat,
          cLng: filteredLng,
        )) {
      await HiveDatabase.instance.deleteRoutePoint(spikeMidId);
      debugPrint('BackgroundLocationService: retracted GPS spike $spikeMidId');
      _prevAccepted = spikeAnchor;
      _prevEmitTime = _prevEmitTime;
      _prevPointId = _prevPointId;
    } else {
      _prevAccepted = gapFrom;
      _prevEmitTime = gapFromTime;
      _prevPointId = spikeMidId;
    }

    _lastAccepted = filteredData;
    _lastEmitTime = now;
    _lastPointId = persisted.pointId;

    // Road-fill B→C after kill / GPS loss. Do not require gap_resume alone —
    // soft gaps (60s/400m) and sub-2.5km kill hops must fill too. Never await
    // Directions here (it stalled the GPS stream).
    if (gapFrom != null &&
        gapFrom.latitude != null &&
        gapFrom.longitude != null &&
        gapFromTime != null) {
      final timeDiff = now.difference(gapFromTime);
      final dist = GeoUtils.distanceMeters(
        gapFrom.latitude!,
        gapFrom.longitude!,
        filteredLat,
        filteredLng,
      );
      if (GpsGapRoadFill.isFillableGap(
        timeGap: timeDiff,
        straightLineMeters: dist,
      )) {
        debugPrint(
          'BackgroundLocationService: scheduling road fill '
          '${dist.toStringAsFixed(0)}m / ${timeDiff.inSeconds}s'
          '${isGapResume ? ' (gap_resume)' : ''}',
        );
        unawaited(
          _persistRoadFillForGap(
            fromLat: gapFrom.latitude!,
            fromLng: gapFrom.longitude!,
            fromTime: gapFromTime,
            toLat: filteredLat,
            toLng: filteredLng,
            toTime: now,
          ),
        );
      }
    }

    // Flush unsynced points (resume hop may have persisted:false on WS).
    if (!persisted.synced || isGapResume) {
      if (ServiceLocator.I.has<ConnectivityService>() &&
          ServiceLocator.I.get<ConnectivityService>().isConnected.value &&
          ServiceLocator.I.has<SyncService>()) {
        unawaited(
            ServiceLocator.I.get<SyncService>().uploadPendingRoutePoints());
      }
    }
  }

  static bool _isUrbanSpike({
    required double aLat,
    required double aLng,
    required double bLat,
    required double bLng,
    required double cLat,
    required double cLng,
  }) {
    final dPrev = GeoUtils.distanceMeters(aLat, aLng, bLat, bLng);
    final dNext = GeoUtils.distanceMeters(bLat, bLng, cLat, cLng);
    final dSkip = GeoUtils.distanceMeters(aLat, aLng, cLat, cLng);
    return dPrev > GpsGapRoadFill.spikeOutMinMeters &&
        dNext > GpsGapRoadFill.spikeOutMinMeters &&
        dSkip < GpsGapRoadFill.spikeSkipMaxMeters &&
        dSkip < dPrev * 0.45 &&
        dSkip < dNext * 0.45;
  }

  /// Inserts Google Directions midpoints between last pre-gap fix and resume fix.
  Future<void> _persistRoadFillForGap({
    required double fromLat,
    required double fromLng,
    required DateTime fromTime,
    required double toLat,
    required double toLng,
    required DateTime toTime,
  }) async {
    final reqId = _requestId;
    final legId = _legId;
    final sessId = _sessionId;
    if (reqId == null || legId == null || sessId == null) return;

    // Kill/reopen used to insert a new Directions set every time (random
    // UUIDs) → interleaved parallel "fake" roads on the map.
    if (await _gapAlreadyFilled(
      requestId: reqId,
      fromTime: fromTime,
      toTime: toTime,
    )) {
      debugPrint(
        'BackgroundLocationService: gap already has fillers — skip re-fill',
      );
      return;
    }

    final fill = await GpsGapRoadFill.fillSingleGap(
      fromLat: fromLat,
      fromLng: fromLng,
      fromTime: fromTime,
      toLat: toLat,
      toLng: toLng,
      toTime: toTime,
    );
    if (fill == null || fill.midpoints.isEmpty) return;

    final gapKey =
        '${fromTime.toUtc().millisecondsSinceEpoch}_'
        '${toTime.toUtc().millisecondsSinceEpoch}';
    for (var i = 0; i < fill.midpoints.length; i++) {
      final mid = fill.midpoints[i];
      final point = RoutePointModel(
        pointId: 'gapfill_${reqId}_${gapKey}_$i',
        requestId: reqId,
        legId: legId,
        sessionId: sessId,
        timestamp: mid.time ?? fromTime,
        latitude: mid.lat,
        longitude: mid.lng,
        accuracy: 10.0,
        speed: 0.0,
        heading: 0.0,
        altitude: 0.0,
        isMoving: true,
        isStopMarker: false,
        source: GpsGapRoadFill.fillerSource,
        isSynced: false,
      );
      await HiveDatabase.instance.saveRoutePoint(point.toHiveMap());
    }
    pointsBuffered.value++;
    debugPrint(
      'BackgroundLocationService: persisted ${fill.midpoints.length} '
      'gap-filler points (${fill.roadMeters.toStringAsFixed(0)}m road)',
    );

    if (ServiceLocator.I.has<ConnectivityService>() &&
        ServiceLocator.I.get<ConnectivityService>().isConnected.value &&
        ServiceLocator.I.has<SyncService>()) {
      unawaited(ServiceLocator.I.get<SyncService>().uploadPendingRoutePoints());
    }
  }

  /// True when Hive already has Directions midpoints inside this silence window.
  Future<bool> _gapAlreadyFilled({
    required String requestId,
    required DateTime fromTime,
    required DateTime toTime,
  }) async {
    try {
      final rows =
          await HiveDatabase.instance.getRoutePointsForRequest(requestId);
      final from = fromTime.toUtc();
      final to = toTime.toUtc();
      var fillerCount = 0;
      for (final m in rows) {
        if (m['source']?.toString() != GpsGapRoadFill.fillerSource) continue;
        final t = GpsGapRoadFill.parseTimestamp(m['timestamp'])?.toUtc();
        if (t == null) continue;
        if (t.isAfter(from) && t.isBefore(to)) fillerCount++;
        if (fillerCount >= 2) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<({bool synced, String pointId})?> _persistPoint(
    loc.LocationData data, {
    required bool isMoving,
    required bool isStopMarker,
    String source = 'gps',
    DateTime? timestamp,
  }) async {
    final lat = data.latitude;
    final lng = data.longitude;
    if (lat == null || lng == null) return null;
    final pointId = const Uuid().v4();
    final ts = timestamp ?? DateTime.now();

    final reqId = _requestId;
    final legId = _legId;
    final sessId = _sessionId;
    if (reqId == null || legId == null || sessId == null) return null;

    var pointSynced = false;
    final ws = ServiceLocator.I.has<WebSocketTrackingService>()
        ? ServiceLocator.I.get<WebSocketTrackingService>()
        : null;

    if (ws != null) {
      if (!ws.isConnected && !ws.isBackendUnavailable) {
        unawaited(ws.connect());
      }
      if (ws.isConnected) {
        String? userId;
        if (ServiceLocator.I.has<AppAuthController>()) {
          userId = ServiceLocator.I.get<AppAuthController>().currentUserApiId;
        }
        pointSynced = await ws.emitLocationUpdate(
          tripId: reqId,
          latitude: lat,
          longitude: lng,
          timestamp: ts,
          speed: data.speed,
          bearing: data.heading,
          accuracy: data.accuracy,
          pointId: pointId,
          requestId: reqId,
          legId: legId,
          sessionId: sessId,
          source: source,
          userId: userId,
        );
      }
    }

    final point = RoutePointModel(
      pointId: pointId,
      requestId: reqId,
      legId: legId,
      sessionId: sessId,
      timestamp: ts,
      latitude: lat,
      longitude: lng,
      accuracy: data.accuracy,
      speed: data.speed,
      heading: data.heading,
      altitude: data.altitude,
      isMoving: isMoving,
      isStopMarker: isStopMarker,
      source: source,
      isSynced: pointSynced,
    );

    await HiveDatabase.instance.saveRoutePoint(point.toHiveMap());
    pointsBuffered.value++;
    return (synced: pointSynced, pointId: pointId);
  }

  static double _haversineM(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _rad(double d) => d * math.pi / 180;
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:location/location.dart' as loc;
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../database/hive_database.dart';
import '../../modules/travel/data/models/route_point_model.dart';
import '../di/service_locator.dart';
import '../../features/tracking/data/services/websocket_tracking_service.dart';
import 'connectivity_service.dart';
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

  loc.LocationData? _lastAccepted;
  DateTime? _lastEmitTime;
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

  static const double _maxAccuracyM = 100;
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

    _requestId = requestId;
    _legId = legId;
    _sessionId = sessionId;
    _pace = pace;

    await _applySettings(_pace);
    try {
      final bgOk = await _location.enableBackgroundMode(enable: true);
      if (bgOk != true) {
        // Still track in foreground; background may be denied on some devices.
      }
    } catch (e) {
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
    pointsBuffered.value = 0;
  }

  Future<void> _applySettings(TrackingPace pace) async {
    await _location.changeSettings(
      accuracy: loc.LocationAccuracy.high,
      interval: pace == TrackingPace.traveling ? 5000 : 25000,
      distanceFilter: pace == TrackingPace.traveling ? 8 : 35,
    );
  }

  Future<void> _onLocation(loc.LocationData data) async {
    if (_requestId == null || _legId == null || _sessionId == null) return;
    if (!AppConstants.featureLiveGpsTracking) return;

    final lat = data.latitude;
    final lng = data.longitude;
    if (lat == null || lng == null) return;

    final acc = data.accuracy;
    if (acc != null && acc > _maxAccuracyM) return;

    final now = DateTime.now();
    final last = _lastAccepted;
    if (last != null && last.latitude != null && last.longitude != null) {
      final lastEmit = _lastEmitTime ?? now;
      final dt = now.difference(lastEmit);
      if (dt.inMilliseconds < _minRepeatMs) {
        final d = _haversineM(
          last.latitude!,
          last.longitude!,
          lat,
          lng,
        );
        if (d < _minRepeatM) return;
      }
    }

    final speed = data.speed;
    final moving = speed == null
        ? true
        : speed.abs() > 0.4 || _pace == TrackingPace.traveling;

    final synced = await _persistPoint(
      data,
      isMoving: moving,
      isStopMarker: false,
    );
    _lastAccepted = data;
    _lastEmitTime = now;

    // Opportunistic sync when online (non-blocking) and not synced via WS.
    if (!synced) {
      if (ServiceLocator.I.has<ConnectivityService>() &&
          ServiceLocator.I.get<ConnectivityService>().isConnected.value &&
          ServiceLocator.I.has<SyncService>()) {
        unawaited(ServiceLocator.I.get<SyncService>().uploadPendingRoutePoints());
      }
    }
  }

  Future<bool> _persistPoint(
    loc.LocationData data, {
    required bool isMoving,
    required bool isStopMarker,
  }) async {
    final lat = data.latitude;
    final lng = data.longitude;
    if (lat == null || lng == null) return false;
    final pointId = const Uuid().v4();
    final now = DateTime.now();

    final reqId = _requestId;
    final legId = _legId;
    final sessId = _sessionId;
    if (reqId == null || legId == null || sessId == null) return false;

    var pointSynced = false;
    final ws = ServiceLocator.I.has<WebSocketTrackingService>()
        ? ServiceLocator.I.get<WebSocketTrackingService>()
        : null;

    if (ws != null) {
      if (!ws.isConnected && !ws.isBackendUnavailable) {
        unawaited(ws.connect());
      }
      if (ws.isConnected) {
        pointSynced = await ws.emitLocationUpdate(
          tripId: reqId,
          latitude: lat,
          longitude: lng,
          timestamp: now,
          speed: data.speed,
          bearing: data.heading,
          accuracy: data.accuracy,
          pointId: pointId,
          requestId: reqId,
          legId: legId,
          sessionId: sessId,
        );
      }
    }

    final point = RoutePointModel(
      pointId: pointId,
      requestId: reqId,
      legId: legId,
      sessionId: sessId,
      timestamp: now,
      latitude: lat,
      longitude: lng,
      accuracy: data.accuracy,
      speed: data.speed,
      heading: data.heading,
      altitude: data.altitude,
      isMoving: isMoving,
      isStopMarker: isStopMarker,
      source: 'gps',
      isSynced: pointSynced,
    );

    await HiveDatabase.instance.saveRoutePoint(point.toHiveMap());
    pointsBuffered.value++;
    return pointSynced;
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

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../database/hive_database.dart';
import '../di/service_locator.dart';
import '../../modules/travel/data/models/tracking_event_model.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

/// Records tracking lifecycle events locally and uploads when online.
class TrackingEventService {
  TrackingEventService({
    HiveDatabase? hive,
    ConnectivityService? connectivity,
  })  : _hive = hive ?? HiveDatabase.instance,
        _connectivity = connectivity;

  final HiveDatabase _hive;
  final ConnectivityService? _connectivity;

  String? _activeRequestId;
  String? _activeLegId;
  String? _activeSessionId;
  bool? _lastNetworkOnline;

  void bindActiveTrip({
    required String requestId,
    String? legId,
    String? sessionId,
  }) {
    _activeRequestId = requestId;
    _activeLegId = legId;
    _activeSessionId = sessionId;
  }

  void clearActiveTrip() {
    _activeRequestId = null;
    _activeLegId = null;
    _activeSessionId = null;
  }

  Future<void> record({
    required String requestId,
    required String type,
    String? legId,
    String? sessionId,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) async {
    if (requestId.isEmpty) return;

    final event = TrackingEventModel.create(
      requestId: requestId,
      type: type,
      legId: legId ?? _activeLegId,
      sessionId: sessionId ?? _activeSessionId,
      metadata: metadata,
      timestamp: timestamp,
    );

    await _hive.saveTrackingEvent(event.toHiveMap());

    if (_connectivity?.isConnected.value == true &&
        ServiceLocator.I.has<SyncService>()) {
      unawaited(ServiceLocator.I.get<SyncService>().uploadPendingTrackingEvents());
    }
  }

  Future<void> onTrackingStarted({
    required String requestId,
    required String legId,
    required String sessionId,
  }) async {
    bindActiveTrip(
      requestId: requestId,
      legId: legId,
      sessionId: sessionId,
    );
    await record(
      requestId: requestId,
      type: TrackingEventTypes.trackingStarted,
      legId: legId,
      sessionId: sessionId,
    );
  }

  Future<void> onTrackingStopped({
    required String requestId,
    String? legId,
    String? sessionId,
  }) async {
    await record(
      requestId: requestId,
      type: TrackingEventTypes.trackingStopped,
      legId: legId ?? _activeLegId,
      sessionId: sessionId ?? _activeSessionId,
    );
    clearActiveTrip();
  }

  Future<void> onAppBackground() async {
    final id = _activeRequestId;
    if (id == null) return;
    await record(requestId: id, type: TrackingEventTypes.appBackground);
  }

  Future<void> onAppForeground() async {
    final id = _activeRequestId;
    if (id == null) return;
    await record(requestId: id, type: TrackingEventTypes.appForeground);
  }

  Future<void> onNetworkChanged(bool isOnline) async {
    if (_lastNetworkOnline == isOnline) return;
    _lastNetworkOnline = isOnline;
    final id = _activeRequestId;
    if (id == null) return;
    await record(
      requestId: id,
      type: isOnline
          ? TrackingEventTypes.networkOnline
          : TrackingEventTypes.networkOffline,
    );
  }

  Future<void> onPermissionDenied({required String requestId}) async {
    await record(
      requestId: requestId,
      type: TrackingEventTypes.permissionDenied,
    );
  }

  /// Call after app restart when an active trip resumes but GPS stream was lost.
  Future<void> checkOsKillSuspected({
    required String requestId,
    required bool trackingWasActive,
  }) async {
    if (!trackingWasActive) return;

    final lastPoint = await _hive.lastRoutePointTimestamp(requestId);
    if (lastPoint == null) return;

    final gap = DateTime.now().toUtc().difference(lastPoint);
    if (gap.inSeconds < AppConstants.trackingGapThresholdSeconds) return;

    await record(
      requestId: requestId,
      type: TrackingEventTypes.osKillSuspected,
      metadata: {
        'lastPointAt': lastPoint.toUtc().toIso8601String(),
        'resumedAt': DateTime.now().toUtc().toIso8601String(),
        'gapSeconds': gap.inSeconds,
      },
    );
  }
}

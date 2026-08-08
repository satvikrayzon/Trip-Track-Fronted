import 'dart:async';

import 'package:flutter/widgets.dart';

import '../database/hive_database.dart';
import '../di/service_locator.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'background_location_service.dart';
import 'punch_reminder_service.dart';
import 'tracking_event_service.dart';
import 'tracking_session_service.dart';
import '../../features/tracking/data/services/websocket_tracking_service.dart';

/// Forwards app lifecycle to [TrackingEventService] during active trips.
class TrackingLifecycleBinder extends WidgetsBindingObserver {
  TrackingLifecycleBinder._();
  static final TrackingLifecycleBinder instance = TrackingLifecycleBinder._();

  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  TrackingEventService? get _events =>
      ServiceLocator.I.has<TrackingEventService>()
          ? ServiceLocator.I.get<TrackingEventService>()
          : null;

  PunchReminderService? get _reminders =>
      ServiceLocator.I.has<PunchReminderService>()
          ? ServiceLocator.I.get<PunchReminderService>()
          : null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final events = _events;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (events != null) unawaited(events.onAppBackground());
      case AppLifecycleState.resumed:
        if (events != null) unawaited(events.onAppForeground());
        final reminders = _reminders;
        if (reminders != null) unawaited(reminders.checkNow());
        unawaited(_resumeLiveTrackingIfNeeded());
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// After kill/background, OS may drop the location stream while Dart still
  /// thinks a subscription exists — or WS rooms need rejoining.
  Future<void> _resumeLiveTrackingIfNeeded() async {
    if (!ServiceLocator.I.has<BackgroundLocationService>()) return;
    if (!ServiceLocator.I.has<TrackingSessionService>()) return;

    final bg = ServiceLocator.I.get<BackgroundLocationService>();
    final session = ServiceLocator.I.get<TrackingSessionService>();

    if (ServiceLocator.I.has<WebSocketTrackingService>()) {
      final ws = ServiceLocator.I.get<WebSocketTrackingService>();
      if (!ws.isConnected) {
        unawaited(ws.connect());
      }
    }

    final trip = await _cachedActiveTrip();
    if (trip == null) return;

    final tracking = trip.status == 'Travelling' ||
        trip.status == 'Returning' ||
        trip.trackingStatus == 'tracking';
    if (!tracking) return;

    final staleFix = bg.recentTrackerFix(maxAge: const Duration(seconds: 90));
    final needsRestart = !bg.isRunning || staleFix == null;
    if (!needsRestart) {
      // Re-assert session ids / WS even when stream looks alive.
      if (bg.activeRequestId != null &&
          bg.activeRequestId!.isNotEmpty &&
          (bg.activeRequestId == trip.requestId ||
              bg.activeRequestId == trip.restResourceId)) {
        return;
      }
    }

    final requestId =
        trip.requestId.isNotEmpty ? trip.requestId : trip.restResourceId;
    final legId = trip.activeLeg?.legId ??
        (trip.tripLegs.isNotEmpty ? trip.tripLegs.first.legId : '');
    final sessionId = trip.trackingSessionId ?? '';
    if (requestId.isEmpty || legId.isEmpty) return;

    await session.onTravelDeparture(
      requestId: requestId,
      legId: legId,
      sessionId: sessionId.isNotEmpty ? sessionId : requestId,
    );
  }

  Future<TravelRequestModel?> _cachedActiveTrip() async {
    final id = HiveDatabase.instance.getActiveTripIdSync();
    if (id == null || id.isEmpty) return null;
    try {
      final rows = await HiveDatabase.instance.getAllOfflineTravelRequests();
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row);
        final rid = map['requestId']?.toString() ?? '';
        final mongo = map['_id']?.toString() ?? '';
        final tripId = map['tripId']?.toString() ?? map['id']?.toString() ?? '';
        if (rid == id || mongo == id || tripId == id) {
          return TravelRequestModel.fromMap(map).ensureTripLegs();
        }
      }
    } catch (_) {}
    return null;
  }
}

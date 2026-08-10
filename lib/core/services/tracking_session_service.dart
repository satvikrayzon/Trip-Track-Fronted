import 'package:geolocator/geolocator.dart';

import '../constants/app_constants.dart';
import '../di/service_locator.dart';
import 'background_location_service.dart';
import 'tracking_event_service.dart';

/// High-level live trip session: ties request/leg to [BackgroundLocationService].
class TrackingSessionService {
  TrackingSessionService({BackgroundLocationService? background})
      : _bg = background ?? ServiceLocator.I.get<BackgroundLocationService>();

  final BackgroundLocationService _bg;

  Future<void> onTravelDeparture({
    required String requestId,
    required String legId,
    required String sessionId,
  }) async {
    if (!AppConstants.featureLiveGpsTracking) return;
    await _bg.startOrUpdateSession(
      requestId: requestId,
      legId: legId,
      sessionId: sessionId,
      pace: TrackingPace.traveling,
    );
    if (ServiceLocator.I.has<TrackingEventService>()) {
      await ServiceLocator.I.get<TrackingEventService>().onTrackingStarted(
            requestId: requestId,
            legId: legId,
            sessionId: sessionId,
          );
    }
  }

  Future<void> onTravelArrivalPaused() async {
    if (!AppConstants.featureLiveGpsTracking) return;
    await _bg.setPace(TrackingPace.paused);
  }

  Future<void> onNextLegDeparture(String legId) async {
    if (!AppConstants.featureLiveGpsTracking) return;
    await _bg.setActiveLeg(legId);
    await _bg.setPace(TrackingPace.traveling);
  }

  Future<void> recordMeetingStopMarker({required bool isStopMarker}) async {
    if (!AppConstants.featureLiveGpsTracking) return;
    if (!_bg.isRunning) return;
    // Prefer the live tracker's own recent fix (already Kalman-filtered) —
    // fall back to a fresh one-shot read only if the stream is momentarily dry.
    final data = _bg.recentTrackerFix(maxAge: const Duration(seconds: 30)) ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
    await _bg.recordStopMarker(isStopMarker: isStopMarker, data: data);
  }

  Future<void> endEntireTrip() async {
    final requestId = _bg.activeRequestId;
    final legId = _bg.activeLegId;
    final sessionId = _bg.activeSessionId;
    await _bg.stopAll();
    if (requestId != null &&
        requestId.isNotEmpty &&
        ServiceLocator.I.has<TrackingEventService>()) {
      await ServiceLocator.I.get<TrackingEventService>().onTrackingStopped(
            requestId: requestId,
            legId: legId,
            sessionId: sessionId,
          );
    }
  }
}

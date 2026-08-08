import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/app_constants.dart';
import '../di/service_locator.dart';
import '../utils/geo_utils.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'notification_service.dart';
import 'punch_location_service.dart';

enum PunchReminderKind {
  /// Inside start geofence; departure not punched yet.
  departureNearStart,

  /// Still inside start geofence but near the 500m edge.
  departureLeavingZone,

  /// Outside start geofence without departure — must return (no tracking).
  departureOutsideZone,

  /// Inside destination geofence; arrival not punched yet.
  arrivalNearDestination,

  /// Dwelt at destination without marking arrival.
  arrivalStillAtDestination,

  /// Left destination geofence without arrival punch (tracking still on).
  arrivalLeftWithoutPunch,
}

class PunchReminderState {
  const PunchReminderState({
    required this.kind,
    required this.title,
    required this.message,
    required this.distanceMeters,
    required this.radiusMeters,
    required this.isUrgent,
    required this.requestId,
  });

  final PunchReminderKind kind;
  final String title;
  final String message;
  final double distanceMeters;
  final double radiusMeters;
  final bool isUrgent;
  final String requestId;
}

/// Watches an active trip and nudges the user to punch while still inside the
/// 500m start/end geofence. Never starts tracking or invents km for forgotten punches.
class PunchReminderService {
  PunchReminderService({
    PunchLocationService? punchLocation,
    NotificationService? notifications,
  })  : _punchLocation =
            punchLocation ?? ServiceLocator.I.get<PunchLocationService>(),
        _notifications = notifications ?? NotificationService.instance;

  final PunchLocationService _punchLocation;
  final NotificationService _notifications;

  final ValueNotifier<PunchReminderState?> reminder =
      ValueNotifier<PunchReminderState?>(null);

  Timer? _timer;
  TravelRequestModel? _trip;
  bool _tickRunning = false;

  bool? _wasInsideStart;
  bool? _wasInsideDest;
  DateTime? _insideDestSince;

  PunchReminderKind? _lastNotifiedKind;
  DateTime? _lastNotifiedAt;

  void watch(TravelRequestModel? trip) {
    if (trip == null || trip.status == AppConstants.statusCompleted) {
      clear();
      return;
    }

    final next = trip.nextPunchTypeForActiveLeg;
    final needsWatch =
        next == 'travel_departure' || next == 'travel_arrival';
    if (!needsWatch) {
      clear();
      return;
    }

    final sameTrip = _trip?.requestId == trip.requestId &&
        _trip?.restResourceId == trip.restResourceId;
    final samePunch = sameTrip &&
        _trip?.nextPunchTypeForActiveLeg == next &&
        _trip?.activeLeg?.legId == trip.activeLeg?.legId;

    _trip = trip;
    if (!samePunch) {
      _wasInsideStart = null;
      _wasInsideDest = null;
      _insideDestSince = null;
      reminder.value = null;
    }

    _timer ??= Timer.periodic(
      AppConstants.punchReminderPollInterval,
      (_) => unawaited(checkNow()),
    );
    unawaited(checkNow());
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _trip = null;
    _wasInsideStart = null;
    _wasInsideDest = null;
    _insideDestSince = null;
    _lastNotifiedKind = null;
    _lastNotifiedAt = null;
    if (reminder.value != null) reminder.value = null;
  }

  void dispose() {
    clear();
    reminder.dispose();
  }

  Future<void> checkNow() async {
    final trip = _trip;
    if (trip == null || _tickRunning) return;
    _tickRunning = true;
    try {
      final next = trip.nextPunchTypeForActiveLeg;
      if (next != 'travel_departure' && next != 'travel_arrival') {
        reminder.value = null;
        return;
      }

      final ok = await _punchLocation.ensurePermissions();
      if (!ok) return;

      final position = await _punchLocation.getFastPosition(
        maxAccuracyMeters: AppConstants.punchMaxAccuracyMeters * 1.5,
      );
      if (position == null) return;

      if (next == 'travel_departure') {
        await _evaluateDeparture(trip, position);
      } else {
        await _evaluateArrival(trip, position);
      }
    } catch (e) {
    } finally {
      _tickRunning = false;
    }
  }

  Future<void> _evaluateDeparture(
    TravelRequestModel trip,
    Position position,
  ) async {
    final leg = trip.activeLeg;
    final anchor = await _punchLocation.resolveDepartureAnchor(
      request: trip,
      activeLeg: leg,
    );
    if (anchor == null) return;

    final dist = GeoUtils.distanceMeters(
      position.latitude,
      position.longitude,
      anchor['latitude']!,
      anchor['longitude']!,
    );
    const radius = AppConstants.departureGeofenceRadiusMeters;
    final inside = dist <= radius;
    final nearEdge = inside && dist >= AppConstants.punchReminderEdgeMeters;
    final originLabel = leg != null &&
            leg.sequence > 1 &&
            leg.fromLocation.trim().isNotEmpty
        ? leg.fromLocation
        : trip.fromLocation;

    PunchReminderState? state;
    if (!inside) {
      state = PunchReminderState(
        kind: PunchReminderKind.departureOutsideZone,
        title: 'Return to start to punch',
        message:
            'Start Departure only within ${radius.round()}m of $originLabel. '
            'You are ~${dist.round()}m away. Travel before punching is not counted.',
        distanceMeters: dist,
        radiusMeters: radius,
        isUrgent: true,
        requestId: trip.requestId,
      );
    } else if (nearEdge || _wasInsideStart == true && dist > radius * 0.7) {
      state = PunchReminderState(
        kind: PunchReminderKind.departureLeavingZone,
        title: 'Start Departure now',
        message:
            'You are near the ${radius.round()}m limit at $originLabel '
            '(~${dist.round()}m away). Punch before you leave — tracking starts only after this.',
        distanceMeters: dist,
        radiusMeters: radius,
        isUrgent: true,
        requestId: trip.requestId,
      );
    } else {
      state = PunchReminderState(
        kind: PunchReminderKind.departureNearStart,
        title: 'Don\'t forget Start Departure',
        message:
            'You are inside the ${radius.round()}m start zone at $originLabel. '
            'Tap Start Departure before leaving — GPS trip tracking starts only after this.',
        distanceMeters: dist,
        radiusMeters: radius,
        isUrgent: false,
        requestId: trip.requestId,
      );
    }

    _wasInsideStart = inside;
    await _publish(state);
  }

  Future<void> _evaluateArrival(
    TravelRequestModel trip,
    Position position,
  ) async {
    final leg = trip.activeLeg;
    if (leg == null) return;

    final dest = await _punchLocation.resolveDestinationCoordinates(trip, leg);
    if (dest == null) return;

    final dist = GeoUtils.distanceMeters(
      position.latitude,
      position.longitude,
      dest['latitude']!,
      dest['longitude']!,
    );
    const radius = AppConstants.arrivalGeofenceRadiusMeters;
    final inside = dist <= radius;
    final label = leg.toLocation.trim().isNotEmpty
        ? leg.toLocation
        : trip.toLocation;

    if (inside) {
      _insideDestSince ??= DateTime.now();
    } else {
      _insideDestSince = null;
    }

    PunchReminderState? state;
    if (inside) {
      final dwelt = _insideDestSince != null &&
          DateTime.now().difference(_insideDestSince!) >=
              AppConstants.punchReminderArrivalDwell;
      if (dwelt) {
        state = PunchReminderState(
          kind: PunchReminderKind.arrivalStillAtDestination,
          title: 'Mark Arrival',
          message:
              'You have been near $label for a while. '
              'Mark Arrival within ${radius.round()}m so the leg can complete.',
          distanceMeters: dist,
          radiusMeters: radius,
          isUrgent: true,
          requestId: trip.requestId,
        );
      } else {
        state = PunchReminderState(
          kind: PunchReminderKind.arrivalNearDestination,
          title: 'You are at the destination',
          message:
              'You are within ${radius.round()}m of $label '
              '(~${dist.round()}m). Tap Mark Arrival when you arrive.',
          distanceMeters: dist,
          radiusMeters: radius,
          isUrgent: false,
          requestId: trip.requestId,
        );
      }
    } else if (_wasInsideDest == true) {
      state = PunchReminderState(
        kind: PunchReminderKind.arrivalLeftWithoutPunch,
        title: 'Arrival not marked',
        message:
            'You left the ${radius.round()}m zone at $label without Mark Arrival. '
            'Return there to punch. GPS is still tracking until you do.',
        distanceMeters: dist,
        radiusMeters: radius,
        isUrgent: true,
        requestId: trip.requestId,
      );
    } else {
      // Still en route — no reminder banner.
      state = null;
    }

    _wasInsideDest = inside;
    await _publish(state);
  }

  Future<void> _publish(PunchReminderState? state) async {
    reminder.value = state;
    if (state == null) return;

    final cooldown = state.isUrgent
        ? AppConstants.punchReminderUrgentCooldown
        : AppConstants.punchReminderNotifyCooldown;
    final now = DateTime.now();
    if (_lastNotifiedKind == state.kind &&
        _lastNotifiedAt != null &&
        now.difference(_lastNotifiedAt!) < cooldown) {
      return;
    }

    // Soft near-start reminder: notify less aggressively (first time + urgents).
    if (state.kind == PunchReminderKind.departureNearStart &&
        _lastNotifiedKind == PunchReminderKind.departureNearStart) {
      return;
    }

    _lastNotifiedKind = state.kind;
    _lastNotifiedAt = now;

    final id = switch (state.kind) {
      PunchReminderKind.departureNearStart ||
      PunchReminderKind.departureLeavingZone ||
      PunchReminderKind.departureOutsideZone =>
        9101,
      PunchReminderKind.arrivalNearDestination ||
      PunchReminderKind.arrivalStillAtDestination ||
      PunchReminderKind.arrivalLeftWithoutPunch =>
        9102,
    };

    try {
      await _notifications.showNotification(
        id: id,
        title: state.title,
        body: state.message,
      );
    } catch (e) {
    }
  }
}

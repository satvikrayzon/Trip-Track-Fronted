import 'geo_utils.dart';
import '../constants/app_constants.dart';

/// Absolute teleport / physics gate for live GPS ingest.
class GpsJumpGate {
  /// Reject any single hop longer than this (meters), unless a large time gap
  /// indicates app-kill / signal loss (then allow up to [maxResumeJumpMeters]).
  static const double hardMaxJumpMeters = 2500;

  /// Max hop accepted after a long tracking silence (must match gap-fill cap).
  static const double maxResumeJumpMeters = 15000;

  /// Typical vehicle max (~162 km/h).
  static const double maxSpeedMps = 45;

  /// Ignore low-speed indoor/network drift with poor accuracy.
  static const double indoorAccuracyRejectM = 40;

  /// Stationary speed threshold (m/s).
  static const double stationarySpeedMps = 0.8;

  /// Result of evaluating a candidate fix.
  static GpsJumpDecision evaluate({
    required double lat,
    required double lng,
    required double accuracyM,
    required DateTime timestamp,
    double? speedMps,
    double? prevLat,
    double? prevLng,
    DateTime? prevTimestamp,
    bool isStopMarker = false,
  }) {
    if (!_validCoord(lat, lng)) {
      return GpsJumpDecision.reject('invalid_coordinates');
    }
    if (accuracyM > 100) {
      return GpsJumpDecision.reject('accuracy');
    }

    // Indoor / network drift: poor accuracy while nearly stationary.
    if (!isStopMarker &&
        accuracyM > indoorAccuracyRejectM &&
        (speedMps == null || speedMps.abs() < stationarySpeedMps)) {
      return GpsJumpDecision.reject('indoor_drift');
    }

    if (prevLat == null || prevLng == null || prevTimestamp == null) {
      // First fix after resume: require decent accuracy.
      if (accuracyM > 55) {
        return GpsJumpDecision.reject('cold_start_accuracy');
      }
      return GpsJumpDecision.accept();
    }

    if (!_validCoord(prevLat, prevLng)) {
      return GpsJumpDecision.accept();
    }

    final dist = GeoUtils.distanceMeters(prevLat, prevLng, lat, lng);
    final dtSec =
        timestamp.difference(prevTimestamp).inMilliseconds / 1000.0;

    // App kill / GPS silence: accept up to city-scale hops and tag gap_resume
    // so Directions can fill B→C. Previously gap_resume required dist > 2500m,
    // so typical kill gaps (400m–2km) never triggered road fill.
    if (dtSec > AppConstants.trackingGapThresholdSeconds) {
      if (dist > maxResumeJumpMeters) {
        return GpsJumpDecision.reject('hard_jump');
      }
      if (dist > 150) {
        return GpsJumpDecision.accept(reason: 'gap_resume');
      }
      return GpsJumpDecision.accept(reason: 'silence_stationary');
    }

    if (dist > hardMaxJumpMeters) {
      return GpsJumpDecision.reject('hard_jump');
    }

    if (dtSec > 0.5 && dist > 5) {
      final speed = dist / dtSec;
      if (speed > maxSpeedMps) {
        return GpsJumpDecision.reject('impossible_speed');
      }
    }

    return GpsJumpDecision.accept();
  }

  static bool _validCoord(double lat, double lng) {
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    return true;
  }
}

class GpsJumpDecision {
  final bool accepted;
  final String? reason;

  const GpsJumpDecision._(this.accepted, this.reason);

  factory GpsJumpDecision.accept({String? reason}) =>
      GpsJumpDecision._(true, reason);
  factory GpsJumpDecision.reject(String reason) =>
      GpsJumpDecision._(false, reason);
}

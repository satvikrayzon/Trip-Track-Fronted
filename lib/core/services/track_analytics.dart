import 'dart:math' as math;

import '../../modules/travel/data/models/route_point_model.dart';
import '../../modules/travel/data/models/tracking_coverage_model.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import '../constants/app_constants.dart';

/// A clean, generic GPS point model for route analytics.
class GpsPoint {
  final double latitude;
  final double longitude;
  final DateTime? timestamp;
  final double? accuracy;
  final double? speed; // speed in meters per second (m/s)

  const GpsPoint({
    required this.latitude,
    required this.longitude,
    this.timestamp,
    this.accuracy,
    this.speed,
  });
}

/// Configurable settings for GPS tracking filters across different transport modes.
class GpsTrackingConfig {
  /// Reject points with accuracy radius larger than this value in meters.
  final double maxAccuracyMeters;

  /// Ignore consecutive movements smaller than this distance to filter out stationary jitter.
  final double minSegmentMeters;

  /// Maximum physically possible speed for the travel mode in meters per second (m/s).
  final double maxSpeedMps;

  /// Multiplier to allow a margin of speed variance (e.g. 1.2 to 2.0).
  final double speedToleranceMultiplier;

  /// Absolute safety cutoff for single jumps (in meters), ignoring timestamps.
  final double hardMaxJumpMeters;

  /// Signal loss threshold. Timestamps gaps exceeding this are marked low-confidence.
  final double maxTimeGapSeconds;

  /// Whether to include straight-line distance across large signal gaps in total calculations.
  final bool includeLowConfidenceDistance;

  const GpsTrackingConfig({
    required this.maxAccuracyMeters,
    required this.minSegmentMeters,
    required this.maxSpeedMps,
    required this.speedToleranceMultiplier,
    required this.hardMaxJumpMeters,
    required this.maxTimeGapSeconds,
    this.includeLowConfidenceDistance = true,
  });

  /// Walking tracking preset.
  factory GpsTrackingConfig.walking() => const GpsTrackingConfig(
        maxAccuracyMeters: 30.0,
        minSegmentMeters: 2.0,
        maxSpeedMps: 5.0, // ~18 km/h
        speedToleranceMultiplier: 1.2,
        hardMaxJumpMeters: 100.0,
        maxTimeGapSeconds: 90.0,
        includeLowConfidenceDistance: true,
      );

  /// Cycling tracking preset.
  factory GpsTrackingConfig.cycling() => const GpsTrackingConfig(
        maxAccuracyMeters: 40.0,
        minSegmentMeters: 4.0,
        maxSpeedMps: 15.0, // ~54 km/h
        speedToleranceMultiplier: 1.3,
        hardMaxJumpMeters: 300.0,
        maxTimeGapSeconds: 120.0,
        includeLowConfidenceDistance: true,
      );

  /// Motorbike/Scooter tracking preset.
  factory GpsTrackingConfig.bike() => const GpsTrackingConfig(
        maxAccuracyMeters: 60.0,
        minSegmentMeters: 6.0,
        maxSpeedMps: 35.0, // ~126 km/h
        speedToleranceMultiplier: 1.5,
        hardMaxJumpMeters: 1000.0,
        maxTimeGapSeconds: 180.0,
        includeLowConfidenceDistance: true,
      );

  /// Standard car driving preset.
  factory GpsTrackingConfig.car() => const GpsTrackingConfig(
        maxAccuracyMeters: 80.0,
        minSegmentMeters: 8.0,
        maxSpeedMps: 45.0, // ~162 km/h
        speedToleranceMultiplier: 1.8,
        hardMaxJumpMeters: 2000.0,
        maxTimeGapSeconds: 240.0,
        includeLowConfidenceDistance: true,
      );

  /// Stop-and-go delivery route preset.
  factory GpsTrackingConfig.delivery() => const GpsTrackingConfig(
        maxAccuracyMeters: 70.0,
        minSegmentMeters: 6.0,
        maxSpeedMps: 40.0, // ~144 km/h
        speedToleranceMultiplier: 1.6,
        hardMaxJumpMeters: 1500.0,
        maxTimeGapSeconds: 180.0,
        includeLowConfidenceDistance: true,
      );

  /// Forest, remote, or offline tracking preset (relaxed accuracy constraints).
  factory GpsTrackingConfig.forestOffline() => const GpsTrackingConfig(
        maxAccuracyMeters: 120.0,
        minSegmentMeters: 10.0,
        maxSpeedMps: 40.0, // ~144 km/h
        speedToleranceMultiplier: 2.0,
        hardMaxJumpMeters: 3000.0,
        maxTimeGapSeconds: 300.0,
        includeLowConfidenceDistance: true,
      );

  /// Maps string identifiers to presets. Defaults to car preset if unknown.
  factory GpsTrackingConfig.fromVehicleType(String? vehicleType) {
    if (vehicleType == null) return GpsTrackingConfig.car();
    switch (vehicleType.toLowerCase()) {
      case 'walking':
      case 'walk':
        return GpsTrackingConfig.walking();
      case 'cycling':
      case 'bicycle':
      case 'cycle':
        return GpsTrackingConfig.cycling();
      case 'bike':
      case 'scooter':
      case 'motorbike':
        return GpsTrackingConfig.bike();
      case 'delivery':
        return GpsTrackingConfig.delivery();
      case 'forest':
      case 'offline':
      case 'forest_offline':
      case 'forestoffline':
        return GpsTrackingConfig.forestOffline();
      case 'car':
      default:
        return GpsTrackingConfig.car();
    }
  }
}

/// Detailed GPS route tracking calculation result.
class RouteDistanceResult {
  final double distanceMeters;
  final double distanceKm;
  final int totalPoints;
  final int acceptedPoints;
  final int rejectedPoints;
  final int rejectedByAccuracy;
  final int rejectedByNoise;
  final int rejectedBySpeed;
  final int rejectedByJump;
  final int rejectedByInvalidTimestamp;
  final int lowConfidenceSegments;
  final bool hasLowConfidenceSegments;

  const RouteDistanceResult({
    required this.distanceMeters,
    required this.distanceKm,
    required this.totalPoints,
    required this.acceptedPoints,
    required this.rejectedPoints,
    required this.rejectedByAccuracy,
    required this.rejectedByNoise,
    required this.rejectedBySpeed,
    required this.rejectedByJump,
    required this.rejectedByInvalidTimestamp,
    required this.lowConfidenceSegments,
    required this.hasLowConfidenceSegments,
  });

  /// Empty result for fallbacks and errors.
  const RouteDistanceResult.empty()
      : distanceMeters = 0.0,
        distanceKm = 0.0,
        totalPoints = 0,
        acceptedPoints = 0,
        rejectedPoints = 0,
        rejectedByAccuracy = 0,
        rejectedByNoise = 0,
        rejectedBySpeed = 0,
        rejectedByJump = 0,
        rejectedByInvalidTimestamp = 0,
        lowConfidenceSegments = 0,
        hasLowConfidenceSegments = false;
}

/// Filters noise and aggregates accurate GPS-based route distance (not exact road distance, which needs Directions API or map matching when online) / moving vs stopped time from route points.
class TrackAnalytics {
  static const double earthRadiusKm = 6371.0;
  static const double maxAccuracyMeters = 80.0;
  static const double minSegmentMeters = 5.0;
  static const double maxJumpMeters = 500.0;
  static const double stoppedSpeedMps = 0.5;

  /// Calculates accurate GPS-based route distance and metrics over a specific time window and leg using configurable travel mode presets.
  /// Note that exact road distance requires Directions API or map matching when online.
  /// Fully backwards compatible with older parameters.
  static TrackLegMetrics computeLegMetrics({
    required List<RoutePointModel> points,
    required String legId,
    required DateTime startInclusive,
    required DateTime endInclusive,
    String? vehicleType,
    GpsTrackingConfig? config,
  }) {
    final legPoints = points
        .where((p) =>
            p.legId == legId &&
            !p.timestamp.isBefore(startInclusive) &&
            !p.timestamp.isAfter(endInclusive))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (legPoints.isEmpty) {
      return const TrackLegMetrics(
        distanceKm: 0,
        movingMinutes: 0,
        stoppedMinutes: 0,
        polylineEncoded: '',
        routeDistanceResult: RouteDistanceResult.empty(),
      );
    }

    final resolvedConfig = config ?? GpsTrackingConfig.fromVehicleType(vehicleType);

    double totalMeters = 0.0;
    int movingSeconds = 0;
    int stoppedSeconds = 0;
    int acceptedPoints = 0;
    int rejectedByAccuracy = 0;
    int rejectedByNoise = 0;
    int rejectedBySpeed = 0;
    int rejectedByJump = 0;
    int rejectedByInvalidTimestamp = 0;
    int lowConfidenceSegments = 0;

    RoutePointModel? prev;
    final coords = <List<double>>[];

    for (final p in legPoints) {
      // 1. Accuracy Check
      if (p.accuracy != null && p.accuracy! > resolvedConfig.maxAccuracyMeters) {
        rejectedByAccuracy++;
        continue;
      }

      if (prev != null) {
        final dt = p.timestamp.difference(prev.timestamp);
        final deltaSeconds = dt.inSeconds;

        // 2. Out-of-order timestamp check
        if (deltaSeconds < 0) {
          rejectedByInvalidTimestamp++;
          continue;
        }

        final dMeters = haversineMeters(
          prev.latitude,
          prev.longitude,
          p.latitude,
          p.longitude,
        );

        // 3. Absolute Hard Jump Check (backup safety filter only)
        if (dMeters > resolvedConfig.hardMaxJumpMeters) {
          rejectedByJump++;
          continue;
        }

        // 4. Timestamp-based speed & dynamic jump validation
        final speedMps = deltaSeconds > 0 ? dMeters / deltaSeconds : 0.0;
        final speed = p.speed ?? speedMps;
        if (deltaSeconds > 0) {
          final maxAllowedDistance = resolvedConfig.maxSpeedMps * deltaSeconds * resolvedConfig.speedToleranceMultiplier;
          if (dMeters > maxAllowedDistance) {
            rejectedBySpeed++;
            continue;
          }
        } else if (dMeters > 0) {
          // Time delta is zero but coordinate changed
          rejectedBySpeed++;
          continue;
        }

        // 5. Time Gap & Poor Quality Verification (Low Confidence)
        // Mark segment as low confidence if time gap exceeds threshold or if accuracy is degraded
        final bool isLowConfidence = deltaSeconds > resolvedConfig.maxTimeGapSeconds ||
            (p.accuracy != null && p.accuracy! > resolvedConfig.maxAccuracyMeters * 0.8);
        if (isLowConfidence) {
          lowConfidenceSegments++;
        }

        // 6. Noise Floor / Accumulation
        final isStopped = speed < stoppedSpeedMps;

        if (dMeters < resolvedConfig.minSegmentMeters) {
          rejectedByNoise++;
          // When below the noise floor, classify time based on state
          if (isStopped) {
            stoppedSeconds += deltaSeconds;
          } else {
            movingSeconds += deltaSeconds;
          }
        } else {
          if (isLowConfidence) {
            if (resolvedConfig.includeLowConfidenceDistance) {
              totalMeters += dMeters;
            }
          } else {
            totalMeters += dMeters;
          }

          if (isStopped) {
            stoppedSeconds += deltaSeconds;
          } else {
            movingSeconds += deltaSeconds;
          }
        }

        acceptedPoints++;
        coords.add([p.latitude, p.longitude]);
        prev = p;
      } else {
        acceptedPoints++;
        coords.add([p.latitude, p.longitude]);
        prev = p;
      }
    }

    final totalPoints = legPoints.length;
    final rejectedPoints = totalPoints - acceptedPoints;

    final routeResult = RouteDistanceResult(
      distanceMeters: totalMeters,
      distanceKm: totalMeters / 1000.0,
      totalPoints: totalPoints,
      acceptedPoints: acceptedPoints,
      rejectedPoints: rejectedPoints,
      rejectedByAccuracy: rejectedByAccuracy,
      rejectedByNoise: rejectedByNoise,
      rejectedBySpeed: rejectedBySpeed,
      rejectedByJump: rejectedByJump,
      rejectedByInvalidTimestamp: rejectedByInvalidTimestamp,
      lowConfidenceSegments: lowConfidenceSegments,
      hasLowConfidenceSegments: lowConfidenceSegments > 0,
    );

    final polyline = coords.isEmpty ? '' : _encodeSimple(coords);

    return TrackLegMetrics(
      distanceKm: routeResult.distanceKm,
      movingMinutes: (movingSeconds / 60).ceil().clamp(0, 1 << 30),
      stoppedMinutes: (stoppedSeconds / 60).ceil().clamp(0, 1 << 30),
      polylineEncoded: polyline,
      routeDistanceResult: routeResult,
    );
  }

  /// Reusable helper method to calculate accurate GPS-based route distance for a generic list of GpsPoints.
  /// Useful for offline, background, or sync logic. Note that exact road distance requires Directions API or map matching when online.
  ///
  /// Example Usage:
  /// ```dart
  /// final points = [
  ///   GpsPoint(latitude: 19.01, longitude: 72.85, timestamp: DateTime.now()),
  ///   GpsPoint(latitude: 19.02, longitude: 72.86, timestamp: DateTime.now().add(Duration(seconds: 30))),
  /// ];
  /// final config = GpsTrackingConfig.car();
  /// final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
  /// print("Distance: ${result.distanceKm} km");
  /// ```
  static RouteDistanceResult calculateRouteDistance({
    required List<GpsPoint> points,
    required GpsTrackingConfig config,
  }) {
    if (points.isEmpty) return const RouteDistanceResult.empty();

    final sortedPoints = List<GpsPoint>.from(points)
      ..sort((a, b) {
        if (a.timestamp == null && b.timestamp == null) return 0;
        if (a.timestamp == null) return 1;
        if (b.timestamp == null) return -1;
        return a.timestamp!.compareTo(b.timestamp!);
      });

    double totalMeters = 0.0;
    int acceptedPoints = 0;
    int rejectedByAccuracy = 0;
    int rejectedByNoise = 0;
    int rejectedBySpeed = 0;
    int rejectedByJump = 0;
    int rejectedByInvalidTimestamp = 0;
    int lowConfidenceSegments = 0;

    GpsPoint? prev;

    for (final p in sortedPoints) {
      // 1. Accuracy Check
      if (p.accuracy != null && p.accuracy! > config.maxAccuracyMeters) {
        rejectedByAccuracy++;
        continue;
      }

      if (prev != null) {
        // 2. Missing Timestamp Fallback
        if (p.timestamp == null || prev.timestamp == null) {
          final dMeters = haversineMeters(
            prev.latitude,
            prev.longitude,
            p.latitude,
            p.longitude,
          );

          if (dMeters > config.hardMaxJumpMeters) {
            rejectedByJump++;
            continue;
          }

          // Mark segment as low confidence because timestamp is missing
          lowConfidenceSegments++;

          if (dMeters < config.minSegmentMeters) {
            rejectedByNoise++;
          } else {
            if (config.includeLowConfidenceDistance) {
              totalMeters += dMeters;
            }
          }
          acceptedPoints++;
          prev = p;
          continue;
        }

        final dt = p.timestamp!.difference(prev.timestamp!);
        final deltaSeconds = dt.inSeconds;

        // 3. Out-of-order timestamp check
        if (deltaSeconds < 0) {
          rejectedByInvalidTimestamp++;
          continue;
        }

        final dMeters = haversineMeters(
          prev.latitude,
          prev.longitude,
          p.latitude,
          p.longitude,
        );

        // 4. Absolute Hard Jump Check (backup safety filter only)
        if (dMeters > config.hardMaxJumpMeters) {
          rejectedByJump++;
          continue;
        }

        // 5. Timestamp-based speed & dynamic jump validation
        final speedMps = deltaSeconds > 0 ? dMeters / deltaSeconds : 0.0;
        if (deltaSeconds > 0) {
          final maxAllowedDistance = config.maxSpeedMps * deltaSeconds * config.speedToleranceMultiplier;
          if (dMeters > maxAllowedDistance) {
            rejectedBySpeed++;
            continue;
          }
        } else if (dMeters > 0) {
          rejectedBySpeed++;
          continue;
        }

        // 6. Time Gap & Poor Quality Verification (Low Confidence)
        final bool isLowConfidence = deltaSeconds > config.maxTimeGapSeconds ||
            (p.accuracy != null && p.accuracy! > config.maxAccuracyMeters * 0.8);
        if (isLowConfidence) {
          lowConfidenceSegments++;
        }

        // 7. Noise Floor / Distance Accumulation
        if (dMeters < config.minSegmentMeters) {
          rejectedByNoise++;
        } else {
          if (isLowConfidence) {
            if (config.includeLowConfidenceDistance) {
              totalMeters += dMeters;
            }
          } else {
            totalMeters += dMeters;
          }
        }

        acceptedPoints++;
        prev = p;
      } else {
        acceptedPoints++;
        prev = p;
      }
    }

    final totalPoints = points.length;
    final rejectedPoints = totalPoints - acceptedPoints;

    return RouteDistanceResult(
      distanceMeters: totalMeters,
      distanceKm: totalMeters / 1000.0,
      totalPoints: totalPoints,
      acceptedPoints: acceptedPoints,
      rejectedPoints: rejectedPoints,
      rejectedByAccuracy: rejectedByAccuracy,
      rejectedByNoise: rejectedByNoise,
      rejectedBySpeed: rejectedBySpeed,
      rejectedByJump: rejectedByJump,
      rejectedByInvalidTimestamp: rejectedByInvalidTimestamp,
      lowConfidenceSegments: lowConfidenceSegments,
      hasLowConfidenceSegments: lowConfidenceSegments > 0,
    );
  }

  /// GPS coverage between departure and arrival using point timestamp gaps.
  static TrackingCoverageLegModel computeLegCoverage({
    required TripLegModel leg,
    required List<RoutePointModel> points,
    required DateTime windowStart,
    required DateTime windowEnd,
    int gapThresholdSeconds = AppConstants.trackingGapThresholdSeconds,
  }) {
    final start = windowStart.toUtc();
    final end = windowEnd.toUtc();
    if (!end.isAfter(start)) {
      return TrackingCoverageLegModel(
        legId: leg.legId,
        legNumber: leg.sequence,
        fromLocation: leg.fromLocation,
        toLocation: leg.toLocation,
        departureAt: start,
        arrivalAt: end,
      );
    }

    final legPoints = points
        .where((p) {
          if (leg.legId.isNotEmpty && p.legId.isNotEmpty) {
            if (p.legId != leg.legId) return false;
          }
          final t = p.timestamp.toUtc();
          return !t.isBefore(start) && !t.isAfter(end);
        })
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final gaps = <TrackingGapModel>[];
    var gapSeconds = 0;

    void addGap(DateTime from, DateTime to) {
      final seconds = to.difference(from).inSeconds;
      if (seconds < gapThresholdSeconds) return;
      gapSeconds += seconds;
      gaps.add(TrackingGapModel(
        from: from,
        to: to,
        durationMinutes: (seconds / 60).ceil(),
        reason: 'no_points',
      ));
    }

    if (legPoints.isEmpty) {
      addGap(start, end);
    } else {
      addGap(start, legPoints.first.timestamp.toUtc());
      for (var i = 0; i < legPoints.length - 1; i++) {
        addGap(
          legPoints[i].timestamp.toUtc(),
          legPoints[i + 1].timestamp.toUtc(),
        );
      }
      addGap(legPoints.last.timestamp.toUtc(), end);
    }

    final expectedSeconds = end.difference(start).inSeconds;
    final trackedSeconds =
        (expectedSeconds - gapSeconds).clamp(0, expectedSeconds);
    final coverage = expectedSeconds > 0
        ? (trackedSeconds / expectedSeconds) * 100
        : 0.0;

    return TrackingCoverageLegModel(
      legId: leg.legId,
      legNumber: leg.sequence > 0 ? leg.sequence : 1,
      fromLocation: leg.fromLocation,
      toLocation: leg.toLocation,
      departureAt: start,
      arrivalAt: end,
      expectedDurationMinutes: (expectedSeconds / 60).ceil(),
      trackedDurationMinutes: (trackedSeconds / 60).ceil(),
      gapDurationMinutes: (gapSeconds / 60).ceil(),
      coveragePercent: double.parse(coverage.toStringAsFixed(1)),
      pointCount: legPoints.length,
      gaps: gaps,
    );
  }

  /// Builds coverage for all legs that have departure punch (arrival optional).
  static TrackingCoverageResult computeTripCoverage({
    required TravelRequestModel request,
    required List<RoutePointModel> points,
    int gapThresholdSeconds = AppConstants.trackingGapThresholdSeconds,
  }) {
    final legs = request.tripLegs.isEmpty
        ? request.ensureTripLegs().tripLegs
        : request.tripLegs;
    final coverageLegs = <TrackingCoverageLegModel>[];

    for (final leg in legs) {
      final departure = leg.departurePunch?.time;
      if (departure == null) continue;

      final arrival = leg.arrivalPunch?.time ?? DateTime.now().toUtc();
      coverageLegs.add(
        computeLegCoverage(
          leg: leg,
          points: points,
          windowStart: departure,
          windowEnd: arrival,
          gapThresholdSeconds: gapThresholdSeconds,
        ),
      );
    }

    return TrackingCoverageResult(
      requestId: request.requestId,
      tripId: request.tripId,
      legs: coverageLegs,
      summary: TrackingCoverageSummary.fromLegs(coverageLegs),
      source: CoverageSource.local,
    );
  }

  /// Evaluates distance in meters between two GPS coordinates using the Haversine formula.
  /// Prevents floating point issues by clamping values to valid trigonometric domains.
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusMeters = 6371000.0; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    // Clamp the parameter to asin/sqrt bounds [0.0, 1.0] to prevent floating point inaccuracies.
    final clampedA = a.clamp(0.0, 1.0);
    final c = 2 * math.atan2(math.sqrt(clampedA), math.sqrt(1 - clampedA));
    return earthRadiusMeters * c;
  }

  static double _toRad(double d) => d * math.pi / 180;

  static String _encodeSimple(List<List<double>> coords) {
    final buf = StringBuffer();
    for (var i = 0; i < coords.length; i++) {
      if (i > 0) buf.write('|');
      buf.write('${coords[i][0]},${coords[i][1]}');
    }
    return buf.toString();
  }
}

/// Data class holding metrics returned for tracking legs.
class TrackLegMetrics {
  final double distanceKm;
  final int movingMinutes;
  final int stoppedMinutes;
  final String polylineEncoded;
  final RouteDistanceResult? routeDistanceResult;

  const TrackLegMetrics({
    required this.distanceKm,
    required this.movingMinutes,
    required this.stoppedMinutes,
    required this.polylineEncoded,
    this.routeDistanceResult,
  });
}

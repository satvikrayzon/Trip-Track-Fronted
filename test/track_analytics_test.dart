import 'package:flutter_test/flutter_test.dart';
import 'package:trip_track/core/services/track_analytics.dart';
import 'package:trip_track/modules/travel/data/models/route_point_model.dart';

void main() {
  group('TrackAnalytics', () {
    test('Haversine distance correctness', () {
      // London: (51.5074, -0.1278)
      // Paris: (48.8566, 2.3522)
      // Great-circle distance is ~344 km
      final dist = TrackAnalytics.haversineMeters(51.5074, -0.1278, 48.8566, 2.3522);
      expect(dist / 1000.0, closeTo(344.0, 5.0));

      // Test clamping boundary values to ensure no NaN is returned.
      // Exact same points should be 0.0.
      final selfDist = TrackAnalytics.haversineMeters(90.0, 180.0, 90.0, 180.0);
      expect(selfDist, 0.0);
      expect(selfDist.isNaN, isFalse);

      // Extreme antipodal or polar points.
      final polarDist = TrackAnalytics.haversineMeters(-90.0, 0.0, 90.0, 0.0);
      expect(polarDist.isNaN, isFalse);
    });

    test('Total route distance calculation', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 10),
        GpsPoint(latitude: 19.001, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 30)), accuracy: 10),
        GpsPoint(latitude: 19.002, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 60)), accuracy: 10),
      ];

      final result = TrackAnalytics.calculateRouteDistance(
        points: points,
        config: GpsTrackingConfig.car(),
      );

      expect(result.distanceMeters, greaterThan(0.0));
      expect(result.acceptedPoints, 3);
      expect(result.rejectedPoints, 0);
    });

    test('Accuracy filtering', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final config = GpsTrackingConfig.walking(); // max accuracy = 30m

      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 10),
        GpsPoint(latitude: 19.0002, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 15)), accuracy: 50), // should be rejected (>30m)
        GpsPoint(latitude: 19.0004, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 30)), accuracy: 15), // accepted
      ];

      final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
      expect(result.totalPoints, 3);
      expect(result.acceptedPoints, 2);
      expect(result.rejectedByAccuracy, 1);
    });

    test('GPS noise filtering', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final config = GpsTrackingConfig.car(); // minSegmentMeters = 8m

      // Small changes representing stationary jitter (~1 meter movements)
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        GpsPoint(latitude: 19.000005, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 10)), accuracy: 5),
        GpsPoint(latitude: 19.00001, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 20)), accuracy: 5),
      ];

      final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
      expect(result.distanceMeters, 0.0);
      expect(result.rejectedByNoise, 2);
    });

    test('Speed jump rejection', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final config = GpsTrackingConfig.walking(); // maxSpeedMps = 5.0 m/s (~18 km/h), hardMaxJump = 100m

      // Move 50 meters in 2 seconds (25 m/s) -> below hardMaxJump (100m) but impossible walking speed
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        GpsPoint(latitude: 19.00045, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 2)), accuracy: 5),
      ];

      final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
      expect(result.distanceMeters, 0.0);
      expect(result.rejectedBySpeed, 1);
    });

    test('Hard jump rejection', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final config = GpsTrackingConfig.walking(); // hardMaxJumpMeters = 100m

      // Huge physical teleportation: 50 km jump
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        GpsPoint(latitude: 19.5, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 10)), accuracy: 5),
      ];

      final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
      expect(result.distanceMeters, 0.0);
      expect(result.rejectedByJump, 1);
    });

    test('Missing timestamp handling', () {
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, accuracy: 5),
        GpsPoint(latitude: 19.001, longitude: 72.0, accuracy: 5), // Missing timestamp
      ];

      // Should not crash and successfully compute distance
      final result = TrackAnalytics.calculateRouteDistance(
        points: points,
        config: GpsTrackingConfig.car(),
      );

      expect(result.distanceMeters, greaterThan(0.0));
      expect(result.acceptedPoints, 2);
    });

    test('Invalid/Out of order timestamp sorting and handling', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      
      // Chronologically out of order in the list, but sorting resolves it
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        GpsPoint(latitude: 19.001, longitude: 72.0, timestamp: t0.subtract(const Duration(seconds: 30)), accuracy: 5),
      ];

      final result = TrackAnalytics.calculateRouteDistance(
        points: points,
        config: GpsTrackingConfig.car(),
      );

      // Sorting shifts the t0-30s point first, making the order valid.
      expect(result.distanceMeters, greaterThan(0.0));
      expect(result.acceptedPoints, 2);
      expect(result.rejectedByInvalidTimestamp, 0);
    });

    test('Identical timestamps with movement are rejected by speed', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        GpsPoint(latitude: 19.001, longitude: 72.0, timestamp: t0, accuracy: 5), // Same timestamp, different location
      ];

      final result = TrackAnalytics.calculateRouteDistance(
        points: points,
        config: GpsTrackingConfig.car(),
      );

      expect(result.distanceMeters, 0.0);
      expect(result.rejectedBySpeed, 1);
    });

    test('Large time gap marked as low confidence', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final config = GpsTrackingConfig.walking(); // maxTimeGapSeconds = 90s, hardMaxJump = 100m

      // Move ~50 meters (below 100m hardMaxJump) in 120 seconds (120s > 90s gap)
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        GpsPoint(latitude: 19.00045, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 120)), accuracy: 5),
      ];

      final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
      expect(result.lowConfidenceSegments, 1);
      expect(result.hasLowConfidenceSegments, isTrue);
    });

    test('Traffic/slow movement is not rejected', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final config = GpsTrackingConfig.car(); // minSegmentMeters = 8m

      // Moving slowly: 10 meters in 10 seconds (~1 m/s = 3.6 km/h)
      // This is a typical traffic scenario
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        // ~11 meters North
        GpsPoint(latitude: 19.0001, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 10)), accuracy: 5),
      ];

      final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
      expect(result.distanceMeters, greaterThan(0.0));
      expect(result.rejectedByNoise, 0);
      expect(result.rejectedBySpeed, 0);
    });

    test('Highway delayed GPS update behavior', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final config = GpsTrackingConfig.car();
      // maxSpeedMps = 45m/s (~162 km/h)
      // deltaSeconds = 60s
      // Speed check allows up to 45 * 1.8 = 81 m/s
      // Distance is 1.5 km (1500m) -> speed is 25 m/s (~90 km/h) -> valid highway travel
      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 5),
        // ~1500 meters North
        GpsPoint(latitude: 19.0135, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 60)), accuracy: 5),
      ];

      final result = TrackAnalytics.calculateRouteDistance(points: points, config: config);
      expect(result.distanceMeters, closeTo(1500.0, 50.0));
      expect(result.acceptedPoints, 2);
      expect(result.rejectedByJump, 0);
      expect(result.rejectedBySpeed, 0);
    });

    test('Forest/offline mode relaxed behavior', () {
      final t0 = DateTime(2026, 7, 4, 12, 0, 0);
      final forestConfig = GpsTrackingConfig.forestOffline(); // maxAccuracyMeters = 120m
      final walkConfig = GpsTrackingConfig.walking(); // maxAccuracyMeters = 30m

      final points = [
        GpsPoint(latitude: 19.0, longitude: 72.0, timestamp: t0, accuracy: 100), // Degraded signal
        GpsPoint(latitude: 19.001, longitude: 72.0, timestamp: t0.add(const Duration(seconds: 30)), accuracy: 100),
      ];

      // In forest config, this should be accepted
      final forestResult = TrackAnalytics.calculateRouteDistance(points: points, config: forestConfig);
      expect(forestResult.acceptedPoints, 2);
      expect(forestResult.rejectedByAccuracy, 0);

      // In walking config, it should be rejected
      final walkResult = TrackAnalytics.calculateRouteDistance(points: points, config: walkConfig);
      expect(walkResult.acceptedPoints, 0);
      expect(walkResult.rejectedByAccuracy, 2);
    });

    test('Different vehicle type presets mapping', () {
      final configWalk = GpsTrackingConfig.fromVehicleType('walk');
      expect(configWalk.maxAccuracyMeters, 30.0);
      expect(configWalk.minSegmentMeters, 2.0);

      final configCar = GpsTrackingConfig.fromVehicleType('car');
      expect(configCar.maxAccuracyMeters, 80.0);
      expect(configCar.minSegmentMeters, 8.0);

      final configUnknown = GpsTrackingConfig.fromVehicleType('spaceship');
      expect(configUnknown.maxAccuracyMeters, 80.0); // defaults to car
    });

    test('computeLegMetrics backward compatibility and functionality', () {
      const legId = 'leg-1';
      final t0 = DateTime(2026, 7, 4, 10, 0, 0);
      final points = <RoutePointModel>[
        RoutePointModel(
          pointId: '1',
          requestId: 'r1',
          legId: legId,
          sessionId: 's1',
          timestamp: t0,
          latitude: 19.0,
          longitude: 72.0,
          accuracy: 20,
          speed: 5.0,
        ),
        RoutePointModel(
          pointId: '2',
          requestId: 'r1',
          legId: legId,
          sessionId: 's1',
          timestamp: t0.add(const Duration(seconds: 30)),
          latitude: 19.00025,
          longitude: 72.0,
          accuracy: 20,
          speed: 5.0,
        ),
      ];

      // Calling computeLegMetrics using legacy signature (with no vehicleType) should still work.
      final m = TrackAnalytics.computeLegMetrics(
        points: points,
        legId: legId,
        startInclusive: t0,
        endInclusive: t0.add(const Duration(minutes: 2)),
      );

      expect(m.distanceKm, greaterThan(0.0));
      expect(m.movingMinutes, greaterThan(0));
      expect(m.routeDistanceResult, isNotNull);
      expect(m.routeDistanceResult!.acceptedPoints, 2);
    });
  });
}

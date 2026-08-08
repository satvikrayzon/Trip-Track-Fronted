import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:trip_track/core/services/gps_gap_road_fill.dart';
import 'package:trip_track/core/services/road_aligned_route_service.dart';

void main() {
  const punch = LatLng(21.1700, 72.8300);

  group('trimGpsLeadingAwayFromAnchor', () {
    test('drops western spur before punch', () {
      final points = [
        // ~400m west of punch
        const GpsGapInputPoint(lat: 21.1700, lng: 72.8262, source: 'gps'),
        const GpsGapInputPoint(lat: 21.1700, lng: 72.8275, source: 'gps'),
        // near punch
        const GpsGapInputPoint(lat: 21.1701, lng: 72.8301, source: 'gps'),
        const GpsGapInputPoint(lat: 21.1710, lng: 72.8310, source: 'gps'),
      ];
      final trimmed = RoadAlignedRouteService.trimGpsLeadingAwayFromAnchor(
        points,
        punch,
      );
      expect(trimmed.length, lessThan(points.length));
      expect(trimmed.first.lat, closeTo(punch.latitude, 0.0001));
      expect(trimmed.first.lng, closeTo(punch.longitude, 0.0001));
      expect(trimmed.first.source, 'punch_start');
    });
  });

  group('anchorPathToPunches', () {
    test('trims leading Snap spur and pins start on punch', () {
      final path = [
        const LatLng(21.1700, 72.8260),
        const LatLng(21.1700, 72.8280),
        const LatLng(21.1700, 72.8300),
        const LatLng(21.1715, 72.8320),
      ];
      final anchored = RoadAlignedRouteService.anchorPathToPunches(
        path,
        start: punch,
      );
      expect(anchored.first.latitude, punch.latitude);
      expect(anchored.first.longitude, punch.longitude);
      expect(anchored.length, lessThan(path.length + 1));
    });
  });

  group('stripDetourLoops', () {
    test('removes rectangular side-street loop back to main road', () {
      // Main road eastbound, then a ~box into bungalows, then continue east.
      const junction = LatLng(21.2000, 72.8500);
      final path = [
        const LatLng(21.2000, 72.8480),
        junction,
        // rectangular detour (~400m+)
        const LatLng(21.2015, 72.8500), // north
        const LatLng(21.2015, 72.8515), // east
        const LatLng(21.2000, 72.8515), // south
        const LatLng(21.2000, 72.85005), // back near junction
        const LatLng(21.2000, 72.8525), // continue on main road
        const LatLng(21.2000, 72.8540),
      ];
      final cleaned = RoadAlignedRouteService.stripDetourLoops(path);
      expect(cleaned.length, lessThan(path.length));
      // Detour northern points should be gone.
      expect(
        cleaned.any((p) => (p.latitude - 21.2015).abs() < 0.0001),
        isFalse,
      );
      expect(cleaned.first.longitude, lessThan(cleaned.last.longitude));
    });
  });
}

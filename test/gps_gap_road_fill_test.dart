import 'package:flutter_test/flutter_test.dart';
import 'package:trip_track/core/services/gps_gap_road_fill.dart';

void main() {
  group('GpsGapRoadFill.isFillableGap', () {
    test('rejects normal tracking cadence (paused ~25s / 200m)', () {
      expect(
        GpsGapRoadFill.isFillableGap(
          timeGap: const Duration(seconds: 25),
          straightLineMeters: 200,
        ),
        isFalse,
      );
      expect(
        GpsGapRoadFill.isFillableGap(
          timeGap: const Duration(seconds: 35),
          straightLineMeters: 300,
        ),
        isFalse,
      );
    });

    test('rejects short teleports', () {
      expect(
        GpsGapRoadFill.isFillableGap(
          timeGap: Duration.zero,
          straightLineMeters: 776,
        ),
        isFalse,
      );
    });

    test('accepts soft kill 60s / 400m+', () {
      expect(
        GpsGapRoadFill.isFillableGap(
          timeGap: const Duration(seconds: 60),
          straightLineMeters: 400,
        ),
        isTrue,
      );
      expect(
        GpsGapRoadFill.isFillableGap(
          timeGap: const Duration(seconds: 70),
          straightLineMeters: 450,
        ),
        isTrue,
      );
    });

    test('accepts classic 90s kill', () {
      expect(
        GpsGapRoadFill.isFillableGap(
          timeGap: const Duration(seconds: 90),
          straightLineMeters: 300,
        ),
        isTrue,
      );
    });

    test('display roadify catches medium corner-cut chords', () {
      expect(GpsGapRoadFill.isDisplayRoadifyGap(45), isFalse);
      expect(GpsGapRoadFill.isDisplayRoadifyGap(60), isTrue);
      expect(GpsGapRoadFill.isDisplayRoadifyGap(180), isTrue);
    });
  });

  group('GpsGapRoadFill.stripSpikePoints', () {
    test('drops urban V-spike under 250m', () {
      final points = [
        const GpsGapInputPoint(lat: 21.1700, lng: 72.8300, source: 'gps'),
        // ~90m north off-road spike
        const GpsGapInputPoint(lat: 21.1708, lng: 72.8300, source: 'gps'),
        // back near corridor
        const GpsGapInputPoint(lat: 21.1701, lng: 72.8302, source: 'gps'),
      ];
      final cleaned = GpsGapRoadFill.stripSpikePoints(points);
      expect(cleaned.length, 2);
      expect(cleaned[0].lat, 21.1700);
      expect(cleaned[1].lat, 21.1701);
    });

    test('drops long thin out-and-back spike', () {
      final points = [
        const GpsGapInputPoint(lat: 21.1700, lng: 72.8300, source: 'gps'),
        // ~250m north
        const GpsGapInputPoint(lat: 21.1722, lng: 72.8300, source: 'gps'),
        // return almost to start (~30m offset)
        const GpsGapInputPoint(lat: 21.1702, lng: 72.8301, source: 'gps'),
      ];
      final cleaned = GpsGapRoadFill.stripSpikePoints(points);
      expect(cleaned.length, lessThan(points.length));
      expect(cleaned.first.lat, 21.1700);
      expect(cleaned.last.lat, 21.1702);
    });
  });

  group('GpsGapRoadFill.collapseDuplicateFillerRuns', () {
    test('keeps one Directions generation between GPS anchors', () {
      const filler = GpsGapRoadFill.fillerSource;
      final points = [
        const GpsGapInputPoint(lat: 21.17, lng: 72.83, source: 'gps'),
        const GpsGapInputPoint(
          lat: 21.171,
          lng: 72.831,
          source: filler,
          pointId: 'gapfill_req_1_2_0',
        ),
        const GpsGapInputPoint(
          lat: 21.172,
          lng: 72.832,
          source: filler,
          pointId: 'gapfill_req_1_2_1',
        ),
        // Second reopen generation (parallel fake road)
        const GpsGapInputPoint(
          lat: 21.1715,
          lng: 72.833,
          source: filler,
          pointId: 'gapfill_req_9_9_0',
        ),
        const GpsGapInputPoint(
          lat: 21.1725,
          lng: 72.834,
          source: filler,
          pointId: 'gapfill_req_9_9_1',
        ),
        const GpsGapInputPoint(lat: 21.173, lng: 72.835, source: 'gps'),
      ];

      final collapsed = GpsGapRoadFill.collapseDuplicateFillerRuns(points);
      final fillers =
          collapsed.where((p) => p.source == filler).toList(growable: false);
      expect(fillers.length, lessThan(4));
      expect(
        fillers.every((p) => p.pointId!.startsWith('gapfill_req_1_2')),
        isTrue,
      );
      expect(collapsed.first.source, 'gps');
      expect(collapsed.last.source, 'gps');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:trip_track/core/utils/route_point_simplify.dart';

void main() {
  test('breakLongMapEdges splits river-scale chords', () {
    // ~2km north-south hop (Surat-scale) must not stay as one polyline.
    const a = LatLng(21.22, 72.89);
    const b = LatLng(21.20, 72.89);
    final pieces = breakLongMapEdges([a, b], maxEdgeMeters: 200);
    expect(pieces, isEmpty); // each side alone has <2 points
  });

  test('breakLongMapEdges keeps short road samples together', () {
    final pts = <LatLng>[
      const LatLng(21.1700, 72.8300),
      const LatLng(21.1705, 72.8302),
      const LatLng(21.1710, 72.8304),
    ];
    final pieces = breakLongMapEdges(pts, maxEdgeMeters: 200);
    expect(pieces, hasLength(1));
    expect(pieces.first, hasLength(3));
  });

    test('breakLongMapEdges splits mid-path long hop', () {
    final pts = <LatLng>[
      const LatLng(21.1700, 72.8300),
      const LatLng(21.1705, 72.8302),
      const LatLng(21.1900, 72.8500), // long jump
      const LatLng(21.1905, 72.8502),
    ];
    final pieces = breakLongMapEdges(pts, maxEdgeMeters: 200);
    expect(pieces.length, greaterThanOrEqualTo(2));
    for (final p in pieces) {
      expect(p.length, greaterThanOrEqualTo(2));
    }
  });

  test('live edge limit keeps sparse GPS together', () {
    // ~300m hop — broken at 200m review limit, kept at live 2500m limit.
    const a = LatLng(21.1700, 72.8300);
    const b = LatLng(21.1727, 72.8300); // ~300m north
    expect(breakLongMapEdges([a, b], maxEdgeMeters: 200), isEmpty);
    final live = breakLongMapEdges([a, b, const LatLng(21.1730, 72.8301)],
        maxEdgeMeters: kLiveMapMaxEdgeMeters);
    expect(live, hasLength(1));
  });
}

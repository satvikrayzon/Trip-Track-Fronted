import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:trip_track/core/utils/trip_route_polyline_decode.dart';

void main() {
  test('decodePipePolyline parses lat,lng pairs', () {
    final pts = decodePipePolyline('19.0,72.0|19.1,72.1');
    expect(pts.length, 2);
    expect(pts[0], const LatLng(19.0, 72.0));
    expect(pts[1], const LatLng(19.1, 72.1));
  });

  test('decodePipePolyline returns empty for null or blank', () {
    expect(decodePipePolyline(null), isEmpty);
    expect(decodePipePolyline(''), isEmpty);
    expect(decodePipePolyline('   '), isEmpty);
  });

  test('decodeGoogleEncodedPolyline decodes a short path', () {
    // Google's example polyline (two points).
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    final pts = decodeGoogleEncodedPolyline(encoded);
    expect(pts.length, greaterThanOrEqualTo(2));
    expect(pts.first.latitude, closeTo(38.5, 0.1));
    expect(pts.first.longitude, closeTo(-120.2, 0.1));
  });
}

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Reduces GPS samples for map rendering without changing the visible path much.
List<LatLng> simplifyRoutePointsForMap(
  List<LatLng> points, {
  int maxPoints = 350,
}) {
  if (points.length <= maxPoints) return points;

  final step = (points.length / maxPoints).ceil().clamp(1, points.length);
  final out = <LatLng>[];
  for (var i = 0; i < points.length; i += step) {
    out.add(points[i]);
  }
  final last = points.last;
  if (out.last.latitude != last.latitude ||
      out.last.longitude != last.longitude) {
    out.add(last);
  }
  return out;
}

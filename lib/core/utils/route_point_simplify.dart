import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'geo_utils.dart';

/// Drops GPS teleport spikes for map display.
///
/// Splits the trail on jumps > [maxJumpMeters] and keeps the longest contiguous
/// segment so a single bad Oman/ocean fix cannot paint a continent-wide line.
List<LatLng> stripTeleportSpikesForMap(
  List<LatLng> points, {
  double maxJumpMeters = 2500,
}) {
  if (points.length < 2) return points;

  final segments = <List<LatLng>>[];
  var current = <LatLng>[points.first];
  for (var i = 1; i < points.length; i++) {
    final prev = current.last;
    final next = points[i];
    final d = GeoUtils.distanceMeters(
      prev.latitude,
      prev.longitude,
      next.latitude,
      next.longitude,
    );
    if (d > maxJumpMeters) {
      segments.add(current);
      current = <LatLng>[next];
    } else {
      current.add(next);
    }
  }
  segments.add(current);

  List<LatLng> best = segments.first;
  for (final seg in segments.skip(1)) {
    if (seg.length > best.length) best = seg;
  }
  return best;
}

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

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'geo_utils.dart';

/// Hard max edge for raw / unaligned GPS (hide teleport / kill chords).
const double kMapMaxEdgeMeters = 400;

/// Live tracking: hide unfilled kill chords.
const double kLiveMapMaxEdgeMeters = 500;

/// Road-aligned polylines may have ~1km vertices on highways — but never
/// allow multi-km straight chords (app-kill river shortcuts).
const double kAlignedMapMaxEdgeMeters = 900;

/// Drops GPS teleport spikes for map display.
///
/// Splits the trail on jumps > [maxJumpMeters] and keeps the longest contiguous
/// segment so a single bad Oman/ocean fix cannot paint a continent-wide line.
List<LatLng> stripTeleportSpikesForMap(
  List<LatLng> points, {
  double maxJumpMeters = 800,
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

/// Split a path wherever consecutive points are farther than [maxEdgeMeters].
/// Returns contiguous paint-ready segments (never contains a long chord).
List<List<LatLng>> breakLongMapEdges(
  List<LatLng> points, {
  double maxEdgeMeters = kMapMaxEdgeMeters,
}) {
  if (points.isEmpty) return const [];
  if (points.length == 1) return [points];

  final out = <List<LatLng>>[];
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
    if (d > maxEdgeMeters) {
      if (current.length >= 2) out.add(current);
      current = <LatLng>[next];
    } else {
      current.add(next);
    }
  }
  if (current.length >= 2) out.add(current);
  return out;
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

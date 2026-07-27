import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Interpolates marker position for smooth Uber-style movement.
class AnimatedLatLng {
  AnimatedLatLng(this.from, this.to);

  final LatLng from;
  final LatLng to;

  LatLng at(double t) {
    return LatLng(
      lerpDouble(from.latitude, to.latitude, t)!,
      lerpDouble(from.longitude, to.longitude, t)!,
    );
  }
}

/// Bearing between two coordinates in degrees.
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLon = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Camera zoom based on speed (km/h).
double zoomForSpeed(double speedKmh) {
  if (speedKmh < 5) return 17;
  if (speedKmh < 30) return 15.5;
  if (speedKmh < 60) return 14;
  return 12.5;
}

/// Simple grid-based marker clustering for performance.
class MapClusterItem {
  MapClusterItem(this.id, this.position, this.data);

  final String id;
  final LatLng position;
  final dynamic data;
}

class MapCluster {
  MapCluster(this.center, this.items);

  final LatLng center;
  final List<MapClusterItem> items;
}

List<MapCluster> clusterMarkers({
  required List<MapClusterItem> items,
  required double zoom,
  double cellSize = 60,
}) {
  if (items.isEmpty) return [];
  if (zoom >= 15) {
    return items
        .map((i) => MapCluster(i.position, [i]))
        .toList();
  }

  final scale = math.pow(2, zoom).toDouble();
  final buckets = <String, List<MapClusterItem>>{};

  for (final item in items) {
    final x = ((item.position.longitude + 180) / 360 * scale * 256 / cellSize)
        .floor();
    final y = ((1 -
                math.log(math.tan(item.position.latitude * math.pi / 180) +
                        1 / math.cos(item.position.latitude * math.pi / 180)) /
                    math.pi) /
            2 *
            scale *
            256 /
            cellSize)
        .floor();
    final key = '$x:$y';
    buckets.putIfAbsent(key, () => []).add(item);
  }

  return buckets.values.map((group) {
    var lat = 0.0;
    var lng = 0.0;
    for (final g in group) {
      lat += g.position.latitude;
      lng += g.position.longitude;
    }
    final n = group.length;
    return MapCluster(LatLng(lat / n, lng / n), group);
  }).toList();
}

/// Animates polyline reveal along a route.
List<LatLng> visibleRoutePoints(
  List<LatLng> full,
  double progress,
) {
  if (full.isEmpty) return [];
  final count = (full.length * progress).ceil().clamp(1, full.length);
  return full.sublist(0, count);
}

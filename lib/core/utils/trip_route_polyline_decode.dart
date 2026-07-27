import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Decodes Google's encoded polyline (Directions / overview_polyline.points).
List<LatLng> decodeGoogleEncodedPolyline(String encoded) {
  if (encoded.isEmpty) return [];
  final poly = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    poly.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return poly;
}

/// Decodes our stored format `lat,lng|lat,lng|...` (from [TrackAnalytics]) to map points.
List<LatLng> decodePipePolyline(String? encoded) {
  if (encoded == null || encoded.trim().isEmpty) return [];
  final out = <LatLng>[];
  for (final part in encoded.split('|')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final coords = trimmed.split(',');
    if (coords.length < 2) continue;
    final lat = double.tryParse(coords[0].trim());
    final lng = double.tryParse(coords[1].trim());
    if (lat == null || lng == null) continue;
    out.add(LatLng(lat, lng));
  }
  return out;
}

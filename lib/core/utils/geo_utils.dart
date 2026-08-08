import 'dart:math' as math;

/// Geographic helpers (Haversine distance, etc.).
abstract final class GeoUtils {
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  /// Rejects null-island / uninitialized (0,0) and partial zeros that break geofence.
  static bool isValidLatLng(double lat, double lng) {
    if (lat.isNaN || lng.isNaN) return false;
    if (lat.abs() > 90 || lng.abs() > 180) return false;
    if (lat.abs() < 1e-5 || lng.abs() < 1e-5) return false;
    return true;
  }

  static Map<String, double>? validCoordinates(Map<String, double>? coords) {
    if (coords == null) return null;
    final lat = coords['latitude'];
    final lng = coords['longitude'];
    if (lat == null || lng == null) return null;
    if (!isValidLatLng(lat, lng)) return null;
    return {'latitude': lat, 'longitude': lng};
  }

  static double _toRadians(double degree) => degree * math.pi / 180;
}

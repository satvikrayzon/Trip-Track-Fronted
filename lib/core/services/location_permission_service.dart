import 'package:geolocator/geolocator.dart';

/// Foreground + background location for live trip tracking.
///
/// Uses Geolocator (same stack as punch GPS) so iOS permission prompts work
/// without relying on permission_handler preprocessor macros.
class LocationPermissionService {
  static Future<bool> ensureForLiveTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      if (!await Geolocator.isLocationServiceEnabled()) return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // iOS: second request can upgrade When In Use → Always for background tracking.
    if (permission == LocationPermission.whileInUse) {
      final upgraded = await Geolocator.requestPermission();
      if (upgraded == LocationPermission.always ||
          upgraded == LocationPermission.whileInUse) {
        permission = upgraded;
      }
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}

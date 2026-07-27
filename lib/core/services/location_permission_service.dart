import 'package:permission_handler/permission_handler.dart';

/// Foreground + background location for live trip tracking.
class LocationPermissionService {
  static Future<bool> ensureForLiveTracking() async {
    var whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) {
      whenInUse = await Permission.locationWhenInUse.request();
    }
    if (!whenInUse.isGranted) {
      return false;
    }

    var always = await Permission.locationAlways.status;
    if (!always.isGranted) {
      always = await Permission.locationAlways.request();
    }

    return always.isGranted || whenInUse.isGranted;
  }
}

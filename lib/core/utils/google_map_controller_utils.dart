import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Disposes a [GoogleMapController] without tripping web assertions when
/// [GoogleMap.onMapCreated] never ran.
void safeDisposeGoogleMapController(
  GoogleMapController? controller, {
  required bool mapCreated,
}) {
  if (controller == null || !mapCreated) return;
  if (kIsWeb) {
    try {
      controller.dispose();
    } catch (_) {
      // google_maps_flutter_web asserts if buildView was never called.
    }
  } else {
    controller.dispose();
  }
}

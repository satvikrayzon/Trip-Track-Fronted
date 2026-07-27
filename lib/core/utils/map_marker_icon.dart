import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Google Maps web does not support [BitmapDescriptor.defaultMarkerWithHue].
BitmapDescriptor mapMarkerIcon(double hue) {
  if (kIsWeb) return BitmapDescriptor.defaultMarker;
  return BitmapDescriptor.defaultMarkerWithHue(hue);
}

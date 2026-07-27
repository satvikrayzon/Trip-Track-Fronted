import 'dart:js_interop';

@JS('tripTrackGoogleMapsReady')
external bool? get _tripTrackGoogleMapsReady;

bool isGoogleMapsJsReady() {
  try {
    return _tripTrackGoogleMapsReady == true;
  } catch (_) {
    return false;
  }
}

import 'dart:async';

import 'package:web/web.dart' as web;

import '../config/google_maps_config.dart';
import 'google_maps_js_ready.dart';

Future<bool> ensureGoogleMapsJsLoaded() async {
  if (isGoogleMapsJsReady()) return true;
  if (!GoogleMapsConfig.isConfigured) return false;

  final existing = web.document.getElementById('trip-track-gmaps-script');
  if (existing == null) {
    final script = web.HTMLScriptElement();
    script.id = 'trip-track-gmaps-script';
    script.async = true;
    script.src =
        'https://maps.googleapis.com/maps/api/js'
        '?key=${Uri.encodeComponent(GoogleMapsConfig.apiKey)}'
        '&libraries=marker'
        '&v=beta'
        '&loading=async'
        '&callback=tripTrackOnGoogleMapsReady';
    web.document.head!.append(script);
  }

  for (var i = 0; i < 150; i++) {
    if (isGoogleMapsJsReady()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return isGoogleMapsJsReady();
}

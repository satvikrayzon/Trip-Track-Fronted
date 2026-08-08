import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as img;

/// Colored map pins that work on Android, iOS, **and web**.
///
/// Google Maps web ignores [BitmapDescriptor.defaultMarkerWithHue], so both
/// start and end would look identical (default red). We draw a small teardrop
/// PNG instead and cache by hue.
final Map<int, BitmapDescriptor> _markerIconCache = {};

BitmapDescriptor mapMarkerIcon(double hue) {
  final key = (hue % 360).round();
  return _markerIconCache.putIfAbsent(key, () => _buildPinDescriptor(hue));
}

/// Start of path — green.
BitmapDescriptor get mapStartMarkerIcon =>
    mapMarkerIcon(BitmapDescriptor.hueGreen);

/// End of path / destination — red.
BitmapDescriptor get mapEndMarkerIcon =>
    mapMarkerIcon(BitmapDescriptor.hueRed);

/// Live current location — azure.
BitmapDescriptor get mapLiveMarkerIcon =>
    mapMarkerIcon(BitmapDescriptor.hueAzure);

/// Client / meeting stop — orange.
BitmapDescriptor get mapStopMarkerIcon =>
    mapMarkerIcon(BitmapDescriptor.hueOrange);

BitmapDescriptor _buildPinDescriptor(double hue) {
  final color = HSLColor.fromAHSL(1, hue % 360, 0.85, 0.45).toColor();
  final bytes = _encodePinPng(color);
  return BitmapDescriptor.bytes(
    bytes,
    imagePixelRatio: 2,
    width: 36,
    height: 48,
  );
}

int _channel(double unit) => (unit * 255.0).round().clamp(0, 255);

Uint8List _encodePinPng(Color color) {
  const w = 72;
  const h = 96;
  final image = img.Image(width: w, height: h, numChannels: 4);

  final r = _channel(color.r);
  final g = _channel(color.g);
  final b = _channel(color.b);
  final fill = img.ColorRgba8(r, g, b, 255);
  final dark = img.ColorRgba8(
    (r * 0.65).round().clamp(0, 255),
    (g * 0.65).round().clamp(0, 255),
    (b * 0.65).round().clamp(0, 255),
    255,
  );
  final white = img.ColorRgba8(255, 255, 255, 255);

  // Circular head.
  const cx = w ~/ 2;
  const cy = 30;
  const radius = 22;
  img.fillCircle(image, x: cx, y: cy, radius: radius, color: fill);
  img.drawCircle(image, x: cx, y: cy, radius: radius, color: dark);

  // Pointed tip under the circle.
  for (var y = cy + radius - 4; y < h - 4; y++) {
    final t = (y - (cy + radius - 4)) / (h - 4 - (cy + radius - 4));
    final halfW = ((1 - t) * 16).round().clamp(1, 16);
    for (var x = cx - halfW; x <= cx + halfW; x++) {
      image.setPixel(x, y, fill);
    }
  }

  // Inner white dot (classic pin look).
  img.fillCircle(image, x: cx, y: cy, radius: 8, color: white);

  return Uint8List.fromList(img.encodePng(image));
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Prevents an underlying Google Map [HtmlElementView] from stealing pointer
/// events from Flutter overlays on web.
Widget mapWebPointerShield({
  required bool enabled,
  required Widget child,
}) {
  if (!enabled || !kIsWeb) return child;
  return PointerInterceptor(child: child);
}

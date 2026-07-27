import 'package:flutter/material.dart';

import '../layout/adaptive_layout.dart';

/// Device utility extensions and responsive helpers
extension DeviceExtension on num {
  double hPr(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final ref = h > 960 ? 840.0 : h.clamp(480.0, 960.0);
    return (this * 813) / ref;
  }

  double wPr(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final ref = w > 720 ? 420.0 : w.clamp(300.0, 720.0);
    return (this * 375) / ref;
  }

  double scp(BuildContext context) =>
      ResponsiveFont.getFontSize(context, toDouble() - 2);
}

class Device {
  static double ratio(BuildContext context) =>
      MediaQuery.of(context).size.aspectRatio;
}

class ResponsiveFont {
  static double _referenceWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= AdaptiveLayout.mediumMaxWidth) return 400;
    if (w >= AdaptiveLayout.compactMaxWidth) return 380;
    return w.clamp(300, 480);
  }

  static double getFontSize(BuildContext context, double size) {
    final width = _referenceWidth(context);
    return size * width / 375;
  }
}

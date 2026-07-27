import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/google_maps_config.dart';

/// True for Android / iOS native builds (not web, not desktop).
bool get kAppRunsOnPhoneHardware {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Native Google Maps (Android / iOS).
bool get kGoogleMapsNativeSupported => kAppRunsOnPhoneHardware;

/// Google Maps JavaScript API on Flutter web (requires script in web/index.html).
bool get kGoogleMapsWebSupported =>
    kIsWeb && GoogleMapsConfig.isConfigured;

/// Whether to render [GoogleMap] instead of the OSM fallback.
///
/// Uses Google Maps on mobile and on web when the API key is configured.
bool googleMapsSupported({bool adminOrManager = false}) {
  if (kGoogleMapsNativeSupported) return true;
  return kGoogleMapsWebSupported;
}

/// True if Google Maps is supported on the current platform (native or web).
bool get kGoogleMapsSupported => googleMapsSupported();

/// Layout buckets for one codebase on phone + tablet + desktop window.
abstract final class AdaptiveLayout {
  static const double compactMaxWidth = 600;
  static const double mediumMaxWidth = 900;
  static const double desktopContentMaxWidth = 1240;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) =>
      widthOf(context) < compactMaxWidth;

  static bool isMedium(BuildContext context) {
    final w = widthOf(context);
    return w >= compactMaxWidth && w < mediumMaxWidth;
  }

  static bool isExpanded(BuildContext context) =>
      widthOf(context) >= mediumMaxWidth;

  /// Max width for centered “app column” on large monitors.
  static double contentMaxWidth(BuildContext context) {
    final w = widthOf(context);
    if (w < compactMaxWidth) return w;
    if (w < mediumMaxWidth) return w.clamp(520, desktopContentMaxWidth);
    return desktopContentMaxWidth;
  }
}

/// Centers the entire app in a max-width column on wide screens (desktop / large web) for auth pages,
/// but passes logged-in screens through so the shell layout can stretch properly.
class AdaptiveAppFrame extends StatelessWidget {
  const AdaptiveAppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = AdaptiveLayout.widthOf(context);
    if (w < AdaptiveLayout.compactMaxWidth) {
      return child;
    }

    final maxW = AdaptiveLayout.contentMaxWidth(context);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW,
            minWidth: 0,
            maxHeight: double.infinity,
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 0,
            child: child,
          ),
        ),
      ),
    );
  }
}

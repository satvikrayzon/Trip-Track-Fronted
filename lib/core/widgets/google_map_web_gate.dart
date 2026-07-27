import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/google_maps_js_ready.dart';
import '../utils/google_maps_web_loader.dart';

/// Waits for the Google Maps JavaScript API on web before building [GoogleMap].
class GoogleMapWebGate extends StatefulWidget {
  const GoogleMapWebGate({
    super.key,
    required this.builder,
    required this.fallback,
    this.timeout = const Duration(seconds: 15),
  });

  final WidgetBuilder builder;
  final Widget fallback;
  final Duration timeout;

  @override
  State<GoogleMapWebGate> createState() => _GoogleMapWebGateState();
}

class _GoogleMapWebGateState extends State<GoogleMapWebGate> {
  bool? _ready;
  bool _buildMap = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _ready = true;
      _buildMap = true;
      return;
    }
    _waitForMaps();
  }

  Future<void> _waitForMaps() async {
    final loaded = await ensureGoogleMapsJsLoaded().timeout(
      widget.timeout,
      onTimeout: () => isGoogleMapsJsReady(),
    );
    if (!mounted) return;
    setState(() => _ready = loaded);
    if (!loaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _buildMap = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return const ColoredBox(
        color: Color(0xFFE8ECEF),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_ready!) return widget.fallback;
    if (kIsWeb && !_buildMap) {
      return const ColoredBox(
        color: Color(0xFFE8ECEF),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.builder(context);
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../di/service_locator.dart';
import 'tracking_event_service.dart';

/// Forwards app lifecycle to [TrackingEventService] during active trips.
class TrackingLifecycleBinder extends WidgetsBindingObserver {
  TrackingLifecycleBinder._();
  static final TrackingLifecycleBinder instance = TrackingLifecycleBinder._();

  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  TrackingEventService? get _events =>
      ServiceLocator.I.has<TrackingEventService>()
          ? ServiceLocator.I.get<TrackingEventService>()
          : null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final events = _events;
    if (events == null) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(events.onAppBackground());
      case AppLifecycleState.resumed:
        unawaited(events.onAppForeground());
      case AppLifecycleState.inactive:
        break;
    }
  }
}

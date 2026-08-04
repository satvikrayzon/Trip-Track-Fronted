import 'dart:async';

import 'package:flutter/widgets.dart';

import '../di/service_locator.dart';
import 'punch_reminder_service.dart';
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

  PunchReminderService? get _reminders =>
      ServiceLocator.I.has<PunchReminderService>()
          ? ServiceLocator.I.get<PunchReminderService>()
          : null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final events = _events;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (events != null) unawaited(events.onAppBackground());
      case AppLifecycleState.resumed:
        if (events != null) unawaited(events.onAppForeground());
        final reminders = _reminders;
        if (reminders != null) unawaited(reminders.checkNow());
      case AppLifecycleState.inactive:
        break;
    }
  }
}

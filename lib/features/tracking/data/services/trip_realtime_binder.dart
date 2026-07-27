import 'dart:async';

import '../../../../core/di/service_locator.dart';
import '../../../../modules/travel/data/models/travel_request_model.dart';
import 'websocket_tracking_service.dart';

bool tripMatchesRealtimeKey(TravelRequestModel trip, String key) {
  if (key.isEmpty) return false;
  return trip.requestId == key ||
      trip.restResourceId == key ||
      trip.tripId == key ||
      (trip.mongoDocumentId?.isNotEmpty == true && trip.mongoDocumentId == key);
}

/// Subscribes to Socket.IO trip updates and optional refetch hints.
class TripRealtimeBinder {
  TripRealtimeBinder({
    this.filter,
    required this.onTripUpdate,
    this.onTripRefetch,
    this.onTripDelete,
  });

  final bool Function(TravelRequestModel trip)? filter;
  final void Function(TravelRequestModel trip) onTripUpdate;
  final void Function(String requestId)? onTripRefetch;
  final void Function(String tripId)? onTripDelete;

  StreamSubscription<TravelRequestModel>? _tripSub;
  StreamSubscription<String>? _refetchSub;
  StreamSubscription<String>? _deleteSub;

  void start() {
    if (!ServiceLocator.I.has<WebSocketTrackingService>()) return;
    final ws = ServiceLocator.I.get<WebSocketTrackingService>();
    unawaited(ws.connect());

    _tripSub?.cancel();
    _tripSub = ws.tripUpdates.listen((trip) {
      if (filter != null && !filter!(trip)) return;
      onTripUpdate(trip);
    });

    if (onTripRefetch != null) {
      _refetchSub?.cancel();
      _refetchSub = ws.tripRefetchIds.listen((id) {
        onTripRefetch!(id);
      });
    }

    if (onTripDelete != null) {
      _deleteSub?.cancel();
      _deleteSub = ws.tripDeletes.listen((id) {
        onTripDelete!(id);
      });
    }
  }

  bool get isLive {
    if (!ServiceLocator.I.has<WebSocketTrackingService>()) return false;
    return ServiceLocator.I.get<WebSocketTrackingService>().isTripRealtimeLive;
  }

  void dispose() {
    _tripSub?.cancel();
    _tripSub = null;
    _refetchSub?.cancel();
    _refetchSub = null;
    _deleteSub?.cancel();
    _deleteSub = null;
  }
}

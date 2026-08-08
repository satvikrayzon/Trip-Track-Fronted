/// REST paths — align with your NestJS global prefix (e.g. `/api/v1`).
/// Set base URL only in [ApiEnv]; paths here are relative to that root.
abstract final class ApiEndpoints {
  static const String authLogin = '/auth/login';
  static const String authRefresh = '/auth/refresh';
  static const String authForgotPassword = '/auth/forgot-password';
  static const String authMe = '/auth/me';

  static const String users = '/users';
  static const String reportingManagers = '/users/reporting-managers';
  static String user(String id) => '$users/$id';
  static String userDeactivate(String id) => '$users/$id/deactivate';
  static String userActivate(String id) => '$users/$id/activate';

  static const String travelRequests = '/travel-requests';
  static const String travelRequestsActive = '$travelRequests/active';
  static const String travelRequestsSummary = '$travelRequests/summary';
  static String travelRequest(String id) => '$travelRequests/$id';
  static String travelRequestDeparture(String requestId) =>
      '$travelRequests/$requestId/departure';
  static String travelRequestArrival(String requestId) =>
      '$travelRequests/$requestId/arrival';
  static String travelRequestMeetingStart(String requestId) =>
      '$travelRequests/$requestId/meeting-start';
  static String travelRequestMeetingEnd(String requestId) =>
      '$travelRequests/$requestId/meeting-end';
  static String travelRequestReturnStart(String requestId) =>
      '$travelRequests/$requestId/return-start';
  static String travelRequestNextClient(String requestId) =>
      '$travelRequests/$requestId/next-client';
  /// Fallback when travel-request punch proxies are not deployed yet.
  static String tripMeetingStart(String tripId) =>
      '/trips/$tripId/punches/meeting-start';
  static String tripMeetingEnd(String tripId) =>
      '/trips/$tripId/punches/meeting-end';
  static String travelRequestRoutePoints(String requestId) =>
      '$travelRequests/$requestId/route-points';
  static String travelRequestRoutePointsBatch(String requestId) =>
      '$travelRequests/$requestId/route-points/batch';
  static String travelRequestTrackingEventsBatch(String requestId) =>
      '$travelRequests/$requestId/tracking-events/batch';
  static String travelRequestTrackingCoverage(String requestId) =>
      '$travelRequests/$requestId/tracking-coverage';
  static String travelRequestMeterImage(String requestId) =>
      '$travelRequests/$requestId/meter-image';

  /// Official map-matched route + km (Nest MapMatchingWorker).
  static String travelRequestMatchedRoute(String requestId) =>
      '$travelRequests/$requestId/matched-route';

  /// Enqueue rematch after GPS catch-up / trip end.
  static String travelRequestMatch(String requestId) =>
      '$travelRequests/$requestId/match';

  /// Legacy Nest Directions proxy (unused — Flutter calls Google directly).
  static const String directionsRoute = '/directions/route';

  /// Legacy Nest Snap-to-Roads proxy (unused — Flutter calls Google directly).
  static const String directionsSnapPath = '/directions/snap-path';

  /// Legacy Nest align-path (unused — Flutter RoadAlignedRouteService is local).
  static const String directionsAlignPath = '/directions/align-path';

  static const String adminFuelRates = '/admin/fuel-rates';
}

import '../../../core/constants/app_constants.dart';
import '../../../core/network/failures/network_failure.dart';
import '../data/models/travel_request_model.dart';

/// Whether the trip can be deleted.
///
/// [asAdmin]: admin app has no status restrictions — any trip can be deleted.
/// Employees can only delete unstarted trips.
bool canDeleteTravelRequest(
  TravelRequestModel request, {
  bool asAdmin = false,
}) {
  if (asAdmin) return true;
  if (request.status == 'Completed') return false;
  if (request.tripLegs.any((leg) => leg.hasDeparted)) return false;
  if (request.hasDeparted &&
      request.status != AppConstants.statusReadyToStart &&
      request.status != AppConstants.statusStartMissing) {
    return false;
  }
  return request.status == AppConstants.statusReadyToStart ||
      request.status == AppConstants.statusStartMissing;
}

/// User-facing message for DELETE /travel-requests/:id failures.
String deleteTravelRequestUserMessage(NetworkFailure failure) {
  final server = failure.message.trim();
  final looksGeneric = server.isEmpty ||
      server.toLowerCase() == 'bad request' ||
      server.toLowerCase().contains('dio') ||
      server.toLowerCase().contains('http');

  switch (failure.statusCode) {
    case 400:
      if (!looksGeneric) return server;
      return 'Cannot delete — trip has already started';
    case 403:
      if (!looksGeneric) return server;
      return 'You are not allowed to delete this request';
    case 404:
      return 'Travel request not found';
    default:
      return server.isNotEmpty ? server : 'Unable to delete travel request';
  }
}

bool travelRequestMatchesId(TravelRequestModel request, String id) {
  if (id.isEmpty) return false;
  return request.requestId == id ||
      request.tripId == id ||
      request.restResourceId == id ||
      request.mongoDocumentId == id;
}

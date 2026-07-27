import '../../../core/constants/app_constants.dart';
import '../../../core/network/failures/network_failure.dart';
import '../data/models/travel_request_model.dart';

/// Whether the trip can be deleted (not started, not completed).
bool canDeleteTravelRequest(TravelRequestModel request) {
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
  switch (failure.statusCode) {
    case 400:
      return 'Cannot delete — trip has already started';
    case 403:
      return 'You are not allowed to delete this request';
    case 404:
      return 'Travel request not found';
    default:
      return failure.message;
  }
}

bool travelRequestMatchesId(TravelRequestModel request, String id) {
  if (id.isEmpty) return false;
  return request.requestId == id ||
      request.tripId == id ||
      request.restResourceId == id ||
      request.mongoDocumentId == id;
}

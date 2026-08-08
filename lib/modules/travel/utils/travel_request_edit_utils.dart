import '../../../core/constants/app_constants.dart';
import '../../../core/models/picked_location.dart';
import '../../../core/utils/geo_utils.dart';
import '../data/models/travel_request_model.dart';

/// Whether the trip is in progress (started but not completed).
bool isTravelRequestRunning(TravelRequestModel request) {
  if (request.status == AppConstants.statusCompleted) return false;
  if (request.tripLegs.any((leg) => leg.hasDeparted)) return true;
  if (request.hasDeparted) return true;

  const runningStatuses = {
    AppConstants.statusTravelling,
    AppConstants.statusAtClient,
    AppConstants.statusInMeeting,
    AppConstants.statusReadyForNext,
    AppConstants.statusReadyToReturn,
    AppConstants.statusReturning,
    AppConstants.statusEndMissing,
  };
  return runningStatuses.contains(request.status);
}

/// Users may create / hold multiple trips at once.
///
/// GPS still tracks only the trip the user has punched departure on
/// ([BackgroundLocationService] focus). Creating another trip is allowed.
bool blocksNewTravelRequest(TravelRequestModel? activeTrip) => false;

String newTravelRequestBlockedMessage(TravelRequestModel trip) {
  final label = trip.clientName.isNotEmpty
      ? trip.clientName
      : trip.displayToLocation;
  return 'You already have an in-progress trip ($label). '
      'You can still create another — GPS tracks the trip you start.';
}

/// Whether the active leg can be edited (not departed, not return leg).
bool canEditTravelRequest(TravelRequestModel request) {
  if (request.status == AppConstants.statusCompleted) return false;

  final leg = request.activeLeg;
  if (leg != null) {
    return !leg.isReturnLeg && !leg.hasDeparted;
  }

  return !request.hasDeparted &&
      (request.status == AppConstants.statusReadyToStart ||
          request.status == AppConstants.statusStartMissing);
}

/// Trip-level vehicle and fuel — only before any leg has departed.
bool canEditTripVehicleSettings(TravelRequestModel request) {
  if (request.status == AppConstants.statusCompleted) return false;
  if (request.tripLegs.isNotEmpty) {
    return !request.tripLegs.any((leg) => leg.hasDeparted);
  }
  return !request.hasDeparted;
}

String editTravelRequestBlockedMessage(TravelRequestModel request) {
  if (request.status == AppConstants.statusCompleted) {
    return 'Cannot edit a completed request';
  }
  final leg = request.activeLeg;
  if (leg?.isReturnLeg == true) {
    return 'Cannot edit the return leg';
  }
  if (leg?.hasDeparted == true || request.hasDeparted) {
    return 'Cannot edit after this leg has started';
  }
  return 'This request cannot be edited';
}

/// Leg index used when saving edits (current active leg or custom leg index).
int editableLegIndex(TravelRequestModel request, {int? legIndex}) {
  if (request.tripLegs.isEmpty) return 0;
  if (legIndex != null) {
    return legIndex.clamp(0, request.tripLegs.length - 1);
  }
  return request.currentLegIndex.clamp(0, request.tripLegs.length - 1);
}

/// Checks if a specific leg card is allowed to be edited.
bool canEditTripLeg(TravelRequestModel request, TripLegModel leg) {
  if (request.status == AppConstants.statusCompleted) return false;
  return !leg.isReturnLeg && !leg.hasDeparted;
}

PickedLocation? pickedLocationForLegField({
  required String address,
  String? displayName,
  Map<String, double>? coordinates,
}) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return null;

  final lat = coordinates?['latitude'];
  final lng = coordinates?['longitude'];
  if (lat != null && lng != null && GeoUtils.isValidLatLng(lat, lng)) {
    return PickedLocation(
      name: (displayName?.trim().isNotEmpty == true) ? displayName!.trim() : trimmed,
      formattedAddress: trimmed,
      latitude: lat,
      longitude: lng,
    );
  }

  // Address-only placeholder. Callers must not PATCH (0,0) to the API.
  return PickedLocation(
    name: (displayName?.trim().isNotEmpty == true) ? displayName!.trim() : trimmed,
    formattedAddress: trimmed,
    latitude: 0,
    longitude: 0,
  );
}

PickedLocation? pickedFromForEdit(TravelRequestModel request, {int? legIndex}) {
  final leg = (legIndex != null && legIndex >= 0 && legIndex < request.tripLegs.length)
      ? request.tripLegs[legIndex]
      : request.activeLeg;
  final address = leg?.fromLocation.isNotEmpty == true
      ? leg!.fromLocation
      : request.fromLocation;
  return pickedLocationForLegField(
    address: address,
    displayName: request.startAddress,
    coordinates: request.startCoordinates,
  );
}

PickedLocation? pickedToForEdit(TravelRequestModel request, {int? legIndex}) {
  final leg = (legIndex != null && legIndex >= 0 && legIndex < request.tripLegs.length)
      ? request.tripLegs[legIndex]
      : request.activeLeg;
  final address = leg?.toLocation.isNotEmpty == true
      ? leg!.toLocation
      : request.toLocation;
  return pickedLocationForLegField(
    address: address,
    displayName: request.endAddress,
    coordinates: request.endCoordinates,
  );
}

String clientNameForEdit(TravelRequestModel request, {int? legIndex}) {
  final leg = (legIndex != null && legIndex >= 0 && legIndex < request.tripLegs.length)
      ? request.tripLegs[legIndex]
      : request.activeLeg;
  if (leg != null && leg.clientName.isNotEmpty) return leg.clientName;
  return request.clientName;
}

String purposeForEdit(TravelRequestModel request, {int? legIndex}) {
  final leg = (legIndex != null && legIndex >= 0 && legIndex < request.tripLegs.length)
      ? request.tripLegs[legIndex]
      : request.activeLeg;
  if (leg != null && leg.purpose.isNotEmpty) return leg.purpose;
  return request.purpose ?? '';
}

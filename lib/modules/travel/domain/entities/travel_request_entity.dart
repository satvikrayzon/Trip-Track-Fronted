/// Travel request entity for domain layer
class TravelRequestEntity {
  final String requestId;
  final String userId;
  final String userName;
  final String city;
  final String fromLocation;
  final String toLocation;
  final String vehicleType;
  final String? fuelType;
  final String? purpose;
  final String? notes;
  final DateTime requestDate;
  final String status;
  final String? startImageUrl;
  final String? endImageUrl;
  final Map<String, double>? startCoordinates;
  final Map<String, double>? endCoordinates;
  final String? startAddress;
  final String? endAddress;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? distance;
  final double? startOdometerReading;
  final double? endOdometerReading;
  final List<Map<String, dynamic>>? stops;

  /// Live GPS tracking (optional; older docs may omit).
  final String? trackingSessionId;
  final DateTime? tripStartedAt;
  final DateTime? tripEndedAt;
  /// idle | tracking | paused | ended
  final String? trackingStatus;
  final bool enableLiveTracking;

  /// MongoDB document id when API returns `_id` (used in `/travel-requests/:id`).
  final String? mongoDocumentId;

  const TravelRequestEntity({
    required this.requestId,
    required this.userId,
    required this.userName,
    required this.city,
    required this.fromLocation,
    required this.toLocation,
    required this.vehicleType,
    this.fuelType,
    this.purpose,
    this.notes,
    required this.requestDate,
    required this.status,
    this.startImageUrl,
    this.endImageUrl,
    this.startCoordinates,
    this.endCoordinates,
    this.startAddress,
    this.endAddress,
    this.startTime,
    this.endTime,
    this.distance,
    this.startOdometerReading,
    this.endOdometerReading,
    this.stops,
    this.trackingSessionId,
    this.tripStartedAt,
    this.tripEndedAt,
    this.trackingStatus,
    this.enableLiveTracking = true,
    this.mongoDocumentId,
  });

  @override
  String toString() {
    return 'TravelRequestEntity(requestId: $requestId, userId: $userId, userName: $userName, status: $status)';
  }
}

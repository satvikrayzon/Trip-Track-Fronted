import 'dart:math' as math;

import '../../domain/entities/travel_request_entity.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/distance_sanity.dart';

/// GPS/time punch captured for a route or meeting event.
class TripPunchModel {
  final String punchId;
  final String type;
  final String label;
  final DateTime time;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String address;

  const TripPunchModel({
    required this.punchId,
    required this.type,
    required this.label,
    required this.time,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.address,
  });

  factory TripPunchModel.fromMap(dynamic data) {
    if (data == null || data is! Map) {
      return TripPunchModel.empty();
    }

    final map = Map<String, dynamic>.from(data);
    final type = TravelRequestModel.normalizePunchType(
      map['type']?.toString() ?? map['punchType']?.toString(),
    );
    return TripPunchModel(
      punchId: map['punchId']?.toString() ?? map['id']?.toString() ?? '',
      type: type,
      label: map['label']?.toString() ?? '',
      time: _parseDateTime(map['time'] ?? map['timestamp']),
      latitude: _parseDouble(map['latitude']) ?? _parseDouble(map['lat']) ?? 0.0,
      longitude: _parseDouble(map['longitude']) ?? _parseDouble(map['lng']) ?? 0.0,
      accuracy: _parseDouble(map['accuracy']) ?? _parseDouble(map['gpsAccuracy']),
      address: map['address']?.toString() ?? '',
    );
  }

  factory TripPunchModel.empty() {
    return TripPunchModel(
      punchId: '',
      type: '',
      label: '',
      time: DateTime.now(),
      latitude: 0,
      longitude: 0,
      address: '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'punchId': punchId,
      'type': type,
      'label': label,
      'time': time.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'address': address,
    };
  }
}

/// One travel leg in a multi-stop trip.
class TripLegModel {
  final String legId;
  final int sequence;
  final String fromLocation;
  final String toLocation;
  final String clientName;
  final String purpose;
  final String clientOfficeAddress;
  final bool isReturnLeg;
  final TripPunchModel? departurePunch;
  final TripPunchModel? arrivalPunch;
  final TripPunchModel? meetingStartPunch;
  final TripPunchModel? meetingEndPunch;
  final double? plannedDistanceKm;
  final double? actualDistanceKm;
  final int? travelDurationMinutes;
  final int? meetingDurationMinutes;

  /// Provisional GPS / Haversine track distance (approximate; not billable).
  final double? actualDistanceKmFromTrack;
  final int? trackMovingDurationMinutes;
  final int? trackStoppedDurationMinutes;
  final String? routePolylineEncoded;

  /// Backend map-matched official distance (billing source of truth).
  final double? officialDistanceKm;

  /// Server-reported provisional km (may mirror [actualDistanceKmFromTrack]).
  final double? provisionalDistanceKm;

  /// Official matched geometry (`lat,lng|...`).
  final String? matchedRoutePolylineEncoded;

  /// Match confidence 0–1 for this leg.
  final double? matchConfidence;

  /// Share of leg length that was gap-estimated (0–1).
  final double? estimatedPct;

  const TripLegModel({
    required this.legId,
    required this.sequence,
    required this.fromLocation,
    required this.toLocation,
    required this.clientName,
    required this.purpose,
    required this.clientOfficeAddress,
    this.isReturnLeg = false,
    this.departurePunch,
    this.arrivalPunch,
    this.meetingStartPunch,
    this.meetingEndPunch,
    this.plannedDistanceKm,
    this.actualDistanceKm,
    this.travelDurationMinutes,
    this.meetingDurationMinutes,
    this.actualDistanceKmFromTrack,
    this.trackMovingDurationMinutes,
    this.trackStoppedDurationMinutes,
    this.routePolylineEncoded,
    this.officialDistanceKm,
    this.provisionalDistanceKm,
    this.matchedRoutePolylineEncoded,
    this.matchConfidence,
    this.estimatedPct,
  });

  factory TripLegModel.fromMap(dynamic data) {
    if (data == null || data is! Map) {
      return TripLegModel.empty();
    }

    final map = Map<String, dynamic>.from(data);
    final legNumber = _parseInt(map['legNumber']) ?? _parseInt(map['sequence']);
  return TripLegModel(
      legId: map['legId']?.toString() ??
          (legNumber != null ? 'leg_$legNumber' : ''),
      sequence: legNumber ?? 0,
      fromLocation: map['fromLocation'] ?? '',
      toLocation: map['toLocation'] ?? '',
      clientName: map['clientName'] ?? map['name'] ?? '',
      purpose: map['purpose'] ?? '',
      clientOfficeAddress:
          map['clientOfficeAddress'] ?? map['officeAddress'] ?? '',
      isReturnLeg: map['isReturnLeg'] == true,
      departurePunch: _parsePunch(map['departurePunch']),
      arrivalPunch: _parsePunch(map['arrivalPunch']),
      meetingStartPunch: _parsePunch(map['meetingStartPunch']),
      meetingEndPunch: _parsePunch(map['meetingEndPunch']),
      plannedDistanceKm: _parseDouble(map['plannedDistanceKm']),
      actualDistanceKm: _parseDouble(map['actualDistanceKm']),
      travelDurationMinutes: _parseInt(map['travelDurationMinutes']),
      meetingDurationMinutes: _parseInt(map['meetingDurationMinutes']),
      actualDistanceKmFromTrack: _parseDouble(map['actualDistanceKmFromTrack']),
      trackMovingDurationMinutes: _parseInt(map['trackMovingDurationMinutes']),
      trackStoppedDurationMinutes:
          _parseInt(map['trackStoppedDurationMinutes']),
      routePolylineEncoded: map['routePolylineEncoded'] as String?,
      officialDistanceKm: _parseDouble(
        map['officialDistanceKm'] ?? map['officialKm'],
      ),
      provisionalDistanceKm: _parseDouble(
        map['provisionalDistanceKm'] ?? map['provisionalKm'],
      ),
      matchedRoutePolylineEncoded:
          map['matchedRoutePolylineEncoded'] as String? ??
              map['matchedPolylineEncoded'] as String?,
      matchConfidence: _parseDouble(map['matchConfidence'] ?? map['confidence']),
      estimatedPct: _parseDouble(map['estimatedPct']),
    ).withRecalculatedMetrics();
  }

  factory TripLegModel.empty() {
    return const TripLegModel(
      legId: '',
      sequence: 0,
      fromLocation: '',
      toLocation: '',
      clientName: '',
      purpose: '',
      clientOfficeAddress: '',
    );
  }

  bool get hasDeparted => departurePunch != null;
  bool get hasArrived => arrivalPunch != null;
  bool get isTravelComplete => hasDeparted && hasArrived;
  bool get isMeetingStarted => meetingStartPunch != null;
  bool get isMeetingComplete =>
      isReturnLeg || (meetingStartPunch != null && meetingEndPunch != null);
  bool get isComplete => isTravelComplete && isMeetingComplete;

  /// Prefer sane official matched km, then provisional GPS, then planned/punch.
  double? get displayDistanceKm => DistanceSanity.selectLegKm(
        officialKm: officialDistanceKm,
        provisionalKm: provisionalDistanceKm,
        trackKm: actualDistanceKmFromTrack,
        plannedKm: plannedDistanceKm,
        punchKm: actualDistanceKm,
        travelMinutes: travelDurationMinutes,
      );

  bool get hasOfficialDistance {
    final o = officialDistanceKm;
    if (o == null || o <= 0) return false;
    return !DistanceSanity.isOfficialAbsurd(
      officialKm: o,
      gpsKm: provisionalDistanceKm ?? actualDistanceKmFromTrack,
      plannedKm: plannedDistanceKm,
      travelMinutes: travelDurationMinutes,
    );
  }

  String get displayDistanceLabel {
    if (hasOfficialDistance) return 'Official';
    if (provisionalDistanceKm != null || actualDistanceKmFromTrack != null) {
      return 'Approx (GPS)';
    }
    if (plannedDistanceKm != null) return 'Planned';
    return 'Distance';
  }

  /// True when stored official km is a teleport / map-match blow-up.
  bool get hasAbsurdOfficialDistance {
    final o = officialDistanceKm;
    if (o == null || o <= 0) return false;
    return DistanceSanity.isOfficialAbsurd(
      officialKm: o,
      gpsKm: provisionalDistanceKm ?? actualDistanceKmFromTrack,
      plannedKm: plannedDistanceKm,
      travelMinutes: travelDurationMinutes,
    );
  }

  String get displayTitle {
    if (isReturnLeg) return 'Return to $toLocation';
    return toLocation;
  }

  TripLegModel withRecalculatedMetrics() {
    double? distance = actualDistanceKm;
    int? travelMinutes = travelDurationMinutes;
    int? meetingMinutes = meetingDurationMinutes;

    if (departurePunch != null && arrivalPunch != null) {
      if (distance == null || distance == 0) {
        distance = _calculateDistanceKm(
          departurePunch!.latitude,
          departurePunch!.longitude,
          arrivalPunch!.latitude,
          arrivalPunch!.longitude,
        );
      }
      travelMinutes =
          arrivalPunch!.time.difference(departurePunch!.time).inMinutes.abs();
    }

    if (meetingStartPunch != null && meetingEndPunch != null) {
      meetingMinutes = meetingEndPunch!.time
          .difference(meetingStartPunch!.time)
          .inMinutes
          .abs();
    }

    return copyWith(
      actualDistanceKm: distance,
      travelDurationMinutes: travelMinutes,
      meetingDurationMinutes: meetingMinutes,
    );
  }

  TripLegModel copyWith({
    String? legId,
    int? sequence,
    String? fromLocation,
    String? toLocation,
    String? clientName,
    String? purpose,
    String? clientOfficeAddress,
    bool? isReturnLeg,
    TripPunchModel? departurePunch,
    TripPunchModel? arrivalPunch,
    TripPunchModel? meetingStartPunch,
    TripPunchModel? meetingEndPunch,
    double? plannedDistanceKm,
    double? actualDistanceKm,
    int? travelDurationMinutes,
    int? meetingDurationMinutes,
    double? actualDistanceKmFromTrack,
    int? trackMovingDurationMinutes,
    int? trackStoppedDurationMinutes,
    String? routePolylineEncoded,
    double? officialDistanceKm,
    double? provisionalDistanceKm,
    String? matchedRoutePolylineEncoded,
    double? matchConfidence,
    double? estimatedPct,
    bool clearOfficialDistanceKm = false,
    bool clearMatchedRoutePolylineEncoded = false,
    bool clearMatchConfidence = false,
    bool clearEstimatedPct = false,
  }) {
    return TripLegModel(
      legId: legId ?? this.legId,
      sequence: sequence ?? this.sequence,
      fromLocation: fromLocation ?? this.fromLocation,
      toLocation: toLocation ?? this.toLocation,
      clientName: clientName ?? this.clientName,
      purpose: purpose ?? this.purpose,
      clientOfficeAddress: clientOfficeAddress ?? this.clientOfficeAddress,
      isReturnLeg: isReturnLeg ?? this.isReturnLeg,
      departurePunch: departurePunch ?? this.departurePunch,
      arrivalPunch: arrivalPunch ?? this.arrivalPunch,
      meetingStartPunch: meetingStartPunch ?? this.meetingStartPunch,
      meetingEndPunch: meetingEndPunch ?? this.meetingEndPunch,
      plannedDistanceKm: plannedDistanceKm ?? this.plannedDistanceKm,
      actualDistanceKm: actualDistanceKm ?? this.actualDistanceKm,
      travelDurationMinutes:
          travelDurationMinutes ?? this.travelDurationMinutes,
      meetingDurationMinutes:
          meetingDurationMinutes ?? this.meetingDurationMinutes,
      actualDistanceKmFromTrack:
          actualDistanceKmFromTrack ?? this.actualDistanceKmFromTrack,
      trackMovingDurationMinutes:
          trackMovingDurationMinutes ?? this.trackMovingDurationMinutes,
      trackStoppedDurationMinutes:
          trackStoppedDurationMinutes ?? this.trackStoppedDurationMinutes,
      routePolylineEncoded: routePolylineEncoded ?? this.routePolylineEncoded,
      officialDistanceKm: clearOfficialDistanceKm
          ? null
          : (officialDistanceKm ?? this.officialDistanceKm),
      provisionalDistanceKm:
          provisionalDistanceKm ?? this.provisionalDistanceKm,
      matchedRoutePolylineEncoded: clearMatchedRoutePolylineEncoded
          ? null
          : (matchedRoutePolylineEncoded ?? this.matchedRoutePolylineEncoded),
      matchConfidence: clearMatchConfidence
          ? null
          : (matchConfidence ?? this.matchConfidence),
      estimatedPct:
          clearEstimatedPct ? null : (estimatedPct ?? this.estimatedPct),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'legId': legId,
      'sequence': sequence,
      'fromLocation': fromLocation,
      'toLocation': toLocation,
      'clientName': clientName,
      'purpose': purpose,
      'clientOfficeAddress': clientOfficeAddress,
      'isReturnLeg': isReturnLeg,
      'departurePunch': departurePunch?.toMap(),
      'arrivalPunch': arrivalPunch?.toMap(),
      'meetingStartPunch': meetingStartPunch?.toMap(),
      'meetingEndPunch': meetingEndPunch?.toMap(),
      'plannedDistanceKm': plannedDistanceKm,
      'actualDistanceKm': actualDistanceKm,
      'travelDurationMinutes': travelDurationMinutes,
      'meetingDurationMinutes': meetingDurationMinutes,
      'actualDistanceKmFromTrack': actualDistanceKmFromTrack,
      'trackMovingDurationMinutes': trackMovingDurationMinutes,
      'trackStoppedDurationMinutes': trackStoppedDurationMinutes,
      'routePolylineEncoded': routePolylineEncoded,
      'officialDistanceKm': officialDistanceKm,
      'provisionalDistanceKm': provisionalDistanceKm,
      'matchedRoutePolylineEncoded': matchedRoutePolylineEncoded,
      'matchConfidence': matchConfidence,
      'estimatedPct': estimatedPct,
    };
  }

  static TripPunchModel? _parsePunch(dynamic data) {
    if (data == null || data is! Map) return null;
    return TripPunchModel.fromMap(data);
  }
}

/// Travel request model for data layer.
class TravelRequestModel extends TravelRequestEntity {
  final String tripId;
  final String clientName;
  final String? employeeCode;
  final String? rawStatus;
  final List<TripPunchModel> punches;
  final bool? apiHasDeparted;
  final bool? apiCanMarkArrival;
  final bool isActive;
  final List<Map<String, dynamic>> routePoints;
  final List<TripLegModel> tripLegs;
  final double totalDistanceKm;
  final int totalTravelDurationMinutes;
  final int totalMeetingDurationMinutes;
  final int totalMeetings;
  final int currentLegIndex;
  final int routePointCount;
  final int totalMovingMinutesFromTrack;
  final int totalStoppedMinutesFromTrack;
  final double travelAllowance;
  final double? fuelRatePerKm;

  const TravelRequestModel({
    required super.requestId,
    this.tripId = '',
    this.clientName = '',
    required super.userId,
    required super.userName,
    this.employeeCode,
    required super.city,
    required super.fromLocation,
    required super.toLocation,
    required super.vehicleType,
    super.fuelType,
    super.purpose,
    super.notes,
    required super.requestDate,
    required super.status,
    this.rawStatus,
    super.startImageUrl,
    super.endImageUrl,
    super.startCoordinates,
    super.endCoordinates,
    super.startAddress,
    super.endAddress,
    super.startTime,
    super.endTime,
    super.distance,
    super.startOdometerReading,
    super.endOdometerReading,
    super.stops,
    super.trackingSessionId,
    super.tripStartedAt,
    super.tripEndedAt,
    super.trackingStatus,
    super.enableLiveTracking = true,
    super.mongoDocumentId,
    this.punches = const [],
    this.apiHasDeparted,
    this.apiCanMarkArrival,
    this.isActive = false,
    this.routePoints = const [],
    this.tripLegs = const [],
    this.totalDistanceKm = 0,
    this.totalTravelDurationMinutes = 0,
    this.totalMeetingDurationMinutes = 0,
    this.totalMeetings = 0,
    this.currentLegIndex = 0,
    this.routePointCount = 0,
    this.totalMovingMinutesFromTrack = 0,
    this.totalStoppedMinutesFromTrack = 0,
    this.travelAllowance = 0,
    this.fuelRatePerKm,
  });

  factory TravelRequestModel.fromMap(Map<String, dynamic> data) {
    final tripId = data['tripId']?.toString() ??
        data['requestId']?.toString() ??
        data['id']?.toString() ??
        '';
    final requestId = data['requestId']?.toString() ??
        (data['tripId'] != null ? data['tripId']?.toString() : null) ??
        data['id']?.toString() ??
        '';
    final parsedLegs = _parseTripLegs(
      data['tripLegs'] ??
          data['legs'] ??
          _nonEmptyStops(data['stops']),
    );
    var normalizedLegs =
        parsedLegs.map((leg) => leg.withRecalculatedMetrics()).toList();
    normalizedLegs = _ensureDefaultLegs(data, normalizedLegs);
    normalizedLegs = _applyFlatPunchesToLegs(
      normalizedLegs,
      data['punches'] ?? data['tripPunches'],
    );
    normalizedLegs = _sanitizeLegPunches(normalizedLegs);
    final summary = _calculateSummary(normalizedLegs);
    final rawStatus = data['rawStatus']?.toString();
    final apiStatus = _normalizeStatus(data['status'] ?? rawStatus ?? '');
    final derivedStatus = _deriveStatus(normalizedLegs);
    final displayStatus = data['displayStatus']?.toString().trim();
    final status = displayStatus != null && displayStatus.isNotEmpty
        ? displayStatus
        : _pickDisplayStatus(apiStatus, derivedStatus);
    final userMap = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : null;
    final clientName = data['clientName']?.toString().trim() ??
        _clientNameFromLegs(normalizedLegs);
    final punches = _parsePunches(data['punches']);
    final routePoints = _parseRoutePoints(
      data['routePoints'] ?? data['route'],
    );

    return TravelRequestModel(
      requestId: requestId.isNotEmpty ? requestId : tripId,
      tripId: tripId,
      clientName: clientName,
      mongoDocumentId: data['_id']?.toString(),
      userId: userMap?['uid']?.toString() ??
          userMap?['id']?.toString() ??
          data['userId']?.toString() ??
          '',
      userName: _pickUserName(data, userMap),
      employeeCode: userMap?['employeeCode']?.toString() ??
          data['employeeCode']?.toString() ??
          '',
      city: data['city'] ?? '',
      fromLocation: data['fromLocation'] ?? '',
      toLocation: data['toLocation'] ?? '',
      vehicleType: data['vehicleType']?.toString() ?? AppConstants.vehicleTypeCar,
      fuelType: data['fuelType']?.toString(),
      purpose: data['purpose']?.toString(),
      notes: data['notes']?.toString(),
      requestDate: _parseDateTime(data['requestDate'] ?? data['createdAt']),
      status: status,
      rawStatus: rawStatus,
      startImageUrl: data['startImageUrl'],
      endImageUrl: data['endImageUrl'],
      startCoordinates:
          _parseCoordinates(data['startCoordinates']) ??
              _parseLatLngFields(data, 'originLat', 'originLng') ??
              _parseLatLngFields(data, 'fromLat', 'fromLng') ??
              _parseOriginFromCoordinates(data['coordinates']),
      endCoordinates: _parseCoordinates(data['endCoordinates']) ??
          _parseLatLngFields(data, 'destinationLat', 'destinationLng') ??
          _parseDestinationCoordinates(data['coordinates']),
      startAddress: data['startAddress'],
      endAddress: data['endAddress'],
      startTime: _parseDateTimeNullable(data['startTime']),
      endTime: _parseDateTimeNullable(data['endTime']),
      distance: _parseDouble(data['distance']),
      startOdometerReading: _parseDouble(data['startOdometerReading']),
      endOdometerReading: _parseDouble(data['endOdometerReading']),
      stops: _parseStops(data['stops']),
      trackingSessionId: data['trackingSessionId'] as String?,
      tripStartedAt: _parseDateTimeNullable(data['tripStartedAt']),
      tripEndedAt: _parseDateTimeNullable(data['tripEndedAt']),
      trackingStatus: data['trackingStatus'] as String?,
      enableLiveTracking: data['enableLiveTracking'] != false,
      punches: punches,
      apiHasDeparted: _parseBool(data['hasDeparted']),
      apiCanMarkArrival: _parseBool(data['canMarkArrival']),
      isActive: data['isActive'] == true,
      routePoints: routePoints,
      tripLegs: normalizedLegs,
      totalDistanceKm:
          _parseDouble(data['totalDistanceKm']) ?? summary.totalDistanceKm,
      totalTravelDurationMinutes:
          _parseInt(data['totalTravelDurationMinutes']) ??
              summary.totalTravelDurationMinutes,
      totalMeetingDurationMinutes:
          _parseInt(data['totalMeetingDurationMinutes']) ??
              summary.totalMeetingDurationMinutes,
      totalMeetings: _parseInt(data['totalMeetings']) ?? summary.totalMeetings,
      currentLegIndex: _resolveCurrentLegIndex(data, normalizedLegs),
      routePointCount: _parseInt(data['routePointCount']) ?? 0,
      totalMovingMinutesFromTrack:
          _parseInt(data['totalMovingMinutesFromTrack']) ??
              summary.totalMovingMinutesFromTrack,
      totalStoppedMinutesFromTrack:
          _parseInt(data['totalStoppedMinutesFromTrack']) ??
              summary.totalStoppedMinutesFromTrack,
      travelAllowance: _parseDouble(data['travelAllowance']) ?? 0,
      fuelRatePerKm: _parseDouble(data['fuelRatePerKm']),
    ).withRecalculatedSummary();
  }

  factory TravelRequestModel.fromJson(Map<String, dynamic> json) =>
      TravelRequestModel.fromMap(json);

  /// Ensures a single travel leg exists for simple API trips (from/to only).
  TravelRequestModel ensureTripLegs() {
    if (tripLegs.isNotEmpty) return this;
    final legs = _ensureDefaultLegs(
      {
        'requestId': requestId,
        'fromLocation': fromLocation,
        'toLocation': toLocation,
        'purpose': purpose,
      },
      const [],
    );
    if (legs.isEmpty) return this;
    return copyWith(tripLegs: legs).withRecalculatedSummary();
  }

  TripLegModel? get activeLeg {
    if (tripLegs.isEmpty) return null;
    final index = currentLegIndex.clamp(0, tripLegs.length - 1);
    return tripLegs[index];
  }

  /// Backend flag when present; otherwise derived from active leg punches.
  bool get hasDeparted {
    if (tripLegs.length > 1) return activeLeg?.hasDeparted ?? false;
    if (apiHasDeparted != null) return apiHasDeparted!;
    return activeLeg?.hasDeparted ?? false;
  }

  /// Backend flag when present; otherwise derived from active leg state.
  bool get canMarkArrival {
    if (tripLegs.length > 1) {
      final leg = activeLeg;
      if (leg == null) return false;
      return leg.hasDeparted && !leg.hasArrived;
    }
    if (apiCanMarkArrival != null) return apiCanMarkArrival!;
    final leg = activeLeg;
    if (leg == null) return false;
    return leg.hasDeparted && !leg.hasArrived;
  }

  /// Next punch type for [activeLeg], or null when the leg is complete.
  String? get nextPunchTypeForActiveLeg {
    final leg = activeLeg;
    if (leg == null) return null;
    if (leg.departurePunch == null) return 'travel_departure';
    if (leg.arrivalPunch == null) return 'travel_arrival';
    if (!leg.isReturnLeg && leg.meetingStartPunch == null) {
      return 'meeting_start';
    }
    if (!leg.isReturnLeg && leg.meetingEndPunch == null) {
      return 'meeting_end';
    }
    return null;
  }

  String get displayId =>
      requestId.isNotEmpty ? requestId : tripId;

  /// Primary id for REST paths — prefers [requestId], then [tripId].
  String get restResourceId {
    if (requestId.isNotEmpty) return requestId;
    if (tripId.isNotEmpty) return tripId;
    final m = mongoDocumentId;
    if (m != null && m.isNotEmpty) return m;
    return '';
  }

  /// True when the active leg is return travel with departure punched but not arrival.
  /// Used when backend `status` is out of sync (e.g. Completed) so the user can still punch.
  bool get needsReturnArrivalPunch {
    final leg = activeLeg;
    if (leg == null) return false;
    return leg.isReturnLeg &&
        leg.departurePunch != null &&
        leg.arrivalPunch == null;
  }

  bool get canAddNextClient {
    if (tripLegs.isEmpty || status == AppConstants.statusCompleted) return false;
    // Block while any forward leg is still in progress (e.g. leg 2 not started).
    if (tripLegs.any((leg) => !leg.isReturnLeg && !leg.isComplete)) {
      return false;
    }
    final lastForward = tripLegs.lastWhere(
      (leg) => !leg.isReturnLeg,
      orElse: () => tripLegs.last,
    );
    return lastForward.isComplete;
  }

  bool get canStartReturnTrip => canAddNextClient;

  String get routeSummary {
    if (tripLegs.isEmpty) {
      return '$fromLocation -> $toLocation';
    }
    final locations = <String>[
      tripLegs.first.fromLocation,
    ];
    locations.addAll(
      tripLegs.map((leg) => leg.toLocation),
    );
    return locations.where((location) => location.trim().isNotEmpty).join(' -> ');
  }

  String get displayFromLocation => fromLocation;

  String get displayToLocation {
    if (tripLegs.isEmpty) return toLocation;
    if (tripLegs.length == 1) {
      return tripLegs.first.toLocation;
    }
    return '${tripLegs.length} stops';
  }

  /// Simple from → to line for home/list cards (no per-leg client names).
  String get cardRouteSummary {
    final from = displayFromLocation;
    final to = displayToLocation;
    if (from.isEmpty && to.isEmpty) return '';
    if (to.isEmpty) return from;
    if (from.isEmpty) return to;
    return '$from → $to';
  }

  /// Short stop chain for list cards, e.g. `Rayzon Solar → Tarun → Return`.
  String get compactLegsSummary {
    if (tripLegs.isEmpty) {
      return '$fromLocation → $toLocation';
    }
    final labels = <String>[
      tripLegs.first.fromLocation,
      ...tripLegs.map(_compactLegLabel),
    ];
    return labels.where((label) => label.trim().isNotEmpty).join(' → ');
  }

  /// Best distance for allowance: sane leg total, API total, or odometer meters.
  double get effectiveDistanceKm {
    final saneLegsKm = _calculateSummary(tripLegs).totalDistanceKm;
    if (saneLegsKm > 0) {
      if (totalDistanceKm <= 0) return saneLegsKm;
      // Prefer GPS/sane legs when stored trip total was inflated by bad match.
      if (totalDistanceKm > saneLegsKm * DistanceSanity.maxOfficialVsGpsRatio &&
          totalDistanceKm - saneLegsKm > DistanceSanity.minAbsDeltaKm) {
        return saneLegsKm;
      }
      if (DistanceSanity.isOfficialAbsurd(
        officialKm: totalDistanceKm,
        gpsKm: saneLegsKm,
        travelMinutes: totalTravelDurationMinutes,
      )) {
        return saneLegsKm;
      }
      return totalDistanceKm;
    }
    if (totalDistanceKm > 0) return totalDistanceKm;
    final meters = distance ?? 0;
    if (meters > 0) return meters / 1000;
    return 0;
  }

  /// True when any leg has backend-matched official km that passes sanity.
  bool get hasOfficialDistance =>
      tripLegs.any((l) => l.hasOfficialDistance);

  String get displayDistanceLabel {
    if (hasOfficialDistance) return 'Official';
    if (tripLegs.any((l) =>
        l.provisionalDistanceKm != null ||
        l.actualDistanceKmFromTrack != null)) {
      return 'Approx (GPS)';
    }
    return 'Travelled';
  }

  /// Drop absurd official km / matched polylines (teleport leftovers) and
  /// recompute totals so details matches the list GPS distance.
  TravelRequestModel sanitizeAbsurdOfficialDistances() {
    var changed = false;
    final cleaned = tripLegs.map((leg) {
      if (!leg.hasAbsurdOfficialDistance) return leg;
      changed = true;
      return leg.copyWith(
        clearOfficialDistanceKm: true,
        clearMatchedRoutePolylineEncoded: true,
        clearMatchConfidence: true,
        clearEstimatedPct: true,
      );
    }).toList();
    if (!changed) {
      // Still recompute if total was inflated vs leg GPS.
      final sane = _calculateSummary(tripLegs).totalDistanceKm;
      if (totalDistanceKm > 0 &&
          sane > 0 &&
          totalDistanceKm > sane * DistanceSanity.maxOfficialVsGpsRatio &&
          totalDistanceKm - sane > DistanceSanity.minAbsDeltaKm) {
        return copyWith(tripLegs: tripLegs).withRecalculatedSummary();
      }
      return this;
    }
    return copyWith(tripLegs: cleaned).withRecalculatedSummary();
  }

  /// Allowance from API or distance × vehicle/fuel rate (₹/km).
  double get displayTravelAllowance {
    final km = effectiveDistanceKm;
    final rate = fuelRatePerKm;
    if (rate != null && rate > 0 && km > 0) {
      return (km * rate * 100).round() / 100;
    }
    if (travelAllowance > 0) return travelAllowance;
    return 0;
  }

  bool get shouldShowTravelAllowance =>
      AppConstants.vehicleRequiresFuelType(vehicleType) &&
      fuelType != null &&
      fuelType!.trim().isNotEmpty;

  String get compactMetricsSummary {
    final parts = <String>[];
    final km = effectiveDistanceKm;
    final hasStartedOrFinished = status != 'Ready To Start' && status != 'Start Missing';
    if (km > 0 || hasStartedOrFinished) {
      parts.add('${km.toStringAsFixed(1)} km');
    }
    if (totalTravelDurationMinutes > 0) {
      parts.add('${_formatCompactDuration(totalTravelDurationMinutes)} travel');
    }
    if (totalMeetings > 0) {
      parts.add('$totalMeetings ${totalMeetings == 1 ? 'meeting' : 'meetings'}');
    }
    if (totalMeetingDurationMinutes > 0) {
      parts.add('${_formatCompactDuration(totalMeetingDurationMinutes)} meeting time');
    }
    if (shouldShowTravelAllowance) {
      if (fuelRatePerKm != null && fuelRatePerKm! > 0) {
        if (displayTravelAllowance > 0) {
          parts.add('${formatTravelAllowance(displayTravelAllowance)} (₹${fuelRatePerKm!.toStringAsFixed(0)}/km)');
        } else {
          parts.add('₹${fuelRatePerKm!.toStringAsFixed(0)}/km');
        }
      } else {
        if (displayTravelAllowance > 0) {
          parts.add(formatTravelAllowance(displayTravelAllowance));
        }
      }
    }
    return parts.join(' · ');
  }

  static String formatTravelAllowance(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toStringAsFixed(0)} allowance';
    }
    return '₹${amount.toStringAsFixed(2)} allowance';
  }

  static String formatAllowanceAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toStringAsFixed(0)}';
    }
    return '₹${amount.toStringAsFixed(2)}';
  }

  static String _compactLegLabel(TripLegModel leg) {
    if (leg.isReturnLeg) {
      final dest = leg.toLocation;
      return dest.isNotEmpty ? 'Return to $dest' : 'Return';
    }
    return leg.toLocation;
  }

  static String _formatCompactDuration(int minutes) {
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours == 0) return '${remainingMinutes}m';
    if (remainingMinutes == 0) return '${hours}h';
    return '${hours}h ${remainingMinutes}m';
  }

  /// Id for `GET|PATCH /travel-requests/:id` — NestJS looks up by `requestId` (UUID).
  // restResourceId defined above with tripId fallback.

  /// Keeps local legs, punches, and locations when the API omits them on poll.
  TravelRequestModel mergePreservingLocalProgress(TravelRequestModel local) {
    final mergedFrom = fromLocation.trim().isNotEmpty
        ? fromLocation
        : local.fromLocation;
    final mergedTo =
        toLocation.trim().isNotEmpty ? toLocation : local.toLocation;

    var mergedLegs = _mergeLegPunches(tripLegs, local.tripLegs);
    if (mergedLegs.isEmpty) {
      mergedLegs = _ensureDefaultLegs(
        {
          'requestId': requestId.isNotEmpty ? requestId : local.requestId,
          'fromLocation': mergedFrom,
          'toLocation': mergedTo,
          'purpose': purpose ?? local.purpose,
          'clientName': _clientNameFromLegs(tripLegs).isNotEmpty
              ? _clientNameFromLegs(tripLegs)
              : _clientNameFromLegs(local.tripLegs),
        },
        const [],
      );
    }

    final merged = copyWith(
      fromLocation: mergedFrom,
      toLocation: mergedTo,
      userName: userName.trim().isNotEmpty ? userName : local.userName,
      employeeCode: (employeeCode ?? '').trim().isNotEmpty
          ? employeeCode
          : local.employeeCode,
      city: city.trim().isNotEmpty ? city : local.city,
      vehicleType: vehicleType.trim().isNotEmpty ? vehicleType : local.vehicleType,
      fuelType: fuelType ?? local.fuelType,
      totalDistanceKm:
          totalDistanceKm > 0 ? totalDistanceKm : local.totalDistanceKm,
      travelAllowance:
          travelAllowance > 0 ? travelAllowance : local.travelAllowance,
      fuelRatePerKm: fuelRatePerKm ?? local.fuelRatePerKm,
      clientName: clientName.isNotEmpty ? clientName : local.clientName,
      purpose: purpose ?? local.purpose,
      notes: notes ?? local.notes,
      startCoordinates: startCoordinates ?? local.startCoordinates,
      endCoordinates: endCoordinates ?? local.endCoordinates,
      startAddress: startAddress ?? local.startAddress,
      endAddress: endAddress ?? local.endAddress,
      startImageUrl: startImageUrl ?? local.startImageUrl,
      endImageUrl: endImageUrl ?? local.endImageUrl,
      tripLegs: mergedLegs,
      punches: punches.isNotEmpty ? punches : local.punches,
      apiHasDeparted: apiHasDeparted ?? local.apiHasDeparted,
      apiCanMarkArrival: apiCanMarkArrival ?? local.apiCanMarkArrival,
      isActive: isActive || local.isActive,
      routePoints: routePoints.isNotEmpty ? routePoints : local.routePoints,
      rawStatus: rawStatus ?? local.rawStatus,
      tripId: tripId.isNotEmpty ? tripId : local.tripId,
      trackingSessionId: trackingSessionId ?? local.trackingSessionId,
      tripStartedAt: tripStartedAt ?? local.tripStartedAt,
      tripEndedAt: tripEndedAt ?? local.tripEndedAt,
      trackingStatus: trackingStatus ?? local.trackingStatus,
      routePointCount:
          routePointCount > 0 ? routePointCount : local.routePointCount,
      mongoDocumentId: mongoDocumentId ?? local.mongoDocumentId,
      totalTravelDurationMinutes: totalTravelDurationMinutes > 0
          ? totalTravelDurationMinutes
          : local.totalTravelDurationMinutes,
      totalMeetingDurationMinutes: totalMeetingDurationMinutes > 0
          ? totalMeetingDurationMinutes
          : local.totalMeetingDurationMinutes,
      totalMeetings: totalMeetings > 0 ? totalMeetings : local.totalMeetings,
    ).withRecalculatedSummary();

    // Recalc can zero card metrics when a partial payload omitted punches;
    // keep the richer values so home cards don't lose fields after details.
    return merged.copyWith(
      vehicleType: merged.vehicleType.trim().isNotEmpty
          ? merged.vehicleType
          : local.vehicleType,
      fuelType: merged.fuelType ?? local.fuelType,
      fuelRatePerKm: merged.fuelRatePerKm ?? local.fuelRatePerKm,
      travelAllowance: merged.travelAllowance > 0
          ? merged.travelAllowance
          : local.travelAllowance,
      totalDistanceKm: merged.totalDistanceKm > 0
          ? merged.totalDistanceKm
          : local.totalDistanceKm,
      totalTravelDurationMinutes: merged.totalTravelDurationMinutes > 0
          ? merged.totalTravelDurationMinutes
          : local.totalTravelDurationMinutes,
      totalMeetingDurationMinutes: merged.totalMeetingDurationMinutes > 0
          ? merged.totalMeetingDurationMinutes
          : local.totalMeetingDurationMinutes,
      totalMeetings:
          merged.totalMeetings > 0 ? merged.totalMeetings : local.totalMeetings,
      userName: merged.userName.trim().isNotEmpty ? merged.userName : local.userName,
      clientName:
          merged.clientName.isNotEmpty ? merged.clientName : local.clientName,
    );
  }

  static List<TripLegModel> _mergeLegPunches(
    List<TripLegModel> remote,
    List<TripLegModel> local,
  ) {
    if (local.any((l) =>
        l.hasDeparted || l.hasArrived || l.isMeetingStarted || l.isMeetingComplete)) {
      if (remote.isEmpty) return local;
    } else if (remote.isNotEmpty) {
      return remote;
    } else {
      return local;
    }

    final remoteById = {for (final leg in remote) leg.legId: leg};
    final merged = <TripLegModel>[];

    for (final localLeg in local) {
      var remoteLeg = remoteById.remove(localLeg.legId);
      if (remoteLeg == null) {
        // Fallback: match by sequence and return leg status if legId mismatch exists
        final matchedKey = remoteById.keys.firstWhere(
          (k) => remoteById[k]!.sequence == localLeg.sequence &&
                 remoteById[k]!.isReturnLeg == localLeg.isReturnLeg,
          orElse: () => '',
        );
        if (matchedKey.isNotEmpty) {
          remoteLeg = remoteById.remove(matchedKey);
        }
      }

      if (remoteLeg == null) {
        if (localLeg.isReturnLeg) continue;
        merged.add(localLeg);
        continue;
      }
      merged.add(
        remoteLeg
            .copyWith(
              fromLocation: remoteLeg.fromLocation.isNotEmpty
                  ? remoteLeg.fromLocation
                  : localLeg.fromLocation,
              toLocation: remoteLeg.toLocation.isNotEmpty
                  ? remoteLeg.toLocation
                  : localLeg.toLocation,
              clientName: remoteLeg.clientName.isNotEmpty
                  ? remoteLeg.clientName
                  : localLeg.clientName,
              purpose: remoteLeg.purpose.isNotEmpty
                  ? remoteLeg.purpose
                  : localLeg.purpose,
              departurePunch:
                  remoteLeg.departurePunch ?? localLeg.departurePunch,
              arrivalPunch: remoteLeg.arrivalPunch ?? localLeg.arrivalPunch,
              meetingStartPunch:
                  remoteLeg.meetingStartPunch ?? localLeg.meetingStartPunch,
              meetingEndPunch:
                  remoteLeg.meetingEndPunch ?? localLeg.meetingEndPunch,
              routePolylineEncoded: remoteLeg.routePolylineEncoded ??
                  localLeg.routePolylineEncoded,
              actualDistanceKmFromTrack: remoteLeg.actualDistanceKmFromTrack ??
                  localLeg.actualDistanceKmFromTrack,
              trackMovingDurationMinutes:
                  remoteLeg.trackMovingDurationMinutes ??
                      localLeg.trackMovingDurationMinutes,
              trackStoppedDurationMinutes:
                  remoteLeg.trackStoppedDurationMinutes ??
                      localLeg.trackStoppedDurationMinutes,
              officialDistanceKm: _preferSaneOfficialKm(
                remote: remoteLeg,
                local: localLeg,
              ),
              provisionalDistanceKm: remoteLeg.provisionalDistanceKm ??
                  localLeg.provisionalDistanceKm,
              matchedRoutePolylineEncoded: _preferSaneMatchedPolyline(
                remote: remoteLeg,
                local: localLeg,
              ),
              matchConfidence:
                  remoteLeg.matchConfidence ?? localLeg.matchConfidence,
              estimatedPct: remoteLeg.estimatedPct ?? localLeg.estimatedPct,
            )
            .withRecalculatedMetrics(),
      );
    }

    merged.addAll(remoteById.values);

    // Keep locally added forward legs when server poll is behind.
    if (local.length > merged.length) {
      for (var i = merged.length; i < local.length; i++) {
        final localLeg = local[i];
        if (!localLeg.isReturnLeg) merged.add(localLeg);
      }
    }

    return merged;
  }

  TravelRequestModel withRecalculatedSummary({String? statusOverride}) {
    final normalizedLegs = _sanitizeLegPunches(
      tripLegs.map((leg) => leg.withRecalculatedMetrics()).toList(),
    );
    final summary = _calculateSummary(normalizedLegs);
    final derivedStatus = statusOverride ?? _deriveStatus(normalizedLegs);
    final legDistanceKm = summary.totalDistanceKm;
    final effectiveDistanceKm = legDistanceKm > 0
        ? legDistanceKm
        : (totalDistanceKm > 0 ? totalDistanceKm : _metersToKm(distance));

    var allowance = travelAllowance;
    final rate = fuelRatePerKm;
    if (rate != null && rate > 0 && effectiveDistanceKm > 0) {
      allowance = (effectiveDistanceKm * rate * 100).round() / 100;
    }

    return copyWith(
      status: derivedStatus,
      tripLegs: normalizedLegs,
      stops: normalizedLegs.map((leg) => leg.toMap()).toList(),
      totalDistanceKm: effectiveDistanceKm,
      totalTravelDurationMinutes: summary.totalTravelDurationMinutes,
      totalMeetingDurationMinutes: summary.totalMeetingDurationMinutes,
      totalMeetings: summary.totalMeetings,
      currentLegIndex: _currentLegIndex(normalizedLegs),
      totalMovingMinutesFromTrack: summary.totalMovingMinutesFromTrack,
      totalStoppedMinutesFromTrack: summary.totalStoppedMinutesFromTrack,
      travelAllowance: allowance,
    );
  }

  static double _metersToKm(double? meters) {
    final value = meters ?? 0;
    return value > 0 ? value / 1000 : 0;
  }

  Map<String, dynamic> toMap() {
    final legMaps = tripLegs.map((leg) => leg.toMap()).toList();

    return {
      'requestId': requestId,
      if (tripId.isNotEmpty) 'tripId': tripId,
      if (mongoDocumentId != null && mongoDocumentId!.isNotEmpty)
        '_id': mongoDocumentId,
      'userId': userId,
      'name': userName,
      'userName': userName,
      if ((employeeCode ?? '').isNotEmpty) 'employeeCode': employeeCode,
      'city': city,
      'fromLocation': fromLocation,
      'toLocation': toLocation,
      if (clientName.trim().isNotEmpty) 'clientName': clientName.trim(),
      if (tripLegs.isNotEmpty &&
          tripLegs.first.clientName.trim().isNotEmpty &&
          clientName.trim().isEmpty)
        'clientName': tripLegs.first.clientName.trim(),
      'vehicleType': vehicleType,
      if (fuelType != null) 'fuelType': fuelType,
      if (purpose != null) 'purpose': purpose,
      if (notes != null) 'notes': notes,
      'requestDate': requestDate.toIso8601String(),
      'status': status,
      if (rawStatus != null) 'rawStatus': rawStatus,
      'hasDeparted': hasDeparted,
      'canMarkArrival': canMarkArrival,
      'isActive': isActive,
      'startImageUrl': startImageUrl,
      'endImageUrl': endImageUrl,
      'startCoordinates': startCoordinates,
      'endCoordinates': endCoordinates,
      'startAddress': startAddress,
      'endAddress': endAddress,
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'distance': distance,
      'startOdometerReading': startOdometerReading,
      'endOdometerReading': endOdometerReading,
      'stops': legMaps,
      'tripLegs': legMaps,
      if (punches.isNotEmpty)
        'punches': punches.map((p) => p.toMap()).toList(),
      if (routePoints.isNotEmpty) 'routePoints': routePoints,
      'totalDistanceKm': totalDistanceKm,
      'totalTravelDurationMinutes': totalTravelDurationMinutes,
      'totalMeetingDurationMinutes': totalMeetingDurationMinutes,
      'totalMeetings': totalMeetings,
      'currentLegIndex': currentLegIndex,
      'trackingSessionId': trackingSessionId,
      'tripStartedAt': tripStartedAt?.toIso8601String(),
      'tripEndedAt': tripEndedAt?.toIso8601String(),
      'trackingStatus': trackingStatus,
      'enableLiveTracking': enableLiveTracking,
      'routePointCount': routePointCount,
      'totalMovingMinutesFromTrack': totalMovingMinutesFromTrack,
      'totalStoppedMinutesFromTrack': totalStoppedMinutesFromTrack,
      if (travelAllowance > 0) 'travelAllowance': travelAllowance,
      if (fuelRatePerKm != null) 'fuelRatePerKm': fuelRatePerKm,
      'createdAt': requestDate.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  TravelRequestModel copyWith({
    String? requestId,
    String? tripId,
    String? clientName,
    String? userId,
    String? userName,
    String? employeeCode,
    String? city,
    String? fromLocation,
    String? toLocation,
    String? vehicleType,
    String? fuelType,
    String? purpose,
    String? notes,
    DateTime? requestDate,
    String? status,
    String? rawStatus,
    String? startImageUrl,
    String? endImageUrl,
    Map<String, double>? startCoordinates,
    Map<String, double>? endCoordinates,
    String? startAddress,
    String? endAddress,
    DateTime? startTime,
    DateTime? endTime,
    double? distance,
    double? startOdometerReading,
    double? endOdometerReading,
    List<Map<String, dynamic>>? stops,
    List<TripLegModel>? tripLegs,
    List<TripPunchModel>? punches,
    bool? apiHasDeparted,
    bool? apiCanMarkArrival,
    bool? isActive,
    List<Map<String, dynamic>>? routePoints,
    double? totalDistanceKm,
    int? totalTravelDurationMinutes,
    int? totalMeetingDurationMinutes,
    int? totalMeetings,
    int? currentLegIndex,
    String? trackingSessionId,
    DateTime? tripStartedAt,
    DateTime? tripEndedAt,
    String? trackingStatus,
    bool? enableLiveTracking,
    int? routePointCount,
    int? totalMovingMinutesFromTrack,
    int? totalStoppedMinutesFromTrack,
    double? travelAllowance,
    double? fuelRatePerKm,
    String? mongoDocumentId,
  }) {
    return TravelRequestModel(
      requestId: requestId ?? this.requestId,
      tripId: tripId ?? this.tripId,
      clientName: clientName ?? this.clientName,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      employeeCode: employeeCode ?? this.employeeCode,
      city: city ?? this.city,
      fromLocation: fromLocation ?? this.fromLocation,
      toLocation: toLocation ?? this.toLocation,
      vehicleType: vehicleType ?? this.vehicleType,
      fuelType: fuelType ?? this.fuelType,
      purpose: purpose ?? this.purpose,
      notes: notes ?? this.notes,
      requestDate: requestDate ?? this.requestDate,
      status: status ?? this.status,
      rawStatus: rawStatus ?? this.rawStatus,
      startImageUrl: startImageUrl ?? this.startImageUrl,
      endImageUrl: endImageUrl ?? this.endImageUrl,
      startCoordinates: startCoordinates ?? this.startCoordinates,
      endCoordinates: endCoordinates ?? this.endCoordinates,
      startAddress: startAddress ?? this.startAddress,
      endAddress: endAddress ?? this.endAddress,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      distance: distance ?? this.distance,
      startOdometerReading: startOdometerReading ?? this.startOdometerReading,
      endOdometerReading: endOdometerReading ?? this.endOdometerReading,
      stops: stops ?? this.stops,
      trackingSessionId: trackingSessionId ?? this.trackingSessionId,
      tripStartedAt: tripStartedAt ?? this.tripStartedAt,
      tripEndedAt: tripEndedAt ?? this.tripEndedAt,
      trackingStatus: trackingStatus ?? this.trackingStatus,
      enableLiveTracking: enableLiveTracking ?? this.enableLiveTracking,
      punches: punches ?? this.punches,
      apiHasDeparted: apiHasDeparted ?? this.apiHasDeparted,
      apiCanMarkArrival: apiCanMarkArrival ?? this.apiCanMarkArrival,
      isActive: isActive ?? this.isActive,
      routePoints: routePoints ?? this.routePoints,
      tripLegs: tripLegs ?? this.tripLegs,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      totalTravelDurationMinutes:
          totalTravelDurationMinutes ?? this.totalTravelDurationMinutes,
      totalMeetingDurationMinutes:
          totalMeetingDurationMinutes ?? this.totalMeetingDurationMinutes,
      totalMeetings: totalMeetings ?? this.totalMeetings,
      currentLegIndex: currentLegIndex ?? this.currentLegIndex,
      routePointCount: routePointCount ?? this.routePointCount,
      totalMovingMinutesFromTrack:
          totalMovingMinutesFromTrack ?? this.totalMovingMinutesFromTrack,
      totalStoppedMinutesFromTrack:
          totalStoppedMinutesFromTrack ?? this.totalStoppedMinutesFromTrack,
      travelAllowance: travelAllowance ?? this.travelAllowance,
      fuelRatePerKm: fuelRatePerKm ?? this.fuelRatePerKm,
      mongoDocumentId: mongoDocumentId ?? this.mongoDocumentId,
    );
  }

  /// Display name for admin/manager lists (falls back to employee code).
  String get displayUserName {
    final n = userName.trim();
    if (n.isNotEmpty) return n;
    final code = employeeCode?.trim() ?? '';
    if (code.isNotEmpty) return code;
    return 'Employee';
  }

  static String _pickUserName(
    Map<String, dynamic> data,
    Map<String, dynamic>? userMap,
  ) {
    // Backend contract: creator name is `item.user.name` only.
    final name = userMap?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    return '';
  }

  static dynamic _nonEmptyStops(dynamic stops) {
    if (stops is List && stops.isNotEmpty) return stops;
    return null;
  }

  static String _clientNameFromLegs(List<TripLegModel> legs) {
    for (final leg in legs) {
      if (leg.clientName.trim().isNotEmpty) return leg.clientName.trim();
    }
    return '';
  }

  static List<TripLegModel> _parseTripLegs(dynamic data) {
    if (data == null || data is! List) return [];
    return data.map((item) => TripLegModel.fromMap(item)).toList();
  }

  /// API `currentLeg` is 1-based; `currentLegIndex` is 0-based.
  static int _resolveCurrentLegIndex(
    Map<String, dynamic> data,
    List<TripLegModel> legs,
  ) {
    final derived = _currentLegIndex(legs);

    // Multi-leg trips: always target the first incomplete leg (server often
    // still reports currentLeg=1 after add-next-client).
    if (legs.length > 1) return derived;

    final index = _parseInt(data['currentLegIndex']);
    if (index != null) return index.clamp(0, legs.isEmpty ? 0 : legs.length - 1);
    final leg = _parseInt(data['currentLeg']);
    if (leg != null && leg > 0) {
      return (leg - 1).clamp(0, legs.isEmpty ? 0 : legs.length - 1);
    }
    return derived;
  }

  static List<TripPunchModel> _parsePunches(dynamic data) {
    if (data == null || data is! List) return [];
    return data
        .map((item) => TripPunchModel.fromMap(item))
        .where((p) => p.type.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> _parseRoutePoints(dynamic data) {
    if (data == null || data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return null;
  }

  /// Builds one outbound leg when the API only stores top-level from/to locations.
  static List<TripLegModel> _ensureDefaultLegs(
    Map<String, dynamic> data,
    List<TripLegModel> legs,
  ) {
    if (legs.isNotEmpty) return legs;

    final from = data['fromLocation']?.toString().trim() ?? '';
    final to = data['toLocation']?.toString().trim() ?? '';
    if (from.isEmpty && to.isEmpty) return legs;

    final tripId = data['requestId']?.toString() ??
        data['id']?.toString() ??
        data['tripId']?.toString() ??
        '';
    final purpose = data['purpose']?.toString().trim() ?? '';
    final clientName = data['clientName']?.toString().trim() ?? '';

    return [
      TripLegModel(
        legId: tripId.isNotEmpty ? '${tripId}_leg_1' : 'leg_1',
        sequence: 1,
        fromLocation: from,
        toLocation: to,
        clientName: clientName.isNotEmpty
            ? clientName
            : (purpose.isNotEmpty ? purpose : to),
        purpose: purpose,
        clientOfficeAddress: to,
      ),
    ];
  }

  static List<Map<String, dynamic>>? _parseStops(dynamic stops) {
    if (stops == null || stops is! List) return null;
    return stops.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Map<String, double>? _parseCoordinates(dynamic coordinates) {
    if (coordinates == null || coordinates is! Map) return null;
    final map = Map<String, dynamic>.from(coordinates);
    final latitude = _parseDouble(map['latitude']);
    final longitude = _parseDouble(map['longitude']);
    if (latitude == null || longitude == null) return null;
    return {'latitude': latitude, 'longitude': longitude};
  }

  static Map<String, double>? _parseLatLngFields(
    Map<String, dynamic> data,
    String latKey,
    String lngKey,
  ) {
    final latitude = _parseDouble(data[latKey]);
    final longitude = _parseDouble(data[lngKey]);
    if (latitude == null || longitude == null) return null;
    return {'latitude': latitude, 'longitude': longitude};
  }

  static Map<String, double>? _parseOriginFromCoordinates(dynamic coordinates) {
    if (coordinates == null || coordinates is! Map) return null;
    final map = Map<String, dynamic>.from(coordinates);
    return _parseLatLngFields(map, 'originLat', 'originLng');
  }

  static Map<String, double>? _parseDestinationCoordinates(dynamic coordinates) {
    if (coordinates == null || coordinates is! Map) return null;
    final map = Map<String, dynamic>.from(coordinates);
    final latitude = _parseDouble(map['destinationLat']);
    final longitude = _parseDouble(map['destinationLng']);
    if (latitude == null || longitude == null) return null;
    return {'latitude': latitude, 'longitude': longitude};
  }

  static double? _preferSaneOfficialKm({
    required TripLegModel remote,
    required TripLegModel local,
  }) {
    final gps = remote.provisionalDistanceKm ??
        remote.actualDistanceKmFromTrack ??
        local.provisionalDistanceKm ??
        local.actualDistanceKmFromTrack;
    final minutes =
        remote.travelDurationMinutes ?? local.travelDurationMinutes;
    final planned = remote.plannedDistanceKm ?? local.plannedDistanceKm;

    for (final candidate in [
      remote.officialDistanceKm,
      local.officialDistanceKm,
    ]) {
      if (candidate == null || candidate <= 0) continue;
      if (!DistanceSanity.isOfficialAbsurd(
        officialKm: candidate,
        gpsKm: gps,
        plannedKm: planned,
        travelMinutes: minutes,
      )) {
        return candidate;
      }
    }
    return null;
  }

  static String? _preferSaneMatchedPolyline({
    required TripLegModel remote,
    required TripLegModel local,
  }) {
    final gps = remote.provisionalDistanceKm ??
        remote.actualDistanceKmFromTrack ??
        local.provisionalDistanceKm ??
        local.actualDistanceKmFromTrack;
    final minutes =
        remote.travelDurationMinutes ?? local.travelDurationMinutes;
    final planned = remote.plannedDistanceKm ?? local.plannedDistanceKm;

    bool absurd(TripLegModel leg) {
      final o = leg.officialDistanceKm;
      if (o == null || o <= 0) return false;
      return DistanceSanity.isOfficialAbsurd(
        officialKm: o,
        gpsKm: gps,
        plannedKm: planned,
        travelMinutes: minutes,
      );
    }

    if (remote.matchedRoutePolylineEncoded != null &&
        remote.matchedRoutePolylineEncoded!.isNotEmpty &&
        !absurd(remote)) {
      return remote.matchedRoutePolylineEncoded;
    }
    if (local.matchedRoutePolylineEncoded != null &&
        local.matchedRoutePolylineEncoded!.isNotEmpty &&
        !absurd(local)) {
      return local.matchedRoutePolylineEncoded;
    }
    return null;
  }

  static _TripSummary _calculateSummary(List<TripLegModel> legs) {
    double distKm(TripLegModel leg) =>
        DistanceSanity.selectLegKm(
          officialKm: leg.officialDistanceKm,
          provisionalKm: leg.provisionalDistanceKm,
          trackKm: leg.actualDistanceKmFromTrack,
          plannedKm: leg.plannedDistanceKm,
          punchKm: leg.actualDistanceKm,
          travelMinutes: leg.travelDurationMinutes,
        ) ??
        0;

    return _TripSummary(
      totalDistanceKm:
          legs.fold<double>(0, (total, leg) => total + distKm(leg)),
      totalTravelDurationMinutes: legs.fold<int>(
        0,
        (total, leg) => total + (leg.travelDurationMinutes ?? 0),
      ),
      totalMeetingDurationMinutes: legs.fold<int>(
        0,
        (total, leg) => total + (leg.meetingDurationMinutes ?? 0),
      ),
      totalMeetings: legs
          .where((leg) => !leg.isReturnLeg && leg.meetingEndPunch != null)
          .length,
      totalMovingMinutesFromTrack: legs.fold<int>(
        0,
        (total, leg) => total + (leg.trackMovingDurationMinutes ?? 0),
      ),
      totalStoppedMinutesFromTrack: legs.fold<int>(
        0,
        (total, leg) => total + (leg.trackStoppedDurationMinutes ?? 0),
      ),
    );
  }

  static int _currentLegIndex(List<TripLegModel> legs) {
    if (legs.isEmpty) return 0;
    final index = legs.indexWhere((leg) => !leg.isComplete);
    if (index == -1) return legs.length - 1;
    return index;
  }

  static String _normalizeStatus(dynamic status) {
    final value = status?.toString().trim() ?? '';
    if (value.isEmpty) return AppConstants.statusReadyToStart;
    final lower = value.toLowerCase().replaceAll('_', ' ');
    return switch (lower) {
      'created' => AppConstants.statusReadyToStart,
      'departed' => AppConstants.statusTravelling,
      'arrived' => AppConstants.statusAtClient,
      'meeting started' => AppConstants.statusInMeeting,
      'meeting completed' => AppConstants.statusReadyForNext,
      'return trip' => AppConstants.statusReadyToReturn,
      'at client' => AppConstants.statusAtClient,
      'in meeting' => AppConstants.statusInMeeting,
      'travelling' => AppConstants.statusTravelling,
      'ready for next' => AppConstants.statusReadyForNext,
      'ready to return' => AppConstants.statusReadyToReturn,
      'returning' => AppConstants.statusReturning,
      'completed' => AppConstants.statusCompleted,
      _ => value,
    };
  }

  /// Maps API punch type strings to the app's canonical punch types.
  static String normalizePunchType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final t = raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (t) {
      'departure' || 'travel_departure' => 'travel_departure',
      'arrival' || 'travel_arrival' => 'travel_arrival',
      'meetingstart' || 'meeting_start' => 'meeting_start',
      'meetingend' || 'meeting_end' => 'meeting_end',
      _ => t,
    };
  }

  static List<TripLegModel> _applyFlatPunchesToLegs(
    List<TripLegModel> legs,
    dynamic rawPunches,
  ) {
    if (legs.isEmpty || rawPunches is! List || rawPunches.isEmpty) {
      return legs;
    }

    final updated = List<TripLegModel>.from(legs);
    final multiLeg = updated.length > 1;

    for (final entry in rawPunches) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final punch = TripPunchModel.fromMap(map);
      final type = normalizePunchType(punch.type);
      if (type.isEmpty) continue;

      final legNumber = _parseInt(map['legNumber']) ?? _parseInt(map['leg']);
      final legIndex = legNumber != null
          ? (legNumber - 1).clamp(0, updated.length - 1)
          : multiLeg
              ? 0
              : _legIndexForPunch(updated, type);
      if (legIndex < 0 || legIndex >= updated.length) continue;

      final leg = updated[legIndex];
      updated[legIndex] = switch (type) {
        'travel_departure' => leg.copyWith(
            departurePunch: leg.departurePunch ?? punch,
          ),
        'travel_arrival' => leg.copyWith(
            arrivalPunch: leg.arrivalPunch ?? punch,
          ),
        'meeting_start' => leg.copyWith(
            meetingStartPunch: leg.meetingStartPunch ?? punch,
          ),
        'meeting_end' => leg.copyWith(
            meetingEndPunch: leg.meetingEndPunch ?? punch,
          ),
        _ => leg,
      }.withRecalculatedMetrics();
    }

    return updated;
  }

  /// Prevents global trip punches from leaking onto legs that have not started.
  static List<TripLegModel> _sanitizeLegPunches(List<TripLegModel> legs) {
    if (legs.isEmpty) return legs;

    TripLegModel cleared(TripLegModel leg) => leg
        .copyWith(
          departurePunch: null,
          arrivalPunch: null,
          meetingStartPunch: null,
          meetingEndPunch: null,
        )
        .withRecalculatedMetrics();

    var updated = List<TripLegModel>.from(legs);
    for (var i = 1; i < updated.length; i++) {
      final leg = updated[i];
      if (leg.isReturnLeg) continue;
      if (_legPunchesLookLeaked(leg, updated[i - 1])) {
        updated[i] = cleared(leg);
      }
    }

    final firstIncomplete = updated.indexWhere(
      (leg) => !leg.isReturnLeg && !leg.isComplete,
    );
    if (firstIncomplete < 0) return updated;

    return [
      for (var i = 0; i < updated.length; i++)
        if (i < firstIncomplete)
          updated[i]
        else if (i == firstIncomplete)
          updated[i].hasDeparted ? updated[i] : cleared(updated[i])
        else
          cleared(updated[i]),
    ];
  }

  /// Detects punches copied from an earlier leg (common when flat `punches[]` hydrate wrong).
  static bool _legPunchesLookLeaked(TripLegModel leg, TripLegModel previous) {
    final hasAnyPunch = leg.hasDeparted ||
        leg.hasArrived ||
        leg.isMeetingStarted ||
        leg.meetingEndPunch != null;
    if (!hasAnyPunch) return false;

    if (!previous.isReturnLeg && !previous.isComplete) return true;
    if (!leg.hasDeparted) return true;

    final departureTime = leg.departurePunch!.time;
    final previousDeparture = previous.departurePunch?.time;
    if (previousDeparture != null && departureTime == previousDeparture) {
      return true;
    }

    final previousEndedAt =
        previous.meetingEndPunch?.time ?? previous.arrivalPunch?.time;
    if (previousEndedAt != null && !departureTime.isAfter(previousEndedAt)) {
      return true;
    }

    return false;
  }

  static int _legIndexForPunch(List<TripLegModel> legs, String type) {
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      if (leg.isReturnLeg) continue;
      switch (type) {
        case 'travel_departure':
          if (leg.departurePunch == null) return i;
        case 'travel_arrival':
          if (leg.departurePunch != null && leg.arrivalPunch == null) return i;
        case 'meeting_start':
          if (leg.arrivalPunch != null && leg.meetingStartPunch == null) {
            return i;
          }
        case 'meeting_end':
          if (leg.meetingStartPunch != null && leg.meetingEndPunch == null) {
            return i;
          }
      }
    }
    final fallback = legs.indexWhere((l) => !l.isReturnLeg);
    return fallback >= 0 ? fallback : 0;
  }

  static String _pickDisplayStatus(String api, String derived) {
    if (derived == AppConstants.statusCompleted) return derived;
    if (api == AppConstants.statusCompleted) return api;

    const progression = [
      AppConstants.statusReadyToStart,
      AppConstants.statusTravelling,
      AppConstants.statusAtClient,
      AppConstants.statusInMeeting,
      AppConstants.statusReadyForNext,
      AppConstants.statusReadyToReturn,
      AppConstants.statusReturning,
      AppConstants.statusCompleted,
    ];

    int rank(String s) {
      final i = progression.indexOf(s);
      return i < 0 ? 0 : i;
    }

    if (rank(derived) > rank(api)) return derived;
    if (api.isNotEmpty) return api;
    return derived;
  }

  static String _deriveStatus(List<TripLegModel> legs) {
    if (legs.isEmpty) return 'Ready To Start';

    final current = legs[_currentLegIndex(legs)];

    if (current.isReturnLeg && current.arrivalPunch != null) {
      return 'Completed';
    }
    if (current.departurePunch == null) {
      return current.isReturnLeg ? 'Ready To Return' : 'Ready To Start';
    }
    if (current.arrivalPunch == null) {
      return current.isReturnLeg ? 'Returning' : 'Travelling';
    }
    if (current.isReturnLeg) {
      return 'Completed';
    }
    if (current.meetingStartPunch == null) {
      return 'At Client';
    }
    if (current.meetingEndPunch == null) {
      return 'In Meeting';
    }
    return 'Ready For Next';
  }
}

class _TripSummary {
  final double totalDistanceKm;
  final int totalTravelDurationMinutes;
  final int totalMeetingDurationMinutes;
  final int totalMeetings;
  final int totalMovingMinutesFromTrack;
  final int totalStoppedMinutesFromTrack;

  const _TripSummary({
    required this.totalDistanceKm,
    required this.totalTravelDurationMinutes,
    required this.totalMeetingDurationMinutes,
    required this.totalMeetings,
    required this.totalMovingMinutesFromTrack,
    required this.totalStoppedMinutesFromTrack,
  });
}

DateTime _parseDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.now();
}

DateTime? _parseDateTimeNullable(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _calculateDistanceKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double degree) => degree * math.pi / 180;

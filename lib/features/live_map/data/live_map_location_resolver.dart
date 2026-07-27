import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../modules/travel/data/models/travel_request_model.dart';
import '../../../modules/auth/data/models/user_model.dart';

/// Whether this trip should appear on the admin live map.
bool isLiveTravelTrip(TravelRequestModel request) {
  if (request.isActive) return true;
  final ts = request.trackingStatus?.toLowerCase();
  if (ts == 'tracking' || ts == 'paused') return true;
  return const {
    'Travelling',
    'Returning',
    'In Meeting',
    'At Client',
  }.contains(request.status);
}

LatLng? coordinatesFromMap(Map<String, dynamic>? coords) {
  if (coords == null) return null;
  final lat = (coords['latitude'] as num?)?.toDouble() ??
      (coords['lat'] as num?)?.toDouble();
  final lng = (coords['longitude'] as num?)?.toDouble() ??
      (coords['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  if (lat.abs() < 1e-6 && lng.abs() < 1e-6) return null;
  return LatLng(lat, lng);
}

/// Best-effort current position from an in-memory travel request.
LatLng? resolveLivePositionFromRequest(TravelRequestModel request) {
  if (request.routePoints.isNotEmpty) {
    for (final raw in request.routePoints.reversed) {
      final pos = coordinatesFromMap(raw);
      if (pos != null) return pos;
    }
  }

  for (final leg in request.tripLegs.reversed) {
    for (final punch in [
      leg.arrivalPunch,
      leg.meetingEndPunch,
      leg.meetingStartPunch,
      leg.departurePunch,
    ]) {
      if (punch == null) continue;
      if (punch.latitude.abs() < 1e-6 && punch.longitude.abs() < 1e-6) {
        continue;
      }
      return LatLng(punch.latitude, punch.longitude);
    }
  }

  for (final punch in request.punches.reversed) {
    if (punch.latitude.abs() < 1e-6 && punch.longitude.abs() < 1e-6) {
      continue;
    }
    return LatLng(punch.latitude, punch.longitude);
  }

  return coordinatesFromMap(request.startCoordinates);
}

/// Reads extra API location fields then falls back to [resolveLivePositionFromRequest].
LatLng? resolveLivePositionFromRow(Map<String, dynamic> row) {
  for (final key in [
    'currentLocation',
    'lastLocation',
    'liveLocation',
    'location',
    'lastKnownLocation',
  ]) {
    final value = row[key];
    if (value is Map) {
      final pos = coordinatesFromMap(Map<String, dynamic>.from(value));
      if (pos != null) return pos;
    }
  }

  final coords = row['coordinates'];
  if (coords is Map) {
    final pos = coordinatesFromMap(Map<String, dynamic>.from(coords));
    if (pos != null) return pos;
  }

  return resolveLivePositionFromRequest(
    TravelRequestModel.fromMap(row).ensureTripLegs(),
  );
}

LatLng? lastPointFromRoutePayload(List<Map<String, dynamic>> points) {
  for (final raw in points.reversed) {
    final pos = coordinatesFromMap(raw);
    if (pos != null) return pos;
  }
  return null;
}

String liveMapEmployeeId(TravelRequestModel request) {
  if (request.userId.isNotEmpty) return request.userId;
  return request.requestId;
}

bool isGenericEmployeeLabel(String? name) {
  final n = name?.trim().toLowerCase() ?? '';
  return n.isEmpty ||
      n == 'employee' ||
      n == 'user' ||
      n == 'unknown' ||
      n == 'on trip';
}

/// Resolves a display name from travel-request list row + parsed model.
String resolveEmployeeName(Map<String, dynamic> row, TravelRequestModel model) {
  final user = row['user'];
  if (user is Map) {
    final name = Map<String, dynamic>.from(user)['name']?.toString().trim();
    if (!isGenericEmployeeLabel(name)) return name!;
  }

  if (!isGenericEmployeeLabel(model.userName)) {
    return model.userName.trim();
  }

  final profile = profileHintsFromTravelRow(row);
  if (profile.employeeCode != null && profile.employeeCode!.isNotEmpty) {
    return profile.employeeCode!;
  }
  if (profile.email != null && profile.email!.contains('@')) {
    return profile.email!.split('@').first;
  }

  return 'On trip';
}

String? liveMapTeamLabel(Map<String, dynamic> row, TravelRequestModel request) {
  final user = row['user'];
  if (user is Map) {
    final map = Map<String, dynamic>.from(user);
    final team = map['sitingLocation']?.toString() ??
        map['sittingLocation']?.toString() ??
        map['team']?.toString();
    if (team != null && team.isNotEmpty) return team;
  }
  final city = request.city.trim();
  return city.isNotEmpty ? city : null;
}

/// Profile fields embedded in a travel-request list row (if API includes `user`).
({
  String? email,
  String? employeeCode,
  String? mobile,
  String? role,
  String? reportingManagerName,
}) profileHintsFromTravelRow(Map<String, dynamic> row) {
  final user = row['user'];
  if (user is Map) {
    final model = UserModel.fromApi(Map<String, dynamic>.from(user));
    return (
      email: model.email.isNotEmpty ? model.email : null,
      employeeCode:
          model.employeeCode.isNotEmpty ? model.employeeCode : null,
      mobile: model.mobile.isNotEmpty ? model.mobile : null,
      role: model.role.isNotEmpty ? model.role : null,
      reportingManagerName: model.reportingManagerName,
    );
  }

  String? pick(String key) {
    final v = row[key]?.toString();
    return v != null && v.isNotEmpty ? v : null;
  }

  return (
    email: pick('userEmail') ?? pick('email'),
    employeeCode: pick('employeeCode'),
    mobile: pick('mobile') ?? pick('mobileNumber'),
    role: pick('userRole') ?? pick('role'),
    reportingManagerName: pick('reportingManagerName'),
  );
}

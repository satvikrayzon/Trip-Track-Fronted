import 'package:equatable/equatable.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Live employee marker status for admin map.
enum TrackingMarkerStatus {
  active,
  online,
  gpsStopped,
  offline,
}

extension TrackingMarkerStatusX on TrackingMarkerStatus {
  int get colorValue => switch (this) {
        TrackingMarkerStatus.active => 0xFF4CAF50,
        TrackingMarkerStatus.online => 0xFF2196F3,
        TrackingMarkerStatus.gpsStopped => 0xFFF44336,
        TrackingMarkerStatus.offline => 0xFF9E9E9E,
      };

  String get label => switch (this) {
        TrackingMarkerStatus.active => 'Tracking',
        TrackingMarkerStatus.online => 'Online',
        TrackingMarkerStatus.gpsStopped => 'GPS paused',
        TrackingMarkerStatus.offline => 'Offline',
      };
}

class TrackedEmployee extends Equatable {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? team;
  final LatLng position;
  final double speedKmh;
  final int batteryPercent;
  final double bearing;
  final TrackingMarkerStatus status;
  final bool hasActiveTrip;
  final String? activeTripId;
  final DateTime lastUpdated;
  final String? email;
  final String? employeeCode;
  final String? mobile;
  final String? role;
  final String? reportingManagerName;
  final String? tripStatus;
  final String? tripFrom;
  final String? tripTo;
  final List<LatLng> path;

  const TrackedEmployee({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.team,
    required this.position,
    this.speedKmh = 0,
    this.batteryPercent = 100,
    this.bearing = 0,
    this.status = TrackingMarkerStatus.offline,
    this.hasActiveTrip = false,
    this.activeTripId,
    required this.lastUpdated,
    this.email,
    this.employeeCode,
    this.mobile,
    this.role,
    this.reportingManagerName,
    this.tripStatus,
    this.tripFrom,
    this.tripTo,
    this.path = const [],
  });

  bool get hasProfileHints =>
      (email != null && email!.isNotEmpty) ||
      (employeeCode != null && employeeCode!.isNotEmpty) ||
      (mobile != null && mobile!.isNotEmpty);

  TrackedEmployee copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? team,
    LatLng? position,
    double? speedKmh,
    int? batteryPercent,
    double? bearing,
    TrackingMarkerStatus? status,
    bool? hasActiveTrip,
    String? activeTripId,
    DateTime? lastUpdated,
    String? email,
    String? employeeCode,
    String? mobile,
    String? role,
    String? reportingManagerName,
    String? tripStatus,
    String? tripFrom,
    String? tripTo,
    List<LatLng>? path,
  }) {
    return TrackedEmployee(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      team: team ?? this.team,
      position: position ?? this.position,
      speedKmh: speedKmh ?? this.speedKmh,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      bearing: bearing ?? this.bearing,
      status: status ?? this.status,
      hasActiveTrip: hasActiveTrip ?? this.hasActiveTrip,
      activeTripId: activeTripId ?? this.activeTripId,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      email: email ?? this.email,
      employeeCode: employeeCode ?? this.employeeCode,
      mobile: mobile ?? this.mobile,
      role: role ?? this.role,
      reportingManagerName: reportingManagerName ?? this.reportingManagerName,
      tripStatus: tripStatus ?? this.tripStatus,
      tripFrom: tripFrom ?? this.tripFrom,
      tripTo: tripTo ?? this.tripTo,
      path: path ?? this.path,
    );
  }

  @override
  List<Object?> get props => [id, position, status, lastUpdated, path];

  /// Label for map markers and detail sheet.
  String get displayName {
    final realName = name.trim();
    final n = realName.toLowerCase();
    if (realName.isNotEmpty &&
        n != 'employee' &&
        n != 'user' &&
        n != 'unknown' &&
        n != 'on trip') {
      return realName;
    }
    if (employeeCode != null && employeeCode!.trim().isNotEmpty) {
      return employeeCode!.trim();
    }
    if (email != null && email!.contains('@')) {
      return email!.split('@').first;
    }
    return 'On trip';
  }

  String? get tripRouteLabel {
    final from = tripFrom?.trim();
    final to = tripTo?.trim();
    if (from == null || from.isEmpty || to == null || to.isEmpty) return null;
    return '$from → $to';
  }
}

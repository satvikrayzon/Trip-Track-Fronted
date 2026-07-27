import 'package:uuid/uuid.dart';

/// Device/session event for GPS tracking audit (uploaded in batches).
class TrackingEventModel {
  const TrackingEventModel({
    required this.eventId,
    required this.requestId,
    required this.type,
    required this.timestamp,
    this.legId,
    this.sessionId,
    this.metadata,
    this.isSynced = false,
  });

  final String eventId;
  final String requestId;
  final String? legId;
  final String? sessionId;
  final String type;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final bool isSynced;

  factory TrackingEventModel.create({
    required String requestId,
    required String type,
    DateTime? timestamp,
    String? legId,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) {
    return TrackingEventModel(
      eventId: const Uuid().v4(),
      requestId: requestId,
      legId: legId,
      sessionId: sessionId,
      type: type,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      metadata: metadata,
    );
  }

  factory TrackingEventModel.fromMap(Map map) {
    final m = Map<String, dynamic>.from(map);
    return TrackingEventModel(
      eventId: m['eventId']?.toString() ?? '',
      requestId: m['requestId']?.toString() ?? '',
      legId: m['legId']?.toString(),
      sessionId: m['sessionId']?.toString(),
      type: m['type']?.toString() ?? '',
      timestamp: _parseTime(m['timestamp']),
      metadata: m['metadata'] is Map
          ? Map<String, dynamic>.from(m['metadata'] as Map)
          : null,
      isSynced: m['isSynced'] == true,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'type': type,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (legId != null && legId!.isNotEmpty) 'legId': legId,
      if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    };
  }

  Map<String, dynamic> toHiveMap() {
    return {
      'eventId': eventId,
      'requestId': requestId,
      if (legId != null) 'legId': legId,
      if (sessionId != null) 'sessionId': sessionId,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
      'isSynced': isSynced,
    };
  }

  static DateTime _parseTime(dynamic v) {
    if (v == null) return DateTime.now().toUtc();
    if (v is String) {
      try {
        return DateTime.parse(v).toUtc();
      } catch (_) {
        return DateTime.now().toUtc();
      }
    }
    if (v is DateTime) return v.toUtc();
    return DateTime.now().toUtc();
  }
}

/// Canonical tracking event types (match backend).
abstract final class TrackingEventTypes {
  static const trackingStarted = 'tracking_started';
  static const trackingStopped = 'tracking_stopped';
  static const appBackground = 'app_background';
  static const appForeground = 'app_foreground';
  static const permissionDenied = 'permission_denied';
  static const osKillSuspected = 'os_kill_suspected';
  static const networkOffline = 'network_offline';
  static const networkOnline = 'network_online';
}

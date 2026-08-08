/// A single GPS sample for live trip tracking (local + REST API).
class RoutePointModel {
  final String pointId;
  final String requestId;
  final String legId;
  final String sessionId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final double? altitude;
  final bool isMoving;
  final bool isStopMarker;
  final String source;
  final bool isSynced;

  const RoutePointModel({
    required this.pointId,
    required this.requestId,
    required this.legId,
    required this.sessionId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.altitude,
    this.isMoving = true,
    this.isStopMarker = false,
    this.source = 'gps',
    this.isSynced = false,
  });

  factory RoutePointModel.fromMap(Map map) {
    final m = Map<String, dynamic>.from(map);
    return RoutePointModel(
      pointId: m['pointId'] as String? ?? '',
      requestId: m['requestId'] as String? ?? '',
      legId: m['legId'] as String? ?? '',
      sessionId: m['sessionId'] as String? ?? '',
      timestamp: _parseTime(m['timestamp']),
      latitude: (m['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (m['longitude'] as num?)?.toDouble() ?? 0,
      accuracy: (m['accuracy'] as num?)?.toDouble(),
      speed: (m['speed'] as num?)?.toDouble(),
      heading: (m['heading'] as num?)?.toDouble(),
      altitude: (m['altitude'] as num?)?.toDouble(),
      isMoving: m['isMoving'] == true,
      isStopMarker: m['isStopMarker'] == true,
      source: m['source'] as String? ?? 'gps',
      isSynced: m['isSynced'] == true,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'pointId': pointId,
      'requestId': requestId,
      'legId': legId,
      'sessionId': sessionId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'altitude': altitude,
      'isMoving': isMoving,
      'isStopMarker': isStopMarker,
      'source': source,
    };
  }

  Map<String, dynamic> toHiveMap() {
    return {
      'pointId': pointId,
      'requestId': requestId,
      'legId': legId,
      'sessionId': sessionId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'altitude': altitude,
      'isMoving': isMoving,
      'isStopMarker': isStopMarker,
      'source': source,
      'isSynced': isSynced,
    };
  }

  static DateTime _parseTime(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    if (v is int || v is double) {
      final n = (v as num).toDouble();
      if (n > 1e12) {
        return DateTime.fromMillisecondsSinceEpoch(n.round(), isUtc: true);
      }
      if (n > 1e9) {
        return DateTime.fromMillisecondsSinceEpoch(
          (n * 1000).round(),
          isUtc: true,
        );
      }
      return DateTime.now();
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return DateTime.now();
      final asNum = double.tryParse(s);
      if (asNum != null &&
          s.length >= 10 &&
          !s.contains('-') &&
          !s.contains('T')) {
        return _parseTime(asNum);
      }
      try {
        return DateTime.parse(s);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  RoutePointModel copyWith({bool? isSynced}) {
    return RoutePointModel(
      pointId: pointId,
      requestId: requestId,
      legId: legId,
      sessionId: sessionId,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
      altitude: altitude,
      isMoving: isMoving,
      isStopMarker: isStopMarker,
      source: source,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

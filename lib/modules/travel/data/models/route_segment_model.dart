/// How a reconstructed route piece was produced (backend map-matching).
enum RouteSegmentKind {
  /// Dense good GPS aligned to road edges.
  gpsVerified,

  /// Continuous but noisy GPS snapped via HMM / Snap-to-Roads.
  mapMatched,

  /// Topology fill across a GPS gap (lowest confidence).
  estimated,
}

extension RouteSegmentKindX on RouteSegmentKind {
  String get apiValue => switch (this) {
        RouteSegmentKind.gpsVerified => 'gps_verified',
        RouteSegmentKind.mapMatched => 'map_matched',
        RouteSegmentKind.estimated => 'estimated',
      };

  static RouteSegmentKind fromApi(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'gps_verified':
      case 'verified':
        return RouteSegmentKind.gpsVerified;
      case 'estimated':
      case 'gap':
        return RouteSegmentKind.estimated;
      case 'map_matched':
      case 'matched':
      default:
        return RouteSegmentKind.mapMatched;
    }
  }
}

/// One contiguous piece of the official reconstructed route.
class RouteSegmentModel {
  final String segId;
  final String? legId;
  final RouteSegmentKind kind;
  final double confidence;
  final double lengthM;
  final DateTime? fromTimestamp;
  final DateTime? toTimestamp;
  final String polylineEncoded;
  final String? matchMethod;

  const RouteSegmentModel({
    required this.segId,
    this.legId,
    required this.kind,
    required this.confidence,
    required this.lengthM,
    this.fromTimestamp,
    this.toTimestamp,
    required this.polylineEncoded,
    this.matchMethod,
  });

  factory RouteSegmentModel.fromMap(dynamic data) {
    if (data is! Map) {
      return const RouteSegmentModel(
        segId: '',
        kind: RouteSegmentKind.mapMatched,
        confidence: 0,
        lengthM: 0,
        polylineEncoded: '',
      );
    }
    final map = Map<String, dynamic>.from(data);
    return RouteSegmentModel(
      segId: map['segId']?.toString() ?? map['id']?.toString() ?? '',
      legId: map['legId']?.toString(),
      kind: RouteSegmentKindX.fromApi(map['kind']?.toString()),
      confidence: _d(map['confidence']) ?? 0,
      lengthM: _d(map['lengthM']) ?? _d(map['lengthMeters']) ?? 0,
      fromTimestamp: _t(map['fromTimestamp'] ?? map['fromT']),
      toTimestamp: _t(map['toTimestamp'] ?? map['toT']),
      polylineEncoded: map['polylineEncoded']?.toString() ??
          map['geomEncoded']?.toString() ??
          '',
      matchMethod: map['matchMethod']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'segId': segId,
        if (legId != null) 'legId': legId,
        'kind': kind.apiValue,
        'confidence': confidence,
        'lengthM': lengthM,
        if (fromTimestamp != null)
          'fromTimestamp': fromTimestamp!.toIso8601String(),
        if (toTimestamp != null) 'toTimestamp': toTimestamp!.toIso8601String(),
        'polylineEncoded': polylineEncoded,
        if (matchMethod != null) 'matchMethod': matchMethod,
      };

  static double? _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  static DateTime? _t(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

/// Authoritative matched-route payload from Nest map-matching worker.
class MatchedRouteResult {
  final String requestId;
  final String status; // pending | ready | failed
  final String? engine;
  final DateTime? matchedAt;
  final double? officialDistanceKm;
  final double? provisionalDistanceKm;
  final double? coveragePct;
  final double? matchedPct;
  final double? estimatedPct;
  final List<MatchedLegMetrics> legs;
  final List<RouteSegmentModel> segments;
  final String? error;

  const MatchedRouteResult({
    required this.requestId,
    required this.status,
    this.engine,
    this.matchedAt,
    this.officialDistanceKm,
    this.provisionalDistanceKm,
    this.coveragePct,
    this.matchedPct,
    this.estimatedPct,
    this.legs = const [],
    this.segments = const [],
    this.error,
  });

  bool get isReady => status == 'ready';
  bool get isPending => status == 'pending';

  factory MatchedRouteResult.fromMap(dynamic data) {
    if (data is! Map) {
      return const MatchedRouteResult(requestId: '', status: 'failed');
    }
    final map = Map<String, dynamic>.from(data);
    final legsRaw = map['legs'];
    final segsRaw = map['segments'];
    final legs = <MatchedLegMetrics>[];
    if (legsRaw is List) {
      for (final e in legsRaw) {
        legs.add(MatchedLegMetrics.fromMap(e));
      }
    }
    final segments = <RouteSegmentModel>[];
    if (segsRaw is List) {
      for (final e in segsRaw) {
        segments.add(RouteSegmentModel.fromMap(e));
      }
    }
    // Flatten per-leg segments when top-level list omitted.
    if (segments.isEmpty) {
      for (final leg in legs) {
        segments.addAll(leg.segments);
      }
    }
    return MatchedRouteResult(
      requestId: map['requestId']?.toString() ?? map['tripId']?.toString() ?? '',
      status: (map['status']?.toString() ?? 'ready').toLowerCase(),
      engine: map['engine']?.toString(),
      matchedAt: RouteSegmentModel._t(map['matchedAt']),
      officialDistanceKm: RouteSegmentModel._d(
        map['officialDistanceKm'] ?? map['officialKm'],
      ),
      provisionalDistanceKm: RouteSegmentModel._d(
        map['provisionalDistanceKm'] ?? map['provisionalKm'],
      ),
      coveragePct: RouteSegmentModel._d(map['coveragePct']),
      matchedPct: RouteSegmentModel._d(map['matchedPct']),
      estimatedPct: RouteSegmentModel._d(map['estimatedPct']),
      legs: legs,
      segments: segments,
      error: map['error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'requestId': requestId,
        'status': status,
        if (engine != null) 'engine': engine,
        if (matchedAt != null) 'matchedAt': matchedAt!.toIso8601String(),
        if (officialDistanceKm != null)
          'officialDistanceKm': officialDistanceKm,
        if (provisionalDistanceKm != null)
          'provisionalDistanceKm': provisionalDistanceKm,
        if (coveragePct != null) 'coveragePct': coveragePct,
        if (matchedPct != null) 'matchedPct': matchedPct,
        if (estimatedPct != null) 'estimatedPct': estimatedPct,
        'legs': legs.map((e) => e.toMap()).toList(),
        'segments': segments.map((e) => e.toMap()).toList(),
        if (error != null) 'error': error,
      };
}

class MatchedLegMetrics {
  final String legId;
  final double? officialDistanceKm;
  final double? provisionalDistanceKm;
  final double? confidence;
  final double? estimatedPct;
  final String? matchedPolylineEncoded;
  final List<RouteSegmentModel> segments;

  const MatchedLegMetrics({
    required this.legId,
    this.officialDistanceKm,
    this.provisionalDistanceKm,
    this.confidence,
    this.estimatedPct,
    this.matchedPolylineEncoded,
    this.segments = const [],
  });

  factory MatchedLegMetrics.fromMap(dynamic data) {
    if (data is! Map) {
      return const MatchedLegMetrics(legId: '');
    }
    final map = Map<String, dynamic>.from(data);
    final segs = <RouteSegmentModel>[];
    final raw = map['segments'];
    if (raw is List) {
      for (final e in raw) {
        segs.add(RouteSegmentModel.fromMap(e));
      }
    }
    return MatchedLegMetrics(
      legId: map['legId']?.toString() ?? '',
      officialDistanceKm: RouteSegmentModel._d(
        map['officialDistanceKm'] ?? map['officialKm'],
      ),
      provisionalDistanceKm: RouteSegmentModel._d(
        map['provisionalDistanceKm'] ?? map['provisionalKm'],
      ),
      confidence: RouteSegmentModel._d(map['confidence']),
      estimatedPct: RouteSegmentModel._d(map['estimatedPct']),
      matchedPolylineEncoded: map['matchedPolylineEncoded']?.toString() ??
          map['routePolylineEncoded']?.toString(),
      segments: segs,
    );
  }

  Map<String, dynamic> toMap() => {
        'legId': legId,
        if (officialDistanceKm != null)
          'officialDistanceKm': officialDistanceKm,
        if (provisionalDistanceKm != null)
          'provisionalDistanceKm': provisionalDistanceKm,
        if (confidence != null) 'confidence': confidence,
        if (estimatedPct != null) 'estimatedPct': estimatedPct,
        if (matchedPolylineEncoded != null)
          'matchedPolylineEncoded': matchedPolylineEncoded,
        'segments': segments.map((e) => e.toMap()).toList(),
      };
}

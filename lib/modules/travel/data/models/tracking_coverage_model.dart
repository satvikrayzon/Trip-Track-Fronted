/// A period with no GPS points during an expected tracking window.
class TrackingGapModel {
  const TrackingGapModel({
    required this.from,
    required this.to,
    required this.durationMinutes,
    this.reason = 'no_points',
    this.suspectedCause,
  });

  final DateTime from;
  final DateTime to;
  final int durationMinutes;
  final String reason;
  final String? suspectedCause;

  factory TrackingGapModel.fromMap(Map map) {
    final m = Map<String, dynamic>.from(map);
    return TrackingGapModel(
      from: _parseTime(m['from']) ?? DateTime.now().toUtc(),
      to: _parseTime(m['to']) ?? DateTime.now().toUtc(),
      durationMinutes: _int(m['durationMinutes']) ?? 0,
      reason: m['reason']?.toString() ?? 'no_points',
      suspectedCause: m['suspectedCause']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'durationMinutes': durationMinutes,
        'reason': reason,
        if (suspectedCause != null) 'suspectedCause': suspectedCause,
      };
}

/// Per-leg GPS coverage between departure and arrival punches.
class TrackingCoverageLegModel {
  const TrackingCoverageLegModel({
    required this.legId,
    this.legNumber = 1,
    this.fromLocation = '',
    this.toLocation = '',
    this.departureAt,
    this.arrivalAt,
    this.expectedDurationMinutes = 0,
    this.trackedDurationMinutes = 0,
    this.gapDurationMinutes = 0,
    this.coveragePercent = 0,
    this.pointCount = 0,
    this.gaps = const [],
  });

  final String legId;
  final int legNumber;
  final String fromLocation;
  final String toLocation;
  final DateTime? departureAt;
  final DateTime? arrivalAt;
  final int expectedDurationMinutes;
  final int trackedDurationMinutes;
  final int gapDurationMinutes;
  final double coveragePercent;
  final int pointCount;
  final List<TrackingGapModel> gaps;

  factory TrackingCoverageLegModel.fromMap(Map map) {
    final m = Map<String, dynamic>.from(map);
    final gapsRaw = m['gaps'];
    final gaps = gapsRaw is List
        ? gapsRaw
            .whereType<Map>()
            .map((e) => TrackingGapModel.fromMap(e))
            .toList()
        : <TrackingGapModel>[];

    return TrackingCoverageLegModel(
      legId: m['legId']?.toString() ?? '',
      legNumber: _int(m['legNumber']) ?? 1,
      fromLocation: m['fromLocation']?.toString() ?? '',
      toLocation: m['toLocation']?.toString() ?? '',
      departureAt: _parseTime(m['departureAt']),
      arrivalAt: _parseTime(m['arrivalAt']),
      expectedDurationMinutes: _int(m['expectedDurationMinutes']) ?? 0,
      trackedDurationMinutes: _int(m['trackedDurationMinutes']) ?? 0,
      gapDurationMinutes: _int(m['gapDurationMinutes']) ?? 0,
      coveragePercent: _double(m['coveragePercent']) ?? 0,
      pointCount: _int(m['pointCount']) ?? 0,
      gaps: gaps,
    );
  }

  Map<String, dynamic> toMap() => {
        'legId': legId,
        'legNumber': legNumber,
        'fromLocation': fromLocation,
        'toLocation': toLocation,
        if (departureAt != null)
          'departureAt': departureAt!.toUtc().toIso8601String(),
        if (arrivalAt != null) 'arrivalAt': arrivalAt!.toUtc().toIso8601String(),
        'expectedDurationMinutes': expectedDurationMinutes,
        'trackedDurationMinutes': trackedDurationMinutes,
        'gapDurationMinutes': gapDurationMinutes,
        'coveragePercent': coveragePercent,
        'pointCount': pointCount,
        'gaps': gaps.map((g) => g.toMap()).toList(),
      };
}

/// Trip-level tracking coverage report.
class TrackingCoverageResult {
  const TrackingCoverageResult({
    required this.requestId,
    this.tripId = '',
    this.legs = const [],
    this.summary = const TrackingCoverageSummary.empty(),
    this.source = CoverageSource.local,
  });

  final String requestId;
  final String tripId;
  final List<TrackingCoverageLegModel> legs;
  final TrackingCoverageSummary summary;
  final CoverageSource source;

  factory TrackingCoverageResult.fromMap(Map map) {
    final m = Map<String, dynamic>.from(map);
    final legsRaw = m['legs'];
    final legs = legsRaw is List
        ? legsRaw
            .whereType<Map>()
            .map((e) => TrackingCoverageLegModel.fromMap(e))
            .toList()
        : <TrackingCoverageLegModel>[];

    final summaryMap = m['summary'];
    final summary = summaryMap is Map
        ? TrackingCoverageSummary.fromMap(summaryMap)
        : TrackingCoverageSummary.fromLegs(legs);

    return TrackingCoverageResult(
      requestId:
          m['requestId']?.toString() ?? m['id']?.toString() ?? '',
      tripId: m['tripId']?.toString() ?? '',
      legs: legs,
      summary: summary,
      source: CoverageSource.remote,
    );
  }

  Map<String, dynamic> toMap() => {
        'requestId': requestId,
        if (tripId.isNotEmpty) 'tripId': tripId,
        'legs': legs.map((l) => l.toMap()).toList(),
        'summary': summary.toMap(),
        'source': source.name,
      };

  factory TrackingCoverageResult.fromJson(Map<String, dynamic> json) =>
      TrackingCoverageResult.fromMap(json);
}

class TrackingCoverageSummary {
  const TrackingCoverageSummary({
    required this.expectedDurationMinutes,
    required this.trackedDurationMinutes,
    required this.gapDurationMinutes,
    required this.coveragePercent,
  });

  const TrackingCoverageSummary.empty()
      : expectedDurationMinutes = 0,
        trackedDurationMinutes = 0,
        gapDurationMinutes = 0,
        coveragePercent = 0;

  final int expectedDurationMinutes;
  final int trackedDurationMinutes;
  final int gapDurationMinutes;
  final double coveragePercent;

  factory TrackingCoverageSummary.fromMap(Map map) {
    final m = Map<String, dynamic>.from(map);
    return TrackingCoverageSummary(
      expectedDurationMinutes: _int(m['expectedDurationMinutes']) ?? 0,
      trackedDurationMinutes: _int(m['trackedDurationMinutes']) ?? 0,
      gapDurationMinutes: _int(m['gapDurationMinutes']) ?? 0,
      coveragePercent: _double(m['coveragePercent']) ?? 0,
    );
  }

  factory TrackingCoverageSummary.fromLegs(List<TrackingCoverageLegModel> legs) {
    if (legs.isEmpty) return const TrackingCoverageSummary.empty();
    final expected =
        legs.fold<int>(0, (t, l) => t + l.expectedDurationMinutes);
    final tracked =
        legs.fold<int>(0, (t, l) => t + l.trackedDurationMinutes);
    final gap = legs.fold<int>(0, (t, l) => t + l.gapDurationMinutes);
    final pct = expected > 0 ? (tracked / expected) * 100 : 0.0;
    return TrackingCoverageSummary(
      expectedDurationMinutes: expected,
      trackedDurationMinutes: tracked,
      gapDurationMinutes: gap,
      coveragePercent: double.parse(pct.toStringAsFixed(1)),
    );
  }

  Map<String, dynamic> toMap() => {
        'expectedDurationMinutes': expectedDurationMinutes,
        'trackedDurationMinutes': trackedDurationMinutes,
        'gapDurationMinutes': gapDurationMinutes,
        'coveragePercent': coveragePercent,
      };
}

enum CoverageSource { local, remote, cached }

DateTime? _parseTime(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    try {
      return DateTime.parse(v).toUtc();
    } catch (_) {
      return null;
    }
  }
  if (v is DateTime) return v.toUtc();
  return null;
}

int? _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

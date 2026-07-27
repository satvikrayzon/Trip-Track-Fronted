/// Dashboard counters from `GET /travel-requests/summary?mine=true`.
class TravelRequestSummary {
  const TravelRequestSummary({
    required this.total,
    required this.pending,
    required this.completed,
  });

  final int total;
  final int pending;
  final int completed;

  factory TravelRequestSummary.fromResponse(dynamic data) {
    if (data is! Map) {
      throw const FormatException('Summary response is not a JSON object');
    }
    final root = Map<String, dynamic>.from(data);
    final payload = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    return TravelRequestSummary(
      total: _int(payload['total']) ?? 0,
      pending: _int(payload['pending']) ?? 0,
      completed: _int(payload['completed']) ?? 0,
    );
  }

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

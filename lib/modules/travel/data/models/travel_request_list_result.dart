import '../../../../core/network/api_response_list.dart';

/// Paginated travel-request list (NestJS `GET /travel-requests?page=&limit=`).
class TravelRequestListResult {
  const TravelRequestListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    this.pending,
    this.completed,
    this.hasMore = false,
  });

  final List<Map<String, dynamic>> items;
  final int total;
  final int page;
  final int limit;
  final int? pending;
  final int? completed;
  final bool hasMore;

  factory TravelRequestListResult.fromResponse(
    dynamic data, {
    required int page,
    required int limit,
  }) {
    if (data is List) {
      // Plain arrays are a full payload in one response — never page further
      // (treating length >= limit as hasMore caused an infinite fetch loop).
      final items = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return TravelRequestListResult(
        items: items,
        total: items.length,
        page: page,
        limit: limit,
        hasMore: false,
      );
    }

    if (data is! Map) {
      throw const FormatException('Expected list or paginated object');
    }

    final root = Map<String, dynamic>.from(data);
    final items = ApiResponseList.parse(data);

    final meta = root['meta'] is Map
        ? Map<String, dynamic>.from(root['meta'] as Map)
        : root;

    final total = _int(meta['total']) ??
        _int(meta['totalCount']) ??
        _int(root['total']) ??
        items.length;

    final pending = _int(meta['pending']) ?? _int(root['pending']);
    final completed = _int(meta['completed']) ?? _int(root['completed']);

    final totalPages = _int(meta['totalPages']) ??
        (limit > 0 ? (total / limit).ceil() : 1);

    return TravelRequestListResult(
      items: items,
      total: total,
      page: _int(meta['page']) ?? _int(root['page']) ?? page,
      limit: _int(meta['limit']) ?? _int(root['limit']) ?? limit,
      pending: pending,
      completed: completed,
      hasMore: page < totalPages,
    );
  }

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

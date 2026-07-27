/// Extracts a JSON array of objects from typical REST / Nest response shapes.
abstract final class ApiResponseList {
  static const List<String> _listKeys = [
    'items',
    'data',
    'users',
    'results',
    'records',
    'rows',
    'payload',
    'content',
  ];

  static List<Map<String, dynamic>> parse(dynamic root) {
    if (root is List) {
      return _mapsFromList(root);
    }
    if (root is Map) {
      final m = Map<String, dynamic>.from(root);
      final direct = _firstListOfMaps(m, _listKeys);
      if (direct != null) return direct;

      final nested = m['data'];
      if (nested is Map) {
        final inner = _firstListOfMaps(
          Map<String, dynamic>.from(nested),
          _listKeys,
        );
        if (inner != null) return inner;
      }
    }
    throw const FormatException(
      'Expected a JSON array or object containing a list of maps',
    );
  }

  static List<Map<String, dynamic>> _mapsFromList(List<dynamic> list) {
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static List<Map<String, dynamic>>? _firstListOfMaps(
    Map<String, dynamic> m,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = m[k];
      if (v is List && (v.isEmpty || v.first is Map)) {
        return _mapsFromList(v);
      }
    }
    return null;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../modules/travel/data/models/travel_request_model.dart';

/// Debug helper — logs travel-request API payloads vs parsed models.
abstract final class TravelRequestDebugLog {
  static void logListResponse({
    required String source,
    required dynamic rawResponse,
    required List<Map<String, dynamic>> items,
    int? page,
    int? limit,
  }) {
    if (!kDebugMode) return;

    if (page != null) 

    if (rawResponse != null) {
      try {
        final encoded = jsonEncode(rawResponse);
        final preview = encoded.length > 2000
            ? '${encoded.substring(0, 2000)}… (${encoded.length} chars total)'
            : encoded;
      } catch (_) {
      }
    }

    if (items.isEmpty) {
      return;
    }

    for (var i = 0; i < items.length && i < 5; i++) {
      _logRawItem(i, items[i]);
    }
  }

  static void logParsedComparison({
    required String source,
    required Map<String, dynamic> raw,
    required TravelRequestModel parsed,
    TravelRequestModel? afterMerge,
  }) {
    if (!kDebugMode) return;

    final merged = afterMerge ?? parsed;
    _logField('fromLocation', raw['fromLocation'], merged.fromLocation);
    _logField('toLocation', raw['toLocation'], merged.toLocation);
    _logField('clientName', raw['clientName'], null);
    _logField('userId', raw['userId'], merged.userId);
    _logField('status', raw['status'], merged.status);
    _logField(
      'tripLegs',
      raw['tripLegs'] is List ? (raw['tripLegs'] as List).length : raw['tripLegs'],
      merged.tripLegs.length,
    );
    if (merged.tripLegs.isNotEmpty) {
      final leg = merged.tripLegs.first;
    }
    if (afterMerge != null &&
        (parsed.fromLocation.isEmpty && merged.fromLocation.isNotEmpty)) {
    }
    if (afterMerge != null &&
        (parsed.toLocation.isEmpty && merged.toLocation.isNotEmpty)) {
    }
  }

  static void _logRawItem(int index, Map<String, dynamic> item) {
    final legs = item['tripLegs'];
    if (legs is List) {
      if (legs.isNotEmpty && legs.first is Map) {
        final leg = Map<String, dynamic>.from(legs.first as Map);
      }
    } else {
    }
  }

  static void _logField(String name, dynamic raw, dynamic parsed) {
    final rawStr = _preview(raw);
    if (parsed != null) {
    } else {
    }
  }

  static String _preview(dynamic v) {
    if (v == null) return '(null)';
    final s = v.toString();
    if (s.isEmpty) return '(empty)';
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

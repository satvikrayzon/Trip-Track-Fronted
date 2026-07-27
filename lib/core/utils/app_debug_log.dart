import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../network/failures/network_failure.dart';

/// Copy-paste friendly debug error blocks for the Flutter console.
abstract final class AppDebugLog {
  static void logError({
    required String source,
    String? operation,
    Object? error,
    StackTrace? stackTrace,
    NetworkFailure? failure,
    Map<String, dynamic>? context,
  }) {
    if (!kDebugMode) return;

    final lines = <String>[
      '══════════════════════ APP ERROR ══════════════════════',
      'time: ${DateTime.now().toIso8601String()}',
      'source: $source',
      if (operation != null && operation.isNotEmpty) 'operation: $operation',
    ];

    if (context != null && context.isNotEmpty) {
      lines.add('context: ${_encode(context)}');
    }

    if (failure != null) {
      lines.add('statusCode: ${failure.statusCode ?? '(none)'}');
      if (failure.code != null) lines.add('code: ${failure.code}');
      lines.add('message: ${failure.message}');
      _appendTransportDetails(lines, failure.raw);
    } else if (error != null) {
      lines.add('error: $error');
      _appendTransportDetails(lines, error);
    }

    if (stackTrace != null) {
      lines.add('stackTrace:');
      lines.add(stackTrace.toString());
    }

    lines.add('══════════════════════════════════════════════════════');
  }

  static void logApiFailure({
    required String source,
    required NetworkFailure failure,
    String? operation,
    Map<String, dynamic>? context,
  }) {
    logError(
      source: source,
      operation: operation,
      failure: failure,
      context: context,
    );
  }

  static void _appendTransportDetails(List<String> lines, Object? raw) {
    if (raw is! DioException) return;

    lines.add('httpMethod: ${raw.requestOptions.method}');
    lines.add('url: ${raw.requestOptions.uri}');
    lines.add('dioType: ${raw.type}');
    if (raw.requestOptions.data != null) {
      lines.add('requestBody: ${_encode(raw.requestOptions.data)}');
    }
    if (raw.response?.data != null) {
      lines.add('responseBody: ${_encode(raw.response!.data)}');
    }
  }

  static String _encode(Object? value) {
    if (value == null) return '(null)';
    try {
      final encoded = jsonEncode(value);
      if (encoded.length <= 1200) return encoded;
      return '${encoded.substring(0, 1200)}… (${encoded.length} chars total)';
    } catch (_) {
      final text = value.toString();
      if (text.length <= 1200) return text;
      return '${text.substring(0, 1200)}… (${text.length} chars total)';
    }
  }
}

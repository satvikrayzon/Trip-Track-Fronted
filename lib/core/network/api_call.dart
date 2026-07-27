import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'failures/network_failure.dart';
import 'models/api_result.dart';
import '../utils/app_debug_log.dart';

NetworkFailure _fromDio(DioException e) {
  final response = e.response;
  final status = response?.statusCode;
  final data = response?.data;

  String message = e.message ?? 'Network error';
  String? code;

  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    final serverMsg = m['message'] ?? m['error'] ?? m['detail'];
    if (serverMsg is List) {
      message = serverMsg.map((e) => e.toString()).join('\n');
    } else if (serverMsg is String && serverMsg.isNotEmpty) {
      message = serverMsg;
    }
    final c = m['code'];
    if (c is String) code = c;
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      message =
          'Cannot reach server. Check that the backend is running and your '
          'device is on the same network as ${e.requestOptions.uri.host}.';
      break;
    case DioExceptionType.connectionError:
      message =
          'No connection to server. Check Wi‑Fi/mobile data and that the '
          'backend at ${e.requestOptions.uri.host} is running.';
      break;
    default:
      break;
  }

  return NetworkFailure(
    message: message,
    statusCode: status,
    code: code,
    raw: e,
  );
}

/// Dio Web rejects [sendTimeout] on GET/HEAD (no request body). Use this helper.
Options dioTimeoutOptions(
  Duration timeout, {
  bool hasRequestBody = false,
  ValidateStatus? validateStatus,
}) {
  return Options(
    receiveTimeout: timeout,
    sendTimeout: (!kIsWeb || hasRequestBody) ? timeout : null,
    validateStatus: validateStatus,
  );
}

/// Runs [runner] and maps [DioException] to [ApiFailure].
/// When [logLabel] is set, logs details in debug mode (use for auth / debugging).
Future<ApiResult<T>> runApi<T>(
  Future<T> Function() runner, {
  String? logLabel,
}) async {
  try {
    final value = await runner();
    if (kDebugMode && logLabel != null) {
    }
    return ApiSuccess(value);
  } on DioException catch (e, st) {
    final failure = _fromDio(e);
    return ApiFailure(failure);
  } catch (e, st) {
    final failure = NetworkFailure(
      message: e.toString(),
      raw: e,
    );
    return ApiFailure(failure);
  }
}

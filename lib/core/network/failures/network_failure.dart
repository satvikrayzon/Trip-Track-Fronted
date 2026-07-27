import 'package:dio/dio.dart';

/// Normalized API / transport error for UI + logging.
class NetworkFailure implements Exception {
  const NetworkFailure({
    required this.message,
    this.statusCode,
    this.code,
    this.raw,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final Object? raw;

  @override
  String toString() =>
      'NetworkFailure($statusCode${code != null ? ', $code' : ''}): $message';

  /// Timeout or transport failure — not an auth/session problem.
  bool get isTransientNetworkError {
    final raw = this.raw;
    if (raw is DioException) {
      switch (raw.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          return false;
      }
    }
    return false;
  }
}

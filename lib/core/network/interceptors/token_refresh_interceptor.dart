import 'package:dio/dio.dart';

import '../../api/api_endpoints.dart';
import '../session_token_refresher.dart';

/// On 401 (or before requests with an expired JWT), refreshes once and retries.
class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor({
    required Dio dio,
    required SessionTokenRefresher refresher,
  })  : _dio = dio,
        _refresher = refresher;

  final Dio _dio;
  final SessionTokenRefresher _refresher;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAuthPath(options.path)) {
      handler.next(options);
      return;
    }

    try {
      final token = await _refresher.validAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    } catch (e, st) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          stackTrace: st,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    if (status != 401 || _isAuthPath(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    if (err.requestOptions.extra['retriedAfterRefresh'] == true) {
      handler.next(err);
      return;
    }

    final refreshed = await _refresher.refreshAccessToken();
    if (!refreshed) {
      handler.next(err);
      return;
    }

    final token = await _refresher.validAccessToken();
    if (token == null || token.isEmpty) {
      handler.next(err);
      return;
    }

    try {
      final retry = err.requestOptions;
      retry.extra['retriedAfterRefresh'] = true;
      retry.headers['Authorization'] = 'Bearer $token';
      final response = await _dio.fetch<dynamic>(retry);
      handler.resolve(response);
    } catch (e) {
      handler.next(err);
    }
  }

  bool _isAuthPath(String path) {
    return path.contains(ApiEndpoints.authLogin) ||
        path.contains(ApiEndpoints.authRefresh);
  }
}

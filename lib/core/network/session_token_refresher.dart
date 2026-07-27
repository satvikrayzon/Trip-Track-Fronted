import 'package:dio/dio.dart';

import '../api/api_endpoints.dart';
import '../utils/jwt_payload.dart';
import 'token_store.dart';

/// Single-flight JWT refresh — avoids rotating the same refresh token twice.
class SessionTokenRefresher {
  SessionTokenRefresher({
    required TokenStore tokenStore,
    required String baseUrl,
    Duration connectTimeout = const Duration(seconds: 25),
    Duration receiveTimeout = const Duration(seconds: 25),
  })  : _tokenStore = tokenStore,
        _refreshClient = Dio(
          BaseOptions(
            baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
            connectTimeout: connectTimeout,
            receiveTimeout: receiveTimeout,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            validateStatus: (code) => code != null && code >= 200 && code < 300,
          ),
        );

  final TokenStore _tokenStore;
  final Dio _refreshClient;

  Future<void>? _inFlight;
  bool _disabled = false;

  /// Call on logout so in-flight refresh cannot restore tokens.
  void invalidate() {
    _disabled = true;
    _inFlight = null;
  }

  /// Re-enable after a successful login.
  void reset() {
    _disabled = false;
  }

  /// Returns a valid access token, refreshing when missing or expired.
  Future<String?> validAccessToken({bool forceRefresh = false}) async {
    if (_disabled) return null;

    final current = _tokenStore.accessToken;
    if (!forceRefresh &&
        current != null &&
        current.isNotEmpty &&
        !JwtPayload.isExpired(current)) {
      return current;
    }

    final ok = await refreshAccessToken();
    return ok ? _tokenStore.accessToken : null;
  }

  /// Refreshes once; concurrent callers wait on the same in-flight refresh.
  Future<bool> refreshAccessToken() async {
    if (_disabled) return false;

    if (_inFlight != null) {
      await _inFlight!;
      return _hasUsableAccessToken();
    }

    _inFlight = _performRefresh();
    try {
      await _inFlight!;
      return _hasUsableAccessToken();
    } finally {
      _inFlight = null;
    }
  }

  bool _hasUsableAccessToken() {
    final access = _tokenStore.accessToken;
    return access != null &&
        access.isNotEmpty &&
        !JwtPayload.isExpired(access);
  }

  Future<void> _performRefresh() async {
    if (_disabled) return;

    final refresh = _tokenStore.refreshToken;
    if (refresh == null || refresh.isEmpty) return;

    try {
      final res = await _refreshClient.post<dynamic>(
        ApiEndpoints.authRefresh,
        data: {
          'refreshToken': refresh,
          'refresh_token': refresh,
        },
      );
      if (_disabled) return;

      final data = res.data;
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final access = (map['accessToken'] ??
              map['access_token'] ??
              map['token'])
          as String?;
      if (access == null || access.isEmpty) return;
      if (_disabled) return;

      final nextRefresh =
          map['refreshToken'] as String? ?? map['refresh_token'] as String?;

      await _tokenStore.setTokens(
        accessToken: access,
        refreshToken: nextRefresh ?? refresh,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        // Refresh token explicitly rejected (e.g. user banned or session revoked)
        await _tokenStore.clear();
      }
    } catch (_) {
      // Leave tokens unchanged; callers handle missing/invalid access.
    }
  }
}

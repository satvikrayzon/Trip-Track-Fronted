import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/api/api_endpoints.dart';
import '../../../../core/network/api_call.dart';
import '../../../../core/network/models/api_result.dart';

typedef AuthTokens = ({String access, String? refresh});

typedef LoginPayload = ({
  Map<String, dynamic> user,
  AuthTokens tokens,
});

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  Future<ApiResult<LoginPayload>> login({
    required String email,
    required String password,
  }) {
    return runApi(
      () async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.authLogin,
          data: {'email': email, 'password': password},
        );
        final root = res.data;
        if (root == null) throw const FormatException('Empty login response');
        final tokens = _parseTokens(root);
        final userMap = _parseUserMap(root);
        return (user: userMap, tokens: tokens);
      },
      logLabel: 'Auth.login',
    );
  }

  Future<ApiResult<Map<String, dynamic>>> fetchCurrentUser() {
    return runApi(() async {
      final res = await _dio.get(ApiEndpoints.authMe);
      final data = res.data;
      if (data is! Map) {
        throw const FormatException('Invalid /auth/me payload');
      }
      final m = Map<String, dynamic>.from(data);
      final nested = m['user'];
      if (nested is Map) {
        return Map<String, dynamic>.from(nested);
      }
      return m;
    });
  }

  Future<ApiResult<bool>> requestPasswordReset(String email) {
    return runApi(() async {
      await _dio.post<void>(
        ApiEndpoints.authForgotPassword,
        data: {'email': email},
      );
      return true;
    });
  }

  Future<ApiResult<AuthTokens>> refreshSession(String refreshToken) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.authRefresh,
        data: {
          'refreshToken': refreshToken,
          'refresh_token': refreshToken,
        },
      );
      final root = res.data;
      if (root == null) {
        throw const FormatException('Empty refresh response');
      }
      return _parseTokens(root);
    });
  }

  AuthTokens _parseTokens(Map<String, dynamic> root) {
    final access = root['accessToken'] ??
        root['access_token'] ??
        root['token'] as String?;
    if (access == null || access.isEmpty) {
      throw const FormatException('Login response missing access token');
    }
    final refresh =
        root['refreshToken'] as String? ?? root['refresh_token'] as String?;
    return (access: access, refresh: refresh);
  }

  Map<String, dynamic> _parseUserMap(Map<String, dynamic> root) {
    final u = root['user'];
    if (u is Map) return Map<String, dynamic>.from(u);
    if (root.containsKey('uid') || root.containsKey('email')) {
      return Map<String, dynamic>.from(root);
    }
    throw const FormatException('Login response missing user object');
  }
}

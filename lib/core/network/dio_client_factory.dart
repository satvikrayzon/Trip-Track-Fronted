import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';



import '../config/api_env.dart';

import '../constants/app_constants.dart';

import 'interceptors/token_refresh_interceptor.dart';

import 'session_token_refresher.dart';

import 'token_store.dart';



class DioClientFactory {

  DioClientFactory({

    required TokenStore tokenStore,

    SessionTokenRefresher? refresher,

    String? baseUrl,

    this.connectTimeout = const Duration(seconds: 25),

    this.receiveTimeout = const Duration(seconds: 25),

  })  : _tokenStore = tokenStore,

        _refresher = refresher,

        _baseUrl = baseUrl ?? ApiEnv.baseUrl;



  final TokenStore _tokenStore;

  final SessionTokenRefresher? _refresher;

  final String _baseUrl;

  final Duration connectTimeout;

  final Duration receiveTimeout;



  Dio create() {

    final raw = _baseUrl.trim().isEmpty ? 'http://localhost' : _baseUrl.trim();

    final resolved = raw.replaceAll(RegExp(r'/+$'), '');

    final dio = Dio(

      BaseOptions(

        baseUrl: resolved,

        connectTimeout: connectTimeout,

        receiveTimeout: receiveTimeout,

        headers: const {

          'Accept': 'application/json',

          'Content-Type': 'application/json',

        },

        // Only 2xx counts as success; 4xx must throw so callers get ApiFailure

        // with server JSON (e.g. 404) instead of parsing error bodies as success.

        validateStatus: (code) =>

            code != null && code >= 200 && code < 300,

      ),

    );



    final refresher = _refresher ??

        SessionTokenRefresher(

          tokenStore: _tokenStore,

          baseUrl: resolved,

          connectTimeout: connectTimeout,

          receiveTimeout: receiveTimeout,

        );



    dio.interceptors.add(

      TokenRefreshInterceptor(dio: dio, refresher: refresher),

    );



    if (kDebugMode && AppConstants.verboseApiLogging) {

      dio.interceptors.add(

        LogInterceptor(

          request: true,

          requestHeader: false,

          requestBody: true,

          responseHeader: false,

          responseBody: true,

          error: true,

        ),

      );

    }



    return dio;

  }

}



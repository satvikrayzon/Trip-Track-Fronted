import 'package:dio/dio.dart';

import '../config/api_env.dart';
import '../network/dio_client_factory.dart';
import '../network/session_token_refresher.dart';
import '../network/token_store.dart';
import '../../modules/auth/data/datasources/auth_remote_datasource.dart';
import '../../modules/auth/data/datasources/users_remote_datasource.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../modules/admin/data/datasources/admin_remote_datasource.dart';
import 'service_locator.dart';

/// Registers HTTP clients and REST datasources (lazy singletons).
void registerApiDependencies() {
  final sl = ServiceLocator.I;

  if (!sl.has<TokenStore>()) {
    sl.lazy<TokenStore>(HiveTokenStore.new);
  }

  if (!sl.has<SessionTokenRefresher>()) {
    sl.lazy<SessionTokenRefresher>(
      () => SessionTokenRefresher(
        tokenStore: sl.get<TokenStore>(),
        baseUrl: ApiEnv.baseUrl,
      ),
    );
  }

  if (!sl.has<Dio>()) {
    sl.lazy<Dio>(
      () => DioClientFactory(
        tokenStore: sl.get<TokenStore>(),
        refresher: sl.get<SessionTokenRefresher>(),
      ).create(),
    );
  }

  if (!sl.has<AuthRemoteDataSource>()) {
    sl.lazy<AuthRemoteDataSource>(
      () => AuthRemoteDataSource(sl.get<Dio>()),
    );
  }

  if (!sl.has<UsersRemoteDataSource>()) {
    sl.lazy<UsersRemoteDataSource>(
      () => UsersRemoteDataSource(sl.get<Dio>()),
    );
  }

  if (!sl.has<TravelRequestRemoteDataSource>()) {
    sl.lazy<TravelRequestRemoteDataSource>(
      () => TravelRequestRemoteDataSource(sl.get<Dio>()),
    );
  }

  if (!sl.has<AdminRemoteDataSource>()) {
    sl.lazy<AdminRemoteDataSource>(
      () => AdminRemoteDataSource(sl.get<Dio>()),
    );
  }
}

/// Used when WorkManager runs outside the normal service graph.
TravelRequestRemoteDataSource travelRequestApiFromHive() {
  final store = HiveTokenStore();
  final refresher = SessionTokenRefresher(
    tokenStore: store,
    baseUrl: ApiEnv.baseUrl,
  );
  final dio = DioClientFactory(
    tokenStore: store,
    refresher: refresher,
  ).create();
  return TravelRequestRemoteDataSource(dio);
}

bool get apiBaseUrlConfigured => ApiEnv.isConfigured;

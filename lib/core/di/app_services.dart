import 'package:dio/dio.dart';
import 'dart:async';

import '../config/api_env.dart';
import '../network/dio_client_factory.dart';
import '../network/session_token_refresher.dart';
import '../network/token_store.dart';
import '../services/background_location_service.dart';
import '../services/connectivity_service.dart';
import '../services/punch_location_service.dart';
import '../services/punch_reminder_service.dart';
import '../services/map_matching_service.dart';
import '../services/sync_service.dart';
import '../services/tracking_coverage_service.dart';
import '../services/tracking_event_service.dart';
import '../services/tracking_lifecycle_binder.dart';
import '../services/tracking_session_service.dart';
import '../../modules/auth/data/datasources/auth_remote_datasource.dart';
import '../../modules/auth/data/datasources/users_remote_datasource.dart';
import '../../modules/auth/presentation/bloc/auth_session_cubit.dart';
import '../../modules/auth/presentation/controllers/app_auth_controller.dart';
import '../../modules/offline_sync/presentation/controllers/sync_controller.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';
import '../../features/tracking/data/services/websocket_tracking_service.dart';
import 'api_registrar.dart';
import 'service_locator.dart';

/// Registers HTTP clients, datasources, and app services (lazy — created on first use).
void registerAppServices() {
  registerApiDependencies();

  final sl = ServiceLocator.I;

  sl.lazy<ConnectivityService>(() {
    final s = ConnectivityService();
    s.init();
    return s;
  });

  sl.lazy<BackgroundLocationService>(BackgroundLocationService.new);

  sl.lazy<PunchLocationService>(PunchLocationService.new);

  sl.lazy<PunchReminderService>(() {
    TrackingLifecycleBinder.instance.attach();
    return PunchReminderService();
  });

  sl.lazy<TrackingSessionService>(TrackingSessionService.new);

  sl.lazy<TrackingEventService>(() {
    final s = TrackingEventService(
      connectivity: sl.get<ConnectivityService>(),
    );
    sl.get<ConnectivityService>().onConnectivityChanged.listen((online) {
      unawaited(s.onNetworkChanged(online));
    });
    TrackingLifecycleBinder.instance.attach();
    return s;
  });

  sl.lazy<TrackingCoverageService>(() => TrackingCoverageService(
        travelApi: sl.get<TravelRequestRemoteDataSource>(),
        connectivity: sl.get<ConnectivityService>(),
      ));

  sl.lazy<MapMatchingService>(() => MapMatchingService(
        travelApi: sl.get<TravelRequestRemoteDataSource>(),
      ));

  sl.lazy<SyncService>(() {
    final s = SyncService(
      connectivity: sl.get<ConnectivityService>(),
      travelApi: sl.get<TravelRequestRemoteDataSource>(),
    );
    s.init();
    return s;
  });

  sl.lazy<AppAuthController>(() {
    return AppAuthController(
      authRemote: sl.get<AuthRemoteDataSource>(),
      usersRemote: sl.get<UsersRemoteDataSource>(),
      tokenStore: sl.get<TokenStore>(),
      tokenRefresher: sl.get<SessionTokenRefresher>(),
      authSessionCubit: sl.has<AuthSessionCubit>()
          ? sl.get<AuthSessionCubit>()
          : null,
    )..start();
  });

  sl.lazy<SyncController>(() {
    return SyncController(
      syncService: sl.get<SyncService>(),
      connectivityService: sl.get<ConnectivityService>(),
    )..start();
  });

  sl.lazy<WebSocketTrackingService>(
    () => WebSocketTrackingService(sl.get<TokenStore>()),
  );
}

/// Background isolate / WorkManager — no full service graph.
SyncService createBackgroundSyncService() {
  final store = HiveTokenStore();
  final refresher = SessionTokenRefresher(
    tokenStore: store,
    baseUrl: ApiEnv.baseUrl,
  );
  final dio = DioClientFactory(
    tokenStore: store,
    refresher: refresher,
  ).create();
  final connectivity = ConnectivityService()..init();
  return SyncService(
    connectivity: connectivity,
    travelApi: TravelRequestRemoteDataSource(dio),
  )..init();
}

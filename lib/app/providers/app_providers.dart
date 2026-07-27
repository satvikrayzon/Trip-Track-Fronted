import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/token_store.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_service.dart';
import '../../features/offline/data/hive_offline_store.dart';
import '../../features/tracking/data/services/websocket_tracking_service.dart';
import '../../modules/auth/presentation/controllers/app_auth_controller.dart';
import '../../modules/auth/data/datasources/users_remote_datasource.dart';
import '../../modules/travel/data/datasources/travel_request_remote_datasource.dart';

class SyncStatusSummary {
  const SyncStatusSummary({
    required this.isOnline,
    required this.totalPending,
  });

  final bool isOnline;
  final int totalPending;

  bool get needsSync => totalPending > 0;
}

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return ServiceLocator.I.get<TokenStore>();
});

final travelApiProvider = Provider<TravelRequestRemoteDataSource>((ref) {
  return ServiceLocator.I.get<TravelRequestRemoteDataSource>();
});

final usersApiProvider = Provider<UsersRemoteDataSource>((ref) {
  return ServiceLocator.I.get<UsersRemoteDataSource>();
});

final authControllerProvider = Provider<AppAuthController>((ref) {
  return ServiceLocator.I.get<AppAuthController>();
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ServiceLocator.I.get<ConnectivityService>();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return ServiceLocator.I.get<SyncService>();
});

final offlineStoreProvider = Provider<HiveOfflineStore>((ref) {
  return HiveOfflineStore.instance;
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final syncStatusProvider = FutureProvider<SyncStatusSummary>((ref) async {
  final store = ref.watch(offlineStoreProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final punches = await store.pendingPunchCount();
  final gps = await store.pendingGpsCount();
  return SyncStatusSummary(
    isOnline: connectivity.isConnected.value,
    totalPending: punches + gps,
  );
});

final webSocketTrackingProvider = Provider<WebSocketTrackingService>((ref) {
  return ServiceLocator.I.get<WebSocketTrackingService>();
});

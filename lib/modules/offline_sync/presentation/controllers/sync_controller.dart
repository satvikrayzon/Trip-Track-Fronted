import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_service.dart';

/// Sync UI state for settings screen.
class SyncController {
  SyncController({
    SyncService? syncService,
    ConnectivityService? connectivityService,
  })  : _syncService = syncService ?? ServiceLocator.I.get(),
        _connectivityService = connectivityService ?? ServiceLocator.I.get();

  final SyncService _syncService;
  final ConnectivityService _connectivityService;

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingItems = ValueNotifier<int>(0);
  final ValueNotifier<String> lastSyncTime = ValueNotifier<String>('');

  void start() {
    isOnline.value = _connectivityService.isConnected.value;
    isSyncing.value = _syncService.isSyncing.value;
    pendingItems.value = _syncService.pendingSyncCount.value;
    _updateLastSyncTime();

    _connectivityService.isConnected.addListener(_onConnectivityChanged);
    _syncService.isSyncing.addListener(_onSyncingChanged);
    _syncService.pendingSyncCount.addListener(_onPendingChanged);
  }

  void dispose() {
    _connectivityService.isConnected.removeListener(_onConnectivityChanged);
    _syncService.isSyncing.removeListener(_onSyncingChanged);
    _syncService.pendingSyncCount.removeListener(_onPendingChanged);
    isOnline.dispose();
    isSyncing.dispose();
    pendingItems.dispose();
    lastSyncTime.dispose();
  }

  void _onConnectivityChanged() {
    isOnline.value = _connectivityService.isConnected.value;
  }

  void _onSyncingChanged() {
    isSyncing.value = _syncService.isSyncing.value;
  }

  void _onPendingChanged() {
    pendingItems.value = _syncService.pendingSyncCount.value;
  }

  String get syncStatusText {
    if (isSyncing.value) return 'Syncing...';
    if (pendingItems.value > 0) return ' pending';
    return 'Up to date';
  }

  Future<void> forceSync() async {
    if (!isOnline.value) {
      showAppSnackBar(
        title: 'No Internet',
        message: 'Please check your internet connection and try again.',
        backgroundColor: const Color(0xFFFF9800),
      );
      return;
    }

    try {
      await _syncService.forceSync();
      _updateLastSyncTime();
    } catch (e) {
      showAppSnackBar(
        title: 'Sync Failed',
        message: 'Failed to sync data. Please try again.',
        backgroundColor: const Color(0xFFEF4444),
      );
    }
  }

  void _updateLastSyncTime() {
    lastSyncTime.value = 'Last sync: ${_formatTime(DateTime.now())}';
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  Future<Map<String, dynamic>> getSyncStatistics() async {
    final stats = await _syncService.getSyncStatistics();
    final connectivityInfo = await _connectivityService.getConnectivityInfo();

    return {
      'pendingSync': stats['pendingSync'] ?? 0,
      'offlineImages': stats['offlineImages'] ?? 0,
      'offlineRequests': stats['offlineRequests'] ?? 0,
      'isOnline': isOnline.value,
      'connectionType': connectivityInfo['connectionType'],
      'lastSync': lastSyncTime.value,
    };
  }

  bool get needsSync => pendingItems.value > 0 && isOnline.value;

  double get syncProgress => isSyncing.value ? 0.5 : 0.0;
}

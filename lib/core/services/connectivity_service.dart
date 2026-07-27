import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors network connectivity.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<ConnectivityResult> connectivityResult =
      ValueNotifier<ConnectivityResult>(ConnectivityResult.none);

  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  final StreamController<bool> _connectedEvents =
      StreamController<bool>.broadcast();

  Stream<bool> get onConnectivityChanged => _connectedEvents.stream;

  void init() {
    if (_connectivitySubscription != null) return;
    unawaited(_initConnectivity());
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(result);

      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _updateConnectivityStatus,
        onError: (error) {
        },
      );
    } catch (e) {
    }
  }

  void _updateConnectivityStatus(ConnectivityResult result) {
    connectivityResult.value = result;
    final connected = result != ConnectivityResult.none;
    if (isConnected.value != connected) {
      isConnected.value = connected;
      _connectedEvents.add(connected);
    }
  }

  Future<bool> hasInternetConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getConnectivityInfo() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return {
        'isConnected': result != ConnectivityResult.none,
        'connectionType': result.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'isConnected': false,
        'connectionType': 'unknown',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectedEvents.close();
    isConnected.dispose();
    connectivityResult.dispose();
  }
}

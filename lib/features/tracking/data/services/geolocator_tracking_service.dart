import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Geolocator-based location with GPS validation for punches.
class GeolocatorTrackingService {
  GeolocatorTrackingService();

  final Battery _battery = Battery();
  StreamSubscription<Position>? _positionSub;
  final _positionController = StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;
  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  Future<bool> ensurePermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position?> getCurrentPosition({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final ok = await ensurePermissions();
    if (!ok) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      ).timeout(timeout);
      _lastPosition = pos;
      return pos;
    } catch (e) {
      return _lastPosition;
    }
  }

  Future<bool> validateGpsForPunch({
    double maxAccuracyMeters = 80,
  }) async {
    final pos = await getCurrentPosition();
    if (pos == null) return false;
    return pos.accuracy <= maxAccuracyMeters;
  }

  Future<void> startStream({
    int distanceFilterMeters = 8,
  }) async {
    final ok = await ensurePermissions();
    if (!ok) return;

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen((pos) {
      _lastPosition = pos;
      _positionController.add(pos);
    });
  }

  Future<void> stopStream() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  Future<int> batteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return 100;
    }
  }

  double speedKmh(Position pos) => (pos.speed >= 0 ? pos.speed : 0) * 3.6;

  void dispose() {
    stopStream();
    _positionController.close();
  }
}

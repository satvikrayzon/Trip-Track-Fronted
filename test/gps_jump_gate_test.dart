import 'package:flutter_test/flutter_test.dart';
import 'package:trip_track/core/utils/gps_jump_gate.dart';

void main() {
  test('rejects hard teleport across continents', () {
    final decision = GpsJumpGate.evaluate(
      lat: 21.17,
      lng: 72.83, // Surat
      accuracyM: 20,
      timestamp: DateTime.now(),
      prevLat: 23.6,
      prevLng: 58.5, // Oman coast
      prevTimestamp: DateTime.now().subtract(const Duration(minutes: 2)),
    );
    expect(decision.accepted, isFalse);
    expect(decision.reason, 'hard_jump');
  });

  test('rejects indoor drift with poor accuracy while stationary', () {
    final decision = GpsJumpGate.evaluate(
      lat: 21.1701,
      lng: 72.8301,
      accuracyM: 55,
      speedMps: 0.1,
      timestamp: DateTime.now(),
      prevLat: 21.17,
      prevLng: 72.83,
      prevTimestamp: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    expect(decision.accepted, isFalse);
    expect(decision.reason, 'indoor_drift');
  });

  test('accepts normal city hop', () {
    final decision = GpsJumpGate.evaluate(
      lat: 21.171,
      lng: 72.831,
      accuracyM: 15,
      speedMps: 8,
      timestamp: DateTime.now(),
      prevLat: 21.17,
      prevLng: 72.83,
      prevTimestamp: DateTime.now().subtract(const Duration(seconds: 8)),
    );
    expect(decision.accepted, isTrue);
  });
}

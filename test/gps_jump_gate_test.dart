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

  test('accepts city-scale hop after long tracking silence', () {
    final decision = GpsJumpGate.evaluate(
      lat: 21.20,
      lng: 72.86,
      accuracyM: 20,
      timestamp: DateTime.now(),
      prevLat: 21.17,
      prevLng: 72.83,
      prevTimestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    expect(decision.accepted, isTrue);
    expect(decision.reason, 'gap_resume');
  });

  test('accepts short kill gap under 2.5km so road fill can run', () {
    // ~1.1km hop after 3 minutes — previously accepted without gap_resume,
    // so Directions B→C never ran.
    final decision = GpsJumpGate.evaluate(
      lat: 21.178,
      lng: 72.838,
      accuracyM: 18,
      timestamp: DateTime.now(),
      prevLat: 21.17,
      prevLng: 72.83,
      prevTimestamp: DateTime.now().subtract(const Duration(minutes: 3)),
    );
    expect(decision.accepted, isTrue);
    expect(decision.reason, 'gap_resume');
  });
}

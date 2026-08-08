import 'package:flutter_test/flutter_test.dart';
import 'package:trip_track/core/utils/distance_sanity.dart';

void main() {
  test('rejects ocean teleport official km vs short GPS', () {
    expect(
      DistanceSanity.isOfficialAbsurd(
        officialKm: 3028,
        gpsKm: 6.7,
        travelMinutes: 33,
      ),
      isTrue,
    );
  });

  test('rejects 107km official for ~3km GPS trip', () {
    expect(
      DistanceSanity.isOfficialAbsurd(
        officialKm: 107.2,
        gpsKm: 2.6,
        travelMinutes: 4,
      ),
      isTrue,
    );
  });

  test('accepts normal matched km near GPS', () {
    expect(
      DistanceSanity.isOfficialAbsurd(
        officialKm: 7.1,
        gpsKm: 6.7,
        travelMinutes: 33,
      ),
      isFalse,
    );
  });

  test('selectLegKm falls back to GPS when official absurd', () {
    final km = DistanceSanity.selectLegKm(
      officialKm: 3028,
      provisionalKm: 6.7,
      travelMinutes: 33,
    );
    expect(km, 6.7);
  });

  test('selectLegKm prefers GPS when official is 0.5km higher', () {
    // Card had 17.8 GPS; detail showed 18.3 Official — keep GPS for parity.
    final km = DistanceSanity.selectLegKm(
      officialKm: 18.3,
      provisionalKm: 17.8,
      travelMinutes: 80,
    );
    expect(km, 17.8);
    expect(
      DistanceSanity.selectLegKmLabel(
        officialKm: 18.3,
        provisionalKm: 17.8,
        travelMinutes: 80,
      ),
      'Approx (GPS)',
    );
  });

  test('selectLegKm keeps official when essentially equal to GPS', () {
    final km = DistanceSanity.selectLegKm(
      officialKm: 17.85,
      provisionalKm: 17.8,
      travelMinutes: 80,
    );
    expect(km, 17.85);
  });
}

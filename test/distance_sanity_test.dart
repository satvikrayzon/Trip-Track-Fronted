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
}

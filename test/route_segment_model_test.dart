import 'package:flutter_test/flutter_test.dart';
import 'package:trip_track/modules/travel/data/models/route_segment_model.dart';
import 'package:trip_track/modules/travel/data/models/travel_request_model.dart';

void main() {
  test('MatchedRouteResult parses legs and segments', () {
    final result = MatchedRouteResult.fromMap({
      'requestId': 'req-1',
      'status': 'ready',
      'engine': 'google_roads',
      'officialDistanceKm': 12.4,
      'provisionalDistanceKm': 12.9,
      'legs': [
        {
          'legId': 'leg_1',
          'officialDistanceKm': 12.4,
          'matchedPolylineEncoded': '21.1,72.8|21.2,72.9',
          'segments': [
            {
              'segId': 's1',
              'kind': 'gps_verified',
              'confidence': 0.9,
              'lengthM': 8000,
              'polylineEncoded': '21.1,72.8|21.15,72.85',
            },
            {
              'segId': 's2',
              'kind': 'estimated',
              'confidence': 0.35,
              'lengthM': 4400,
              'polylineEncoded': '21.15,72.85|21.2,72.9',
            },
          ],
        },
      ],
    });

    expect(result.isReady, isTrue);
    expect(result.officialDistanceKm, 12.4);
    expect(result.legs, hasLength(1));
    expect(result.segments, hasLength(2));
    expect(result.segments.first.kind, RouteSegmentKind.gpsVerified);
    expect(result.segments.last.kind, RouteSegmentKind.estimated);
  });

  test('TripLegModel prefers official distance for display', () {
    const leg = TripLegModel(
      legId: 'leg_1',
      sequence: 1,
      fromLocation: 'A',
      toLocation: 'B',
      clientName: 'C',
      purpose: 'P',
      clientOfficeAddress: '',
      actualDistanceKmFromTrack: 10.0,
      provisionalDistanceKm: 10.0,
      officialDistanceKm: 9.5,
    );

    expect(leg.displayDistanceKm, 9.5);
    expect(leg.displayDistanceLabel, 'Official');
    expect(leg.hasOfficialDistance, isTrue);
  });
}

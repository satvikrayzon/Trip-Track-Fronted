import 'package:flutter_test/flutter_test.dart';
import 'package:trip_track/core/services/punch_reminder_service.dart';

void main() {
  test('PunchReminderState carries geofence context', () {
    const state = PunchReminderState(
      kind: PunchReminderKind.departureOutsideZone,
      title: 'Return to start to punch',
      message: 'Outside 500m',
      distanceMeters: 1200,
      radiusMeters: 500,
      isUrgent: true,
      requestId: 'req-1',
    );
    expect(state.isUrgent, isTrue);
    expect(state.radiusMeters, 500);
    expect(state.kind, PunchReminderKind.departureOutsideZone);
  });
}

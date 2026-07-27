import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../modules/travel/data/models/travel_request_model.dart';

class DashboardState {
  const DashboardState({
    this.isLoading = true,
    this.totalTrips = 0,
    this.pendingTrips = 0,
    this.completedTrips = 0,
    this.todayDistanceKm = 0,
    this.meetingMinutesToday = 0,
    this.isTrackingActive = false,
    this.activeTrip,
    this.recentTrips = const [],
    this.error,
  });

  final bool isLoading;
  final int totalTrips;
  final int pendingTrips;
  final int completedTrips;
  final double todayDistanceKm;
  final int meetingMinutesToday;
  final bool isTrackingActive;
  final TravelRequestModel? activeTrip;
  final List<TravelRequestModel> recentTrips;
  final String? error;

  DashboardState copyWith({
    bool? isLoading,
    int? totalTrips,
    int? pendingTrips,
    int? completedTrips,
    double? todayDistanceKm,
    int? meetingMinutesToday,
    bool? isTrackingActive,
    TravelRequestModel? activeTrip,
    List<TravelRequestModel>? recentTrips,
    String? error,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      totalTrips: totalTrips ?? this.totalTrips,
      pendingTrips: pendingTrips ?? this.pendingTrips,
      completedTrips: completedTrips ?? this.completedTrips,
      todayDistanceKm: todayDistanceKm ?? this.todayDistanceKm,
      meetingMinutesToday: meetingMinutesToday ?? this.meetingMinutesToday,
      isTrackingActive: isTrackingActive ?? this.isTrackingActive,
      activeTrip: activeTrip ?? this.activeTrip,
      recentTrips: recentTrips ?? this.recentTrips,
      error: error,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier(this._ref) : super(const DashboardState()) {
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_consecutiveFailures >= _maxPollFailures) return;
      unawaited(refresh());
    });
  }

  final Ref _ref;
  Timer? _timer;
  int _consecutiveFailures = 0;
  static const int _maxPollFailures = 3;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final auth = _ref.read(authControllerProvider);
    final userId = auth.currentUserData?.uid;
    if (userId == null) {
      state = state.copyWith(isLoading: false, error: 'Not signed in');
      return;
    }

    if (!state.isLoading && state.recentTrips.isEmpty) {
      state = state.copyWith(isLoading: true);
    }

    final api = _ref.read(travelApiProvider);
    final result = await api.listTravelRequests(page: 1, limit: 10, mine: true);

    result.fold(
      onSuccess: (data) {
        _consecutiveFailures = 0;
        final trips = data.items
            .map(TravelRequestModel.fromMap)
            .where((t) => t.userId == userId)
            .toList()
          ..sort((a, b) => b.requestDate.compareTo(a.requestDate));

        final today = DateTime.now();
        final todayTrips = trips.where((t) {
          final d = t.requestDate;
          return d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        });

        final active = trips.cast<TravelRequestModel?>().firstWhere(
              (t) =>
                  t!.status != 'Completed' &&
                  {
                    'Travelling',
                    'Returning',
                    'In Meeting',
                    'At Client',
                  }.contains(t.status),
              orElse: () => null,
            );

        state = DashboardState(
          isLoading: false,
          totalTrips: data.total,
          pendingTrips: data.pending ??
              trips.where((t) => t.status != 'Completed').length,
          completedTrips: data.completed ??
              trips.where((t) => t.status == 'Completed').length,
          todayDistanceKm: todayTrips.fold(
            0.0,
            (sum, t) => sum + (t.totalDistanceKm ?? t.distance ?? 0),
          ),
          meetingMinutesToday: todayTrips.fold(
            0,
            (sum, t) => sum + (t.totalMeetingDurationMinutes ?? 0),
          ),
          isTrackingActive: active?.trackingStatus == 'tracking',
          activeTrip: active,
          recentTrips: trips.take(5).toList(),
        );
      },
      onFailure: (failure) {
        _consecutiveFailures++;
        state = state.copyWith(
          isLoading: false,
          error: failure.message,
        );
      },
    );
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  return DashboardNotifier(ref);
});

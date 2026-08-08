import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/widgets/trip_detail_map_layout.dart';
import '../../../../modules/travel/data/models/travel_request_model.dart';
import '../../../../modules/user/presentation/controllers/request_details_controller.dart';
import '../../../tracking/domain/entities/trip_timeline_event.dart';
import '../../../../shared/widgets/glass_card.dart';
import '../../../../shared/widgets/punch_action_button.dart';
import '../../../../shared/widgets/shimmer_skeleton.dart';
import '../../../../shared/widgets/trip_timeline.dart';

/// Premium trip detail with timeline, map, and punch actions.
class EnterpriseTripDetailPage extends ConsumerStatefulWidget {
  const EnterpriseTripDetailPage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<EnterpriseTripDetailPage> createState() =>
      _EnterpriseTripDetailPageState();
}

class _EnterpriseTripDetailPageState
    extends ConsumerState<EnterpriseTripDetailPage> {
  RequestDetailsController? _controller;
  bool _loadingTrip = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final api = ref.read(travelApiProvider);
    final result = await api.getById(widget.tripId);
    if (!mounted) return;

    result.fold(
      onSuccess: (data) {
        final trip = TravelRequestModel.fromMap(data).withRecalculatedSummary();
        _controller = RequestDetailsController(initialRequest: trip);
        _controller!.start();
        setState(() {
          _loadingTrip = false;
        });
      },
      onFailure: (f) {
        setState(() {
          _loadingTrip = false;
          _loadError = f.message;
        });
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_loadingTrip) {
      return const Scaffold(body: DashboardSkeleton());
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip Details')),
        body: Center(child: Text(_loadError!)),
      );
    }
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        controller.request,
        controller.adminLivePath,
        controller.isPunching,
      ]),
      builder: (context, _) {
        final trip = controller.request.value;
        if (trip == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return TripDetailMapLayout(
          request: trip,
          onBack: () => context.pop(),
          useGoogleMaps: _useGoogleMaps(),
          adminServerPath: _isLiveStatus(trip) &&
                  controller.adminLivePath.value.isNotEmpty
              ? List<LatLng>.from(controller.adminLivePath.value)
              : null,
          sheetFooter: !_isAdmin() && controller.primaryActionLabel.isNotEmpty
              ? (context) => ValueListenableBuilder<bool>(
                    valueListenable: controller.isPunching,
                    builder: (context, isPunching, _) {
                      final next = controller.primaryActionLabel;
                      return PunchActionButton(
                        type: _mapNextPunch(next),
                        isLoading: isPunching,
                        enabled: next.isNotEmpty,
                        onPressed: () async {
                          await controller.punchNextStep();
                          return !controller.isPunching.value;
                        },
                      );
                    },
                  )
              : null,
          sheetBuilder: (context, scrollController) {
            return RefreshIndicator(
              onRefresh: controller.refreshRequest,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _StatusHeader(trip: trip),
                  const SizedBox(height: 16),
                  _MetricsRow(trip: trip),
                  const SizedBox(height: 20),
                  Text(
                    'Timeline',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    child: TripTimeline(
                      events: _buildTimeline(trip),
                    ),
                  ),
                  if (!_isAdmin()) ...[
                    const SizedBox(height: 20),
                    _PunchPanel(
                      controller: controller,
                      trip: trip,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isAdmin() =>
      ref.read(authControllerProvider).currentUserData?.role == 'admin';

  bool _isLiveStatus(TravelRequestModel trip) {
    final s = trip.status;
    return s == 'Travelling' ||
        s == 'Returning' ||
        s == 'At Client' ||
        s == 'In Meeting';
  }

  bool _useGoogleMaps() => googleMapsSupported();

  List<TripTimelineEvent> _buildTimeline(TravelRequestModel trip) {
    final leg = trip.activeLeg ?? trip.tripLegs.firstOrNull;
    if (leg == null) return [];

    return [
      TripTimelineEvent(
        type: TripTimelineEventType.departure,
        title: 'Departure',
        subtitle: leg.fromLocation,
        timestamp: leg.departurePunch?.time,
        isCompleted: leg.departurePunch != null,
        isActive: leg.departurePunch == null,
      ),
      TripTimelineEvent(
        type: TripTimelineEventType.arrival,
        title: 'Arrival',
        subtitle: leg.toLocation,
        timestamp: leg.arrivalPunch?.time,
        isCompleted: leg.arrivalPunch != null,
        isActive: leg.departurePunch != null && leg.arrivalPunch == null,
      ),
      if (!leg.isReturnLeg) ...[
        TripTimelineEvent(
          type: TripTimelineEventType.meetingStart,
          title: 'Meeting Start',
          subtitle: leg.clientName,
          timestamp: leg.meetingStartPunch?.time,
          isCompleted: leg.meetingStartPunch != null,
          isActive: leg.arrivalPunch != null && leg.meetingStartPunch == null,
        ),
        TripTimelineEvent(
          type: TripTimelineEventType.meetingEnd,
          title: 'Meeting End',
          timestamp: leg.meetingEndPunch?.time,
          isCompleted: leg.meetingEndPunch != null,
          isActive:
              leg.meetingStartPunch != null && leg.meetingEndPunch == null,
        ),
      ],
      TripTimelineEvent(
        type: TripTimelineEventType.statusChange,
        title: trip.status,
        subtitle: 'Current status',
        isCompleted: trip.status == 'Completed',
        isActive: trip.status != 'Completed',
      ),
    ];
  }

  PunchType _mapNextPunch(String label) {
    if (label.contains('Meeting Start')) return PunchType.meetingStart;
    if (label.contains('Meeting End')) return PunchType.meetingEnd;
    if (label.contains('Arrival')) return PunchType.arrival;
    return PunchType.departure;
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.trip});

  final TravelRequestModel trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trip.displayToLocation,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            trip.routeSummary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trip.status,
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.trip});

  final TravelRequestModel trip;

  @override
  Widget build(BuildContext context) {
    final dist = trip.effectiveDistanceKm > 0
        ? trip.effectiveDistanceKm
        : (trip.distance ?? 0);
    final travel = trip.totalTravelDurationMinutes;
    final meeting = trip.totalMeetingDurationMinutes;
    return Row(
      children: [
        Expanded(
          child: _MetricChip(
            label: 'Distance',
            value: '${dist.toStringAsFixed(1)} km',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricChip(
            label: 'Travel',
            value: '$travel min',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricChip(
            label: 'Meeting',
            value: '$meeting min',
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _PunchPanel extends StatelessWidget {
  const _PunchPanel({
    required this.controller,
    required this.trip,
  });

  final RequestDetailsController controller;
  final TravelRequestModel trip;

  @override
  Widget build(BuildContext context) {
    final next = controller.primaryActionLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Punch Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isPunching,
          builder: (context, isPunching, _) => PunchActionButton(
            type: _mapNextPunch(next),
            isLoading: isPunching,
            enabled: next.isNotEmpty,
            onPressed: () async {
              await controller.punchNextStep();
              return !controller.isPunching.value;
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: controller.isPunching,
                builder: (context, isPunching, _) => PunchActionButton(
                  type: PunchType.departure,
                  enabled: next.contains('Departure') || next.contains('Start'),
                  isLoading: isPunching,
                  onPressed: () async {
                    if (!next.contains('Departure') &&
                        !next.contains('Start')) {
                      return false;
                    }
                    await controller.punchNextStep();
                    return true;
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  PunchType _mapNextPunch(String label) {
    if (label.contains('Meeting Start')) return PunchType.meetingStart;
    if (label.contains('Meeting End')) return PunchType.meetingEnd;
    if (label.contains('Arrival')) return PunchType.arrival;
    return PunchType.departure;
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

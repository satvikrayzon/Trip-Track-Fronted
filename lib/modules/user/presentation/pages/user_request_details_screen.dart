import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../core/routes/app_routes.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/services/punch_reminder_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/trip_detail_map_layout.dart';
import '../../../../core/widgets/trip_tracking_coverage_card.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';
import '../../../travel/data/models/travel_request_model.dart';
import 'add_next_client_screen.dart';
import '../controllers/add_next_client_controller.dart';
import '../controllers/request_details_controller.dart';
import '../../../travel/utils/travel_request_edit_utils.dart';

/// User Request Details Screen with multi-leg GPS punch tracking.
class UserRequestDetailsScreen extends StatefulWidget {
  const UserRequestDetailsScreen({super.key});

  @override
  State<UserRequestDetailsScreen> createState() =>
      _UserRequestDetailsScreenState();
}

class _UserRequestDetailsScreenState extends State<UserRequestDetailsScreen> {
  late final RequestDetailsController _controller;
  late final AppAuthController _authController;

  @override
  void initState() {
    super.initState();
    _controller = RequestDetailsController();
    _controller.start();
    _authController = ServiceLocator.I.get<AppAuthController>();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isAdmin => _authController.currentUserData?.role == 'admin';

  bool get _canViewTrackingCoverage => _authController.isHodOrAdmin;

  bool get _canViewServerTrail {
    final curUser = _authController.currentUserApiId;
    final reqUser = _controller.request.value?.userId;
    return _authController.isHodOrAdmin || (curUser != null && curUser == reqUser);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _controller.request,
        _controller.adminLivePath,
      ]),
      builder: (context, _) {
        final request = _controller.request.value;
        if (request == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return TripDetailMapLayout(
          key: ValueKey(request.requestId),
          request: request,
          onBack: () => Navigator.of(context).maybePop(),
          useGoogleMaps: googleMapsSupported(),
          adminServerPath:
              _canViewServerTrail && _controller.adminLivePath.value.isNotEmpty
                  ? List<LatLng>.from(_controller.adminLivePath.value)
                  : null,
          sheetFooter: (context) => AnimatedBuilder(
                animation: Listenable.merge([
                  _controller.request,
                  _controller.isPunching,
                  _controller.isDeleting,
                  _controller.punchReminder,
                ]),
                builder: (context, _) {
                  final footer = _buildSheetFooter(context, _controller, request);
                  return footer ?? const SizedBox.shrink();
                },
              ),
          sheetBuilder: (context, scrollController) {
            return RefreshIndicator(
              onRefresh: _controller.refreshRequest,
              child: ListView(
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.defaultPadding,
                  8,
                  AppConstants.defaultPadding,
                  240, // Extra padding to clear the bottom action buttons
                ),
                children: [
                  _buildStatusCard(request),
                  AnimatedBuilder(
                    animation: _controller.punchReminder,
                    builder: (context, _) {
                      final reminder = _controller.punchReminder.value;
                      if (reminder == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(
                          top: AppConstants.defaultPadding,
                        ),
                        child: _buildPunchReminderBanner(reminder),
                      );
                    },
                  ),
                  const SizedBox(height: AppConstants.defaultPadding),
                  _buildLiveGpsCard(request),
                  if (_canViewTrackingCoverage) ...[
                    const SizedBox(height: AppConstants.defaultPadding),
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _controller.trackingCoverage,
                        _controller.isCoverageLoading,
                      ]),
                      builder: (context, _) => TripTrackingCoverageCard(
                        coverage: _controller.trackingCoverage.value,
                        isLoading: _controller.isCoverageLoading.value,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppConstants.defaultPadding),
                  _buildSummaryCard(request),
                  const SizedBox(height: AppConstants.defaultPadding),
                  _buildTravelDetailsCard(request),
                  const SizedBox(height: AppConstants.defaultPadding),
                  _buildRouteTimeline(request),
                  if (request.status == 'Completed' && !request.needsReturnArrivalPunch) ...[
                    const SizedBox(height: AppConstants.defaultPadding * 2),
                    _buildCoolCompletedBanner(),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusCard(TravelRequestModel request) {
    final statusStyle = _statusStyle(request.status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: statusStyle.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusStyle.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusStyle.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusStyle.icon, color: AppColors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.status,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusDescription(request),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(TravelRequestModel request) {
    return AppCard(
      type: AppCardType.elevatedCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Trip Summary',
                style: AppTextStyles.titleMedium
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          Row(
            children: [
              Expanded(
                child: _buildSummaryTile(
                  Icons.straighten,
                  '${request.effectiveDistanceKm.toStringAsFixed(2)} km',
                  request.displayDistanceLabel,
                ),
              ),
              Expanded(
                child: _buildSummaryTile(
                  Icons.handshake_outlined,
                  '${request.totalMeetings}',
                  'Meetings',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          Row(
            children: [
              Expanded(
                child: _buildSummaryTile(
                  Icons.directions_car_outlined,
                  _formatDuration(request.totalTravelDurationMinutes),
                  'Travel Time',
                ),
              ),
              Expanded(
                child: _buildSummaryTile(
                  Icons.timer_outlined,
                  _formatDuration(request.totalMeetingDurationMinutes),
                  'Meeting Time',
                ),
              ),
            ],
          ),
          if (request.displayTravelAllowance > 0 ||
              (request.fuelType != null &&
                  request.fuelType!.isNotEmpty &&
                  AppConstants.vehicleRequiresFuelType(
                    request.vehicleType,
                  ))) ...[
            const SizedBox(height: AppConstants.defaultPadding),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryTile(
                    Icons.payments_outlined,
                    request.displayTravelAllowance > 0
                        ? '₹${request.displayTravelAllowance.toStringAsFixed(2)}'
                        : '—',
                    'Travel Allowance',
                  ),
                ),
                if (request.fuelRatePerKm != null && request.fuelRatePerKm! > 0)
                  Expanded(
                    child: _buildSummaryTile(
                      Icons.local_gas_station_outlined,
                      '₹${request.fuelRatePerKm!.toStringAsFixed(2)}/km',
                      AppConstants.fuelTypeLabel(request.fuelType),
                    ),
                  ),
              ],
            ),
          ],
          if (request.enableLiveTracking &&
              AppConstants.featureLiveGpsTracking &&
              (request.totalMovingMinutesFromTrack > 0 ||
                  request.totalStoppedMinutesFromTrack > 0)) ...[
            const SizedBox(height: AppConstants.defaultPadding),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryTile(
                    Icons.navigation_outlined,
                    _formatDuration(request.totalMovingMinutesFromTrack),
                    'Moving (GPS)',
                  ),
                ),
                Expanded(
                  child: _buildSummaryTile(
                    Icons.pause_circle_outline,
                    _formatDuration(request.totalStoppedMinutesFromTrack),
                    'Stopped (GPS)',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveGpsCard(TravelRequestModel request) {
    if (!request.enableLiveTracking || !AppConstants.featureLiveGpsTracking) {
      return const SizedBox.shrink();
    }

    return AppCard(
      type: AppCardType.outlinedCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Live GPS',
                style: AppTextStyles.titleSmall.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Status: ${request.trackingStatus ?? 'idle'}',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          if (request.tripStartedAt != null)
            Text(
              'Started: ${DateFormat('dd MMM, hh:mm a').format(request.tripStartedAt!)}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          if (request.tripEndedAt != null)
            Text(
              'Ended: ${DateFormat('dd MMM, hh:mm a').format(request.tripEndedAt!)}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          Text(
            'GPS points stored (this device): ${request.routePointCount}',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(IconData icon, String value, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelDetailsCard(TravelRequestModel request) {
    return AppCard(
      type: AppCardType.elevatedCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'Travel Information',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          _buildInfoRow(Icons.person_outline, 'Employee', request.userName),
          if (request.clientName.isNotEmpty)
            _buildInfoRow(
              Icons.business_outlined,
              'Client',
              request.clientName,
            ),
          _buildInfoRow(
            AppConstants.isCarVehicle(request.vehicleType)
                ? Icons.directions_car_outlined
                : Icons.motorcycle_outlined,
            'Vehicle',
            AppConstants.vehicleTypeLabel(request.vehicleType),
          ),
          if (request.fuelType != null && request.fuelType!.isNotEmpty)
            _buildInfoRow(
              Icons.local_gas_station_outlined,
              'Fuel',
              AppConstants.fuelTypeLabel(request.fuelType),
            ),
          if (request.purpose != null && request.purpose!.isNotEmpty)
            _buildInfoRow(
              Icons.assignment_outlined,
              'Purpose',
              request.purpose!,
            ),
          if (request.notes != null && request.notes!.isNotEmpty)
            _buildInfoRow(Icons.notes_outlined, 'Notes', request.notes!),
          _buildInfoRow(
            Icons.calendar_today_outlined,
            'Created',
            DateFormat('dd MMM yyyy, hh:mm a').format(request.requestDate),
          ),
          _buildInfoRow(Icons.route_outlined, 'Route', request.routeSummary),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTimeline(TravelRequestModel request) {
    final legs = request.tripLegs.isEmpty
        ? request.ensureTripLegs().tripLegs
        : request.tripLegs;

    if (legs.isEmpty) {
      return AppCard(
        type: AppCardType.outlinedCard,
        child: Text(
          'No trip legs found for this request.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Route Timeline',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.defaultPadding),
        ...legs.map((leg) {
          final isActive = leg.sequence == request.currentLegIndex + 1 &&
              (request.status != 'Completed' ||
                  request.needsReturnArrivalPunch);
          return _buildLegCard(leg, isActive);
        }),
      ],
    );
  }

  Widget _buildLegCard(TripLegModel leg, bool isActive) {
    final reqVal = _controller.request.value;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.greyLight,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: leg.isReturnLeg
                        ? AppColors.info.withValues(alpha: 0.12)
                        : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    leg.isReturnLeg
                        ? Icons.keyboard_return
                        : Icons.business_center_outlined,
                    color: leg.isReturnLeg ? AppColors.info : AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Leg ${leg.sequence}: ${leg.displayTitle}',
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${leg.fromLocation} -> ${leg.toLocation}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Active',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (reqVal != null && canEditTripLeg(reqVal, leg)) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                    tooltip: 'Edit Leg',
                    onPressed: () {
                      unawaited(
                        AppNavigation.to(
                          AppRoutes.userCreateRequest,
                          arguments: {
                            'edit': true,
                            'request': reqVal,
                            'legIndex': leg.sequence - 1,
                          },
                        ).then((_) => _controller.refreshRequest()),
                      );
                    },
                  ),
                ],
              ],
            ),
            if (!leg.isReturnLeg) ...[
              const SizedBox(height: 12),
              _buildClientDetails(leg),
            ],
            const SizedBox(height: 12),
            _buildLegMetrics(leg),
            if (leg.trackMovingDurationMinutes != null ||
                leg.trackStoppedDurationMinutes != null) ...[
              const SizedBox(height: 8),
              Text(
                'GPS: moving ${_formatDuration(leg.trackMovingDurationMinutes ?? 0)} · stopped ${_formatDuration(leg.trackStoppedDurationMinutes ?? 0)}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildPunchRows(leg),
          ],
        ),
      ),
    );
  }

  Widget _buildClientDetails(TripLegModel leg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildCompactText('Purpose', leg.purpose),
        ],
      ),
    );
  }

  Widget _buildCompactText(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegMetrics(TripLegModel leg) {
    final distKm = leg.displayDistanceKm;
    return Row(
      children: [
        Expanded(
          child: _buildSmallMetric(
            Icons.straighten,
            distKm == null ? '-' : '${distKm.toStringAsFixed(2)} km',
            leg.displayDistanceLabel,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSmallMetric(
            Icons.directions_car_outlined,
            leg.travelDurationMinutes == null
                ? '-'
                : _formatDuration(leg.travelDurationMinutes!),
            'Travel',
          ),
        ),
        if (!leg.isReturnLeg) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _buildSmallMetric(
              Icons.timer_outlined,
              leg.meetingDurationMinutes == null
                  ? '-'
                  : _formatDuration(leg.meetingDurationMinutes!),
              'Meeting',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSmallMetric(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunchRows(TripLegModel leg) {
    final punches = <_PunchDisplay>[
      _PunchDisplay('Departure', Icons.logout, leg.departurePunch),
      _PunchDisplay('Arrival', Icons.flag_outlined, leg.arrivalPunch),
      if (!leg.isReturnLeg)
        _PunchDisplay(
            'Meeting Start', Icons.play_circle_outline, leg.meetingStartPunch),
      if (!leg.isReturnLeg)
        _PunchDisplay(
            'Meeting End', Icons.stop_circle_outlined, leg.meetingEndPunch),
    ];

    return Column(
      children: punches.map((punch) => _buildPunchRow(punch)).toList(),
    );
  }

  Widget _buildPunchRow(_PunchDisplay display) {
    final punch = display.punch;
    final hasPunch = punch != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: hasPunch
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.greyLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              display.icon,
              color: hasPunch ? AppColors.success : AppColors.textSecondary,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display.label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPunch
                      ? '${DateFormat('dd MMM, hh:mm a').format(punch.time)} | ${punch.latitude.toStringAsFixed(6)}, ${punch.longitude.toStringAsFixed(6)}'
                      : 'Pending',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (hasPunch && punch.address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    punch.address,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildSheetFooter(
    BuildContext context,
    RequestDetailsController controller,
    TravelRequestModel request,
  ) {
    final actions = _isAdmin
        ? null
        : _buildActionsContent(context, controller, request);
    if (actions == null) return null;

    return actions;
  }

  Widget _buildPunchReminderBanner(PunchReminderState reminder) {
    final color = reminder.isUrgent ? AppColors.warning : AppColors.primary;
    final bg = reminder.isUrgent
        ? const Color(0xFFFFF3E0)
        : const Color(0xFFE0F2F1);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reminder.isUrgent
                ? Icons.warning_amber_rounded
                : Icons.notifications_active_outlined,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reminder.message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildActionsContent(
    BuildContext context,
    RequestDetailsController controller,
    TravelRequestModel request,
  ) {
    final current = controller.request.value ?? request;
    final reminder = controller.punchReminder.value;

    final actionLabel = controller.primaryActionLabel;
    if (actionLabel.isNotEmpty) {
      final button = AppButton(
        text: actionLabel,
        type: AppButtonType.primary,
        size: AppButtonSize.large,
        icon: Icons.play_arrow_rounded,
        isLoading: controller.isPunching.value,
        onPressed:
            controller.isPunching.value ? null : controller.punchNextStep,
      );
      if (reminder == null) return button;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPunchReminderBanner(reminder),
          const SizedBox(height: 10),
          button,
        ],
      );
    }

    if (current.canAddNextClient) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            text: 'Add Next Client',
            type: AppButtonType.primary,
            size: AppButtonSize.large,
            icon: Icons.add_location_alt_outlined,
            onPressed: () => _openAddClientScreen(context, controller),
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          AppButton(
            text: 'Start Return Trip',
            type: AppButtonType.secondary,
            size: AppButtonSize.large,
            icon: Icons.keyboard_return,
            onPressed: controller.startReturnTrip,
          ),
        ],
      );
    }

    return null;
  }

  Future<void> _openAddClientScreen(
    BuildContext context,
    RequestDetailsController controller,
  ) async {
    final current = controller.request.value;
    if (current == null || current.tripLegs.isEmpty) return;

    final input = await Navigator.of(context).push<AddNextClientInput>(
      MaterialPageRoute(
        builder: (_) => AddNextClientScreen(request: current),
      ),
    );
    if (input == null) return;

    await controller.addClientLeg(
      clientName: input.clientName,
      destination: input.destination,
      purpose: input.purpose,
    );
  }

  _StatusStyle _statusStyle(String status) {
    switch (status) {
      case 'Ready To Start':
        return const _StatusStyle(
          color: AppColors.warning,
          background: Color(0xFFFFF8E1),
          icon: Icons.schedule_rounded,
        );
      case 'Travelling':
      case 'Returning':
        return const _StatusStyle(
          color: AppColors.info,
          background: Color(0xFFE3F2FD),
          icon: Icons.directions_car,
        );
      case 'At Client':
        return const _StatusStyle(
          color: AppColors.accent,
          background: Color(0xFFE0F7FA),
          icon: Icons.location_on,
        );
      case 'In Meeting':
        return const _StatusStyle(
          color: AppColors.primary,
          background: Color(0xFFE0F2F1),
          icon: Icons.handshake_outlined,
        );
      case 'Ready For Next':
      case 'Ready To Return':
        return const _StatusStyle(
          color: AppColors.warning,
          background: Color(0xFFFFF3E0),
          icon: Icons.next_plan_outlined,
        );
      case 'Completed':
        return const _StatusStyle(
          color: AppColors.success,
          background: Color(0xFFE8F5E9),
          icon: Icons.check_circle_rounded,
        );
      default:
        return const _StatusStyle(
          color: AppColors.grey,
          background: Color(0xFFF5F5F5),
          icon: Icons.info_rounded,
        );
    }
  }

  String _statusDescription(TravelRequestModel request) {
    final leg = request.activeLeg;
    switch (request.status) {
      case 'Ready To Start':
        final radius = AppConstants.departureGeofenceRadiusMeters.round();
        return 'Be within ${radius}m of ${leg?.fromLocation ?? 'your start point'}, '
            'then tap Start Departure';
      case 'Travelling':
        final arrivalRadius = AppConstants.arrivalGeofenceRadiusMeters.round();
        return 'Be within ${arrivalRadius}m of '
            '${leg?.toLocation ?? 'destination'}, then tap Mark Arrival';
      case 'At Client':
        return 'Tap Start Meeting when the visit begins';
      case 'In Meeting':
        return 'Tap End Meeting when the visit is finished';
      case 'Ready For Next':
        return 'Add another client or start the return trip';
      case 'Ready To Return':
        return 'Tap Start Return when leaving for your starting location';
      case 'Returning':
        final arrivalRadius = AppConstants.arrivalGeofenceRadiusMeters.round();
        return 'Be within ${arrivalRadius}m of '
            '${leg?.toLocation ?? 'your starting location'}, '
            'then tap Mark Return Arrival';
      case 'Completed':
        return 'All travel legs and meetings are completed';
      default:
        return 'Trip status information';
    }
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours == 0) return '${remainingMinutes}m';
    if (remainingMinutes == 0) return '${hours}h';
    return '${hours}h ${remainingMinutes}m';
  }
  Widget _buildCoolCompletedBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: AppColors.success,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Trip Completed',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All objectives have been met successfully.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PunchDisplay {
  final String label;
  final IconData icon;
  final TripPunchModel? punch;

  const _PunchDisplay(this.label, this.icon, this.punch);
}

class _StatusStyle {
  final Color color;
  final Color background;
  final IconData icon;

  const _StatusStyle({
    required this.color,
    required this.background,
    required this.icon,
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/widgets/hover_widget.dart';
import '../../../../core/widgets/fade_slide_transition.dart';

import '../../../../core/app_dialog.dart';
import '../../../../core/app_messenger.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/router/navigation_helper.dart';
import '../../../../core/services/punch_reminder_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/device_utils.dart';
import '../../../../core/utils/font_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/custom_appbar.dart';
import '../../../../core/widgets/header_widget.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';
import '../../../travel/utils/travel_request_edit_utils.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../controllers/user_home_controller.dart';

/// User Home Screen - Clean Minimal Design
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  late final UserHomeController _controller;
  late final AppAuthController _authController;

  @override
  void initState() {
    super.initState();
    _controller = UserHomeController();
    _controller.start();
    _authController = ServiceLocator.I.get<AppAuthController>();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    return HeaderWidget(
      headerChild: CustomAppBar(
        title: _authController.currentUserData?.name ?? '',
        showBackButton: false,
        action: [
          // Hide logout button on desktop since sidebar has it
          if (!isDesktop)
            GestureDetector(
              onTap: () => _handleLogout(),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 12.scp(context), vertical: 8.scp(context)),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20.scp(context)),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Colors.white,
                      size: 16.scp(context),
                    ),
                    SizedBox(width: 6.scp(context)),
                    Text(
                      'Logout',
                      style: FontUtilities.style(
                        fontSize: 12.scp(context),
                        fontColor: Colors.white,
                        fontWeight: FWT.semiBold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller.isLoading,
        builder: (context, child) {
          if (_controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return child!;
        },
        child: RefreshIndicator(
          onRefresh: _controller.refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(isDesktop ? 24 : 16.scp(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Statistics section (rebuilds only when stats change)
                AnimatedBuilder(
                  animation: Listenable.merge([
                    _controller.totalRequests,
                    _controller.pendingRequests,
                    _controller.completedRequests,
                    _controller.recentRequests,
                  ]),
                  builder: (context, _) => FadeSlideTransition(
                    direction: AnimationDirection.up,
                    milliseconds: 500,
                    child: _buildStatistics(context),
                  ),
                ),
                SizedBox(height: isDesktop ? 32 : 24.scp(context)),

                if (isDesktop)
                  FadeSlideTransition(
                    direction: AnimationDirection.up,
                    milliseconds: 700,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              // Active trip banner section
                              AnimatedBuilder(
                                animation: _controller.activeTrip,
                                builder: (context, _) {
                                  final trip = _controller.activeTrip.value;
                                  if (trip == null) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 24.0),
                                    child: _buildActiveTripBanner(context, trip),
                                  );
                                },
                              ),
                              AnimatedBuilder(
                                animation: Listenable.merge([
                                  _controller.recentRequests,
                                  _controller.deletingRequestId,
                                ]),
                                builder: (context, _) => _buildRecentRequests(context),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 2,
                          child: _buildQuickActions(context),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // Active trip banner section for mobile
                  AnimatedBuilder(
                    animation: _controller.activeTrip,
                    builder: (context, _) {
                      final trip = _controller.activeTrip.value;
                      if (trip == null) return const SizedBox.shrink();
                      return Column(
                        children: [
                          _buildActiveTripBanner(context, trip),
                          SizedBox(height: 24.scp(context)),
                        ],
                      );
                    },
                  ),
                  FadeSlideTransition(
                    direction: AnimationDirection.up,
                    milliseconds: 600,
                    child: _buildQuickActions(context),
                  ),
                  SizedBox(height: 24.scp(context)),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _controller.recentRequests,
                      _controller.deletingRequestId,
                    ]),
                    builder: (context, _) => FadeSlideTransition(
                      direction: AnimationDirection.up,
                      milliseconds: 700,
                      child: _buildRecentRequests(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTripBanner(
    BuildContext context,
    TravelRequestModel trip,
  ) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    final bannerContent = GestureDetector(
      onTap: () => unawaited(
        AppNavigation.to(
          AppRoutes.userRequestDetails,
          arguments: trip,
        ).then((_) => _controller.refresh()),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isDesktop ? 20 : 16.scp(context)),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.scp(context)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E7D32).withOpacity(0.25),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10.scp(context),
                  height: 10.scp(context),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8.scp(context)),
                Text(
                  'Continue Trip',
                  style: FontUtilities.style(
                    fontSize: 14.scp(context),
                    fontColor: Colors.white,
                    fontWeight: FWT.semiBold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.scp(context),
                    vertical: 4.scp(context),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20.scp(context)),
                  ),
                  child: Text(
                    trip.status,
                    style: FontUtilities.style(
                      fontSize: 11.scp(context),
                      fontColor: Colors.white,
                      fontWeight: FWT.medium,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.scp(context)),
            Text(
              '${trip.fromLocation} → ${trip.displayToLocation}',
              style: FontUtilities.style(
                fontSize: 16.scp(context),
                fontColor: Colors.white,
                fontWeight: FWT.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 8.scp(context)),
            Text(
              'Tap to resume punches and tracking',
              style: FontUtilities.style(
                fontSize: 12.scp(context),
                fontColor: Colors.white.withOpacity(0.9),
                fontWeight: FWT.regular,
              ),
            ),
          ],
        ),
      ),
    );

    final reminderListenable =
        ServiceLocator.I.has<PunchReminderService>()
            ? ServiceLocator.I.get<PunchReminderService>().reminder
            : null;

    final withReminder = reminderListenable == null
        ? bannerContent
        : AnimatedBuilder(
            animation: reminderListenable,
            builder: (context, _) {
              final reminder = reminderListenable.value;
              if (reminder == null ||
                  reminder.requestId != trip.requestId) {
                return bannerContent;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  bannerContent,
                  SizedBox(height: 10.scp(context)),
                  Container(
                    padding: EdgeInsets.all(12.scp(context)),
                    decoration: BoxDecoration(
                      color: reminder.isUrgent
                          ? const Color(0xFFFFF3E0)
                          : const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(12.scp(context)),
                      border: Border.all(
                        color: (reminder.isUrgent
                                ? AppColors.warning
                                : AppColors.primary)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      '${reminder.title}: ${reminder.message}',
                      style: FontUtilities.style(
                        fontSize: 12.scp(context),
                        fontColor: AppColors.textPrimary,
                        fontWeight: FWT.medium,
                      ),
                    ),
                  ),
                ],
              );
            },
          );

    if (isDesktop) {
      return HoverWidget(child: withReminder);
    }
    return withReminder;
  }

  Widget _buildResponsiveStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    if (!isDesktop) {
      return _buildMiniStatCard(
        context,
        title: title,
        value: value,
        icon: icon,
        color: color,
      );
    }

    return HoverWidget(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
          border: Border.all(
            color: Colors.grey.shade100,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: FontUtilities.style(
                      fontSize: 24,
                      fontColor: const Color(0xFF1F2937),
                      fontWeight: FWT.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: FontUtilities.style(
                      fontSize: 13,
                      fontColor: const Color(0xFF6B7280),
                      fontWeight: FWT.medium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: FontUtilities.style(
            fontSize: isDesktop ? 22 : 20.scp(context),
            fontColor: const Color(0xFF2D3748),
            fontWeight: FWT.bold,
          ),
        ),
        SizedBox(height: isDesktop ? 16 : 12.scp(context)),
        Row(
          children: [
            Expanded(
              child: _buildResponsiveStatCard(
                context,
                title: 'Total',
                value: _controller.totalRequests.value.toString(),
                icon: Icons.assignment_outlined,
                color: const Color(0xFF2196F3),
              ),
            ),
            SizedBox(width: isDesktop ? 16 : 8.scp(context)),
            Expanded(
              child: _buildResponsiveStatCard(
                context,
                title: 'Pending',
                value: _controller.pendingRequests.value.toString(),
                icon: Icons.schedule,
                color: const Color(0xFFFF9800),
              ),
            ),
            SizedBox(width: isDesktop ? 16 : 8.scp(context)),
            Expanded(
              child: _buildResponsiveStatCard(
                context,
                title: 'Done',
                value: _controller.completedRequests.value.toString(),
                icon: Icons.check_circle_outline,
                color: const Color(0xFF4CAF50),
              ),
            ),
            SizedBox(width: isDesktop ? 16 : 8.scp(context)),
            Expanded(
              child: _buildResponsiveStatCard(
                context,
                title: 'Month',
                value: _controller.recentRequests.value.length.toString(),
                icon: Icons.calendar_today,
                color: const Color(0xFF9C27B0),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: 8.scp(context), vertical: 10.scp(context)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.scp(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(6.scp(context)),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.scp(context)),
            ),
            child: Icon(icon, color: color, size: 16.scp(context)),
          ),
          SizedBox(height: 6.scp(context)),
          Text(
            value,
            style: FontUtilities.style(
              fontSize: 18.scp(context),
              fontColor: color,
              fontWeight: FWT.bold,
            ),
          ),
          SizedBox(height: 2.scp(context)),
          Text(
            title,
            style: FontUtilities.style(
              fontSize: 10.scp(context),
              fontColor: const Color(0xFF718096),
              fontWeight: FWT.medium,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    final actions = [
      _buildActionButton(
        context,
        title: 'New Request',
        icon: Icons.add_circle,
        color: AppColors.primary,
        onTap: () => _handleCreateRequest(),
      ),
      _buildActionButton(
        context,
        title: 'My Requests',
        icon: Icons.list_alt,
        color: const Color(0xFF2196F3),
        onTap: () => AppNavigation.to(AppRoutes.userRequestList),
      ),
      if (_authController.isHodOrAdmin) ...[
        _buildActionButton(
          context,
          title: 'Live Team Map',
          icon: Icons.map_rounded,
          color: const Color(0xFF009688),
          onTap: () => AppNavigator.push(AppPaths.liveMap, context: context),
        ),
        _buildActionButton(
          context,
          title: 'Team Requests',
          icon: Icons.assignment_ind,
          color: const Color(0xFF673AB7),
          onTap: () => AppNavigation.to(AppRoutes.adminTravelRequests),
        ),
      ],
      _buildActionButton(
        context,
        title: 'Profile',
        icon: Icons.person,
        color: const Color(0xFF4CAF50),
        onTap: () => AppNavigation.to(AppRoutes.profile),
      ),
      _buildActionButton(
        context,
        title: 'Settings',
        icon: Icons.settings,
        color: const Color(0xFF757575),
        onTap: () => AppNavigation.to(AppRoutes.settings),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: FontUtilities.style(
            fontSize: isDesktop ? 22 : 20.scp(context),
            fontColor: const Color(0xFF2D3748),
            fontWeight: FWT.bold,
          ),
        ),
        SizedBox(height: isDesktop ? 16 : 12.scp(context)),
        if (isDesktop)
          Column(
            children: actions
                .map((action) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: action,
                    ))
                .toList(),
          )
        else
          Column(
            children: [
              for (int i = 0; i < actions.length; i += 2)
                Padding(
                  padding: EdgeInsets.only(bottom: i + 2 < actions.length ? 12.scp(context) : 0),
                  child: Row(
                    children: [
                      Expanded(child: actions[i]),
                      SizedBox(width: 12.scp(context)),
                      Expanded(
                        child: i + 1 < actions.length
                            ? actions[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    final buttonContent = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isDesktop ? 18 : 16.scp(context)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.scp(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              offset: const Offset(0, 2),
              blurRadius: 8,
            ),
          ],
          border: isDesktop
              ? Border.all(color: Colors.grey.shade100, width: 1)
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.scp(context)),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10.scp(context)),
              ),
              child: Icon(icon, color: color, size: 24.scp(context)),
            ),
            SizedBox(width: 12.scp(context)),
            Expanded(
              child: Text(
                title,
                style: FontUtilities.style(
                  fontSize: 15.scp(context),
                  fontColor: const Color(0xFF2D3748),
                  fontWeight: FWT.semiBold,
                ),
              ),
            ),
            Icon(
              isDesktop ? Icons.chevron_right_rounded : Icons.arrow_forward_ios,
              color: const Color(0xFF718096),
              size: 16.scp(context),
            ),
          ],
        ),
      ),
    );

    if (isDesktop) {
      return HoverWidget(child: buttonContent);
    }
    return buttonContent;
  }

  Widget _buildRecentRequests(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Requests',
              style: FontUtilities.style(
                fontSize: isDesktop ? 22 : 20.scp(context),
                fontColor: const Color(0xFF2D3748),
                fontWeight: FWT.bold,
              ),
            ),
            TextButton(
              onPressed: () => AppNavigation.to(AppRoutes.userRequestList),
              child: Text(
                'View All',
                style: FontUtilities.style(
                  fontSize: 14.scp(context),
                  fontColor: AppColors.primary,
                  fontWeight: FWT.semiBold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: isDesktop ? 16 : 12.scp(context)),
        if (_controller.recentRequests.value.isEmpty)
          Container(
            padding: EdgeInsets.all(40.scp(context)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.scp(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  offset: const Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox,
                    size: 48.scp(context),
                    color: const Color(0xFF718096).withOpacity(0.5),
                  ),
                  SizedBox(height: 12.scp(context)),
                  Text(
                    'No travel requests yet',
                    style: FontUtilities.style(
                      fontSize: 16.scp(context),
                      fontColor: const Color(0xFF718096),
                      fontWeight: FWT.medium,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._controller.recentRequests.value.map((request) {
            final isDeleting =
                _controller.deletingRequestId.value == request.restResourceId;
            final card = TravelRequestCard(
              name: request.userName,
              clientName: request.clientName.isNotEmpty
                  ? request.clientName
                  : request.userName,
              fromLocation: request.fromLocation,
              toLocation: request.displayToLocation,
              legsSummary: request.compactLegsSummary,
              metricsSummary: request.compactMetricsSummary,
              travelAllowance: request.shouldShowTravelAllowance
                  ? request.displayTravelAllowance
                  : null,
              fuelType: request.fuelType,
              showClientName: request.tripLegs.length <= 1,
              vehicleType: request.vehicleType,
              status: request.status,
              dateTime: request.requestDate,
              isSynced: true,
              startImageUrl: request.startImageUrl,
              endImageUrl: request.endImageUrl,
              showEditButton: canEditTravelRequest(request),
              showDeleteButton: canDeleteTravelRequest(request),
              isDeleteLoading: isDeleting,
              onTap: () => unawaited(
                AppNavigation.to(
                  AppRoutes.userRequestDetails,
                  arguments: request,
                ).then((_) => _controller.refresh()),
              ),
              onEdit: () => _handleEditRequest(request),
              onDelete: () => _handleDeleteRequest(request),
            );

            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: HoverWidget(child: card),
              );
            }
            return card;
          }),
      ],
    );
  }

  void _handleEditRequest(TravelRequestModel request) {
    if (!canEditTravelRequest(request)) {
      showAppSnackBar(
        title: 'Cannot Edit',
        message: editTravelRequestBlockedMessage(request),
        backgroundColor: Colors.orange,
      );
      return;
    }

    AppNavigation.to(
      AppRoutes.userCreateRequest,
      arguments: {'edit': true, 'request': request},
    );
  }

  void _handleCreateRequest() {
    final active = _controller.activeTrip.value;
    if (blocksNewTravelRequest(active)) {
      showAppSnackBar(
        title: 'Trip In Progress',
        message: newTravelRequestBlockedMessage(active!),
        backgroundColor: Colors.orange,
      );
      return;
    }

    AppNavigation.to(AppRoutes.userCreateRequest);
  }

  void _handleDeleteRequest(TravelRequestModel request) {
    if (!canDeleteTravelRequest(request)) {
      final message = request.status == 'Completed'
          ? 'Cannot delete completed request'
          : 'Cannot delete — trip has already started';
      showAppSnackBar(
        title: 'Cannot Delete',
        message: message,
        backgroundColor: Colors.orange,
      );
      return;
    }

    unawaited(_confirmDeleteRequest(request));
  }

  Future<void> _confirmDeleteRequest(TravelRequestModel request) async {
    final confirmed = await showAppConfirmDialog(
      title: 'Delete Request',
      message: 'Are you sure you want to delete this travel request? '
          'This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      final ok = await _controller.deleteTravelRequest(request);
      if (ok) {
        showAppSnackBar(
          title: 'Deleted',
          message: 'Travel request deleted',
          backgroundColor: Colors.green,
        );
      }
    } on NetworkFailure catch (failure) {
      showAppSnackBar(
        title: 'Error',
        message: deleteTravelRequestUserMessage(failure),
        backgroundColor: Colors.red,
      );
    }
  }

  void _handleLogout() {
    unawaited(_confirmLogout());
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showAppConfirmDialog(
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmLabel: 'Logout',
      destructive: true,
    );
    if (confirmed) {
      await _authController.signOut();
    }
  }
}

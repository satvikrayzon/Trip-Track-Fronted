import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trip_track/core/widgets/custom_appbar.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/widgets/hover_widget.dart';
import '../../../../core/widgets/fade_slide_transition.dart';

import '../../../../app/router/navigation_helper.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/app_dialog.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/app_messenger.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/utils/device_utils.dart';
import '../../../../core/utils/font_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/header_widget.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';
import '../controllers/admin_dashboard_controller.dart';
import '../widgets/admin_report_export_dialog.dart';

/// Admin Dashboard Screen - Modern Design with Header Widget
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminDashboardController _controller;
  late final AppAuthController _authController;

  @override
  void initState() {
    super.initState();
    _controller = AdminDashboardController();
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
        title: 'Admin Dashboard',
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
        animation: Listenable.merge([
          _controller.isLoading,
          _controller.totalUsers,
          _controller.totalRequests,
          _controller.pendingRequests,
          _controller.completedRequests,
          _controller.recentRequests,
          _controller.deletingRequestId,
        ]),
        builder: (context, _) {
          if (_controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(isDesktop ? 24 : 16.scp(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeSlideTransition(
                    direction: AnimationDirection.up,
                    milliseconds: 500,
                    child: _buildStatistics(context),
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
                            child: _buildRecentRequests(context),
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
                    FadeSlideTransition(
                      direction: AnimationDirection.up,
                      milliseconds: 600,
                      child: _buildQuickActions(context),
                    ),
                    SizedBox(height: 24.scp(context)),
                    FadeSlideTransition(
                      direction: AnimationDirection.up,
                      milliseconds: 700,
                      child: _buildRecentRequests(context),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.scp(context)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4B8E97),
            Color(0xFF095763),
          ],
        ),
        borderRadius: BorderRadius.circular(16.scp(context)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B8E97).withOpacity(0.3),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12.scp(context)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12.scp(context)),
            ),
            child: Icon(
              Icons.admin_panel_settings,
              color: Colors.white,
              size: 32.scp(context),
            ),
          ),
          SizedBox(width: 16.scp(context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard Overview',
                  style: FontUtilities.style(
                    fontSize: 18.scp(context),
                    fontColor: Colors.white,
                    fontWeight: FWT.bold,
                  ),
                ),
                SizedBox(height: 4.scp(context)),
                Text(
                  'Manage your travel tracking system',
                  style: FontUtilities.style(
                    fontSize: 14.scp(context),
                    fontColor: Colors.white70,
                    fontWeight: FWT.regular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    if (!isDesktop) {
      return _buildMiniStatCard(
        context,
        title: title,
        value: value,
        icon: icon,
        color: color,
        onTap: onTap,
      );
    }

    return HoverWidget(
      child: GestureDetector(
        onTap: onTap,
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
                title: 'Users',
                value: _controller.totalUsers.value.toString(),
                icon: Icons.people_outline,
                color: const Color(0xFF4CAF50),
                onTap: () => AppNavigation.to(AppRoutes.adminUserList),
              ),
            ),
            SizedBox(width: isDesktop ? 16 : 8.scp(context)),
            Expanded(
              child: _buildResponsiveStatCard(
                context,
                title: 'Requests',
                value: _controller.totalRequests.value.toString(),
                icon: Icons.assignment_outlined,
                color: const Color(0xFF2196F3),
                onTap: () => AppNavigation.to(AppRoutes.adminTravelRequests),
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
                onTap: () => AppNavigation.to(AppRoutes.adminTravelRequests),
              ),
            ),
            SizedBox(width: isDesktop ? 16 : 8.scp(context)),
            Expanded(
              child: _buildResponsiveStatCard(
                context,
                title: 'Done',
                value: _controller.completedRequests.value.toString(),
                icon: Icons.check_circle_outline,
                color: const Color(0xFF9C27B0),
                onTap: () => AppNavigation.to(AppRoutes.adminTravelRequests),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String trend,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12.scp(context)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.scp(context)),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(8.scp(context)),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.scp(context)),
                  ),
                  child: Icon(icon, color: color, size: 20.scp(context)),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 8.scp(context), vertical: 4.scp(context)),
                  decoration: BoxDecoration(
                    color: trend.startsWith('+')
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : const Color(0xFFFF5722).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.scp(context)),
                  ),
                  child: Text(
                    trend,
                    style: FontUtilities.style(
                      fontSize: 11.scp(context),
                      fontColor: trend.startsWith('+')
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFF5722),
                      fontWeight: FWT.semiBold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.scp(context)),
            Text(
              value,
              style: FontUtilities.style(
                fontSize: 24.scp(context),
                fontColor: color,
                fontWeight: FWT.bold,
              ),
            ),
            SizedBox(height: 4.scp(context)),
            Text(
              title,
              style: FontUtilities.style(
                fontSize: 12.scp(context),
                fontColor: const Color(0xFF718096),
                fontWeight: FWT.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final isDesktop = !AdaptiveLayout.isCompact(context);

    final actions = [
      if (_authController.isAdmin)
        _buildActionButton(
          context,
          title: 'Create User',
          icon: Icons.person_add,
          color: const Color(0xFF4B8E97),
          onTap: () => AppNavigation.to(AppRoutes.adminCreateUser),
        ),
      _buildActionButton(
        context,
        title: 'Manage Users',
        icon: Icons.manage_accounts,
        color: const Color(0xFF2196F3),
        onTap: () => AppNavigation.to(AppRoutes.adminUserList),
      ),
      _buildActionButton(
        context,
        title: 'View Requests',
        icon: Icons.list_alt,
        color: const Color(0xFF9C27B0),
        onTap: () => AppNavigation.to(AppRoutes.adminTravelRequests),
      ),
      _buildActionButton(
        context,
        title: 'Export Report',
        icon: Icons.download_rounded,
        color: const Color(0xFF4CAF50),
        onTap: () => AdminReportExportDialog.show(context),
      ),
      _buildActionButton(
        context,
        title: 'Fuel Rates',
        icon: Icons.local_gas_station_outlined,
        color: const Color(0xFFFF5722),
        onTap: () => AppNavigation.to(AppRoutes.adminFuelRates),
      ),
      _buildActionButton(
        context,
        title: 'Settings',
        icon: Icons.settings,
        color: const Color(0xFF757575),
        onTap: () => AppNavigation.to(AppRoutes.settings),
      ),
      _buildActionButton(
        context,
        title: 'Live Map',
        icon: Icons.map_rounded,
        color: const Color(0xFF095763),
        onTap: () => AppNavigator.push(AppPaths.liveMap, context: context),
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
              Row(
                children: [
                  if (_authController.isAdmin) ...[
                    Expanded(child: actions[0]),
                    SizedBox(width: 12.scp(context)),
                    Expanded(child: actions[1]),
                  ] else
                    Expanded(child: actions[0]),
                ],
              ),
              SizedBox(height: 12.scp(context)),
              Row(
                children: [
                  Expanded(child: actions[_authController.isAdmin ? 2 : 1]),
                  SizedBox(width: 12.scp(context)),
                  Expanded(child: actions[_authController.isAdmin ? 3 : 2]),
                ],
              ),
              SizedBox(height: 12.scp(context)),
              Row(
                children: [
                  Expanded(child: actions[_authController.isAdmin ? 4 : 3]),
                  SizedBox(width: 12.scp(context)),
                  Expanded(child: actions[_authController.isAdmin ? 5 : 4]),
                ],
              ),
              SizedBox(height: 12.scp(context)),
              Row(
                children: [
                  Expanded(child: actions[_authController.isAdmin ? 6 : 5]),
                ],
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
              onPressed: () => AppNavigation.to(AppRoutes.adminTravelRequests),
              child: Text(
                'View All',
                style: FontUtilities.style(
                  fontSize: 14.scp(context),
                  fontColor: const Color(0xFF4B8E97),
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
              name: request.displayUserName,
              employeeCode: request.employeeCode,
              showDeleteButton: canDeleteTravelRequest(request, asAdmin: true),
              isDeleteLoading: isDeleting,
              clientName: request.clientName.isNotEmpty
                  ? request.clientName
                  : request.displayUserName,
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
              isAdmin: true,
              onTap: () => AppNavigation.to(
                AppRoutes.userRequestDetails,
                arguments: request,
              ),
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

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Morning';
    } else if (hour < 17) {
      return 'Afternoon';
    } else {
      return 'Evening';
    }
  }

  void _handleDeleteRequest(TravelRequestModel request) {
    unawaited(_confirmDeleteRequest(request));
  }

  Future<void> _confirmDeleteRequest(TravelRequestModel request) async {
    final confirmed = await showAppConfirmDialog(
      title: 'Delete Request',
      message:
          'Are you sure you want to delete this travel request? This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      final ok = await _controller.deleteRequest(request);
      if (ok) {
        showAppSnackBar(
          title: 'Deleted',
          message: 'Travel request deleted',
          backgroundColor: Colors.green,
        );
        unawaited(_controller.refresh());
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

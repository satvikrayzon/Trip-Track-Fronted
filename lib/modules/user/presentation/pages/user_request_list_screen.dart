import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/app_dialog.dart';
import '../../../../core/app_messenger.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/device_utils.dart';
import '../../../../core/utils/font_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/custom_appbar.dart';
import '../../../../core/widgets/header_widget.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';
import '../../../travel/utils/travel_request_edit_utils.dart';
import '../../../../core/services/active_trip_restore_service.dart';
import '../../../../core/di/service_locator.dart';
import '../../../travel/data/datasources/travel_request_remote_datasource.dart';
import '../controllers/user_requests_controller.dart';

/// User Request List Screen
class UserRequestListScreen extends StatefulWidget {
  const UserRequestListScreen({super.key});

  @override
  State<UserRequestListScreen> createState() => _UserRequestListScreenState();
}

class _UserRequestListScreenState extends State<UserRequestListScreen> {
  late final UserRequestsController _controller;
  late final ScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchText = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _controller = UserRequestsController();
    _controller.start();
    _scrollController = ScrollController()..addListener(_onScroll);
    _searchController.addListener(() {
      _searchText.value = _searchController.text;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      unawaited(_controller.loadMore());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchText.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HeaderWidget(
      headerChild: CustomAppBar(
        title: 'My Requests',
        showBackButton: true,
        action: [
          GestureDetector(
            onTap: () => _handleCreateRequest(),
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
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 16.scp(context),
                  ),
                  SizedBox(width: 6.scp(context)),
                  Text(
                    'New Request',
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
      child: Column(
        children: [
          // Search and filter bar
          Container(
            padding: EdgeInsets.all(16.scp(context)),
            child: Column(
              children: [
                // Search field
                ValueListenableBuilder<String>(
                  valueListenable: _searchText,
                  builder: (context, searchText, _) {
                    return TextField(
                      controller: _searchController,
                      style: FontUtilities.style(
                        fontSize: 14.scp(context),
                        fontColor: const Color(0xFF1F2937),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by client or location...',
                        hintStyle: FontUtilities.style(
                          fontSize: 14.scp(context),
                          fontColor: const Color(0xFF9CA3AF),
                          fontWeight: FWT.regular,
                        ),
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xFF6B7280)),
                        suffixIcon: searchText.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: Color(0xFF6B7280)),
                                onPressed: () {
                                  _searchController.clear();
                                  _controller.searchRequests('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.scp(context),
                            vertical: 12.scp(context)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.scp(context)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: _controller.searchRequests,
                    );
                  },
                ),

                SizedBox(height: 12.scp(context)),

                // Status filter chips
                ValueListenableBuilder<String>(
                  valueListenable: _controller.filterStatus,
                  builder: (context, _, __) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All', 'all', context),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Ready', 'Ready To Start', context),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Travelling', 'Travelling', context),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Meeting', 'In Meeting', context),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Return', 'Returning', context),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Completed', 'Completed', context),
                        ],
                      ),
                    )),
              ],
            ),
          ),

          // Request count
          ValueListenableBuilder<List<TravelRequestModel>>(
            valueListenable: _controller.requests,
            builder: (context, requests, _) => Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 16.scp(context), vertical: 12.scp(context)),
                color: const Color(0xFFF9FAFB),
                child: Row(
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 18.scp(context), color: const Color(0xFF6B7280)),
                    SizedBox(width: 8.scp(context)),
                    Text(
                      '${requests.length} ${requests.length == 1 ? 'request' : 'requests'} found',
                      style: FontUtilities.style(
                        fontSize: 13.scp(context),
                        fontColor: const Color(0xFF6B7280),
                        fontWeight: FWT.medium,
                      ),
                    ),
                  ],
                ),
              )),

          // Requests list
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _controller.isLoading,
                _controller.requests,
                _controller.hasMore,
                _controller.deletingRequestId,
              ]),
              builder: (context, _) {
              if (_controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final requests = _controller.requests.value;
              if (requests.isEmpty) {
                return ValueListenableBuilder<String>(
                  valueListenable: _searchText,
                  builder: (context, searchText, _) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 64.scp(context),
                            color: const Color(0xFF9CA3AF),
                          ),
                          SizedBox(height: 16.scp(context)),
                          Text(
                            'No requests found',
                            style: FontUtilities.style(
                              fontSize: 18.scp(context),
                              fontColor: const Color(0xFF4B5563),
                              fontWeight: FWT.semiBold,
                            ),
                          ),
                          SizedBox(height: 8.scp(context)),
                          Text(
                            searchText.isNotEmpty
                                ? 'Try adjusting your search'
                                : 'Create your first travel request',
                            style: FontUtilities.style(
                              fontSize: 14.scp(context),
                              fontColor: const Color(0xFF9CA3AF),
                              fontWeight: FWT.regular,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }

              return RefreshIndicator(
                onRefresh: _controller.refresh,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(16.scp(context)),
                  itemCount: requests.length +
                      (_controller.hasMore.value ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= requests.length) {
                      return Padding(
                        padding: EdgeInsets.all(16.scp(context)),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final request = requests[index];
                    final isDeleting = _controller.deletingRequestId.value ==
                        request.restResourceId;
                    return TravelRequestCard(
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
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, BuildContext context) {
    final isSelected = _controller.filterStatus.value == value;

    return GestureDetector(
      onTap: () => _controller.filterByStatus(value),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 16.scp(context), vertical: 8.scp(context)),
        decoration: BoxDecoration(
          color: isSelected ? _getStatusColor(value) : Colors.white,
          borderRadius: BorderRadius.circular(20.scp(context)),
          border: Border.all(
            color:
                isSelected ? _getStatusColor(value) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: FontUtilities.style(
            fontSize: 13.scp(context),
            fontColor: isSelected ? Colors.white : const Color(0xFF6B7280),
            fontWeight: isSelected ? FWT.semiBold : FWT.medium,
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Ready To Start':
      case 'Start Missing':
        return AppColors.warning;
      case 'Travelling':
      case 'Returning':
      case 'End Missing':
        return AppColors.info;
      case 'In Meeting':
      case 'At Client':
      case 'Ready For Next':
      case 'Ready To Return':
        return AppColors.primary;
      case 'Completed':
        return AppColors.success;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _handleCreateRequest() async {
    final restore = ActiveTripRestoreService(
      ServiceLocator.I.get<TravelRequestRemoteDataSource>(),
    );
    final active = await restore.resolveActiveTrip();
    if (!mounted) return;
    if (blocksNewTravelRequest(active)) {
      showAppSnackBar(
        title: 'Trip In Progress',
        message: newTravelRequestBlockedMessage(active!),
        backgroundColor: AppColors.warning,
      );
      return;
    }
    AppNavigation.to(AppRoutes.userCreateRequest);
  }

  void _handleEditRequest(TravelRequestModel request) {
    if (!canEditTravelRequest(request)) {
      showAppSnackBar(
        title: 'Cannot Edit',
        message: editTravelRequestBlockedMessage(request),
        backgroundColor: AppColors.warning,
      );
      return;
    }

    unawaited(
      AppNavigation.to(
        AppRoutes.userCreateRequest,
        arguments: {'edit': true, 'request': request},
      ).then((_) => _controller.refresh()),
    );
  }

  void _handleDeleteRequest(TravelRequestModel request) {
    if (!canDeleteTravelRequest(request)) {
      final message = request.status == 'Completed'
          ? 'Cannot delete completed request'
          : 'Cannot delete — trip has already started';
      showAppSnackBar(
        title: 'Cannot Delete',
        message: message,
        backgroundColor: AppColors.warning,
      );
      return;
    }
    unawaited(_confirmDeleteRequest(request));
  }

  Future<void> _confirmDeleteRequest(TravelRequestModel request) async {
    final confirmed = await showAppConfirmDialog(
      title: 'Delete Request',
      message:
          'Are you sure you want to delete this travel request? '
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
          backgroundColor: AppColors.success,
        );
      }
    } on NetworkFailure catch (failure) {
      showAppSnackBar(
        title: 'Error',
        message: deleteTravelRequestUserMessage(failure),
        backgroundColor: AppColors.error,
      );
    }
  }
}

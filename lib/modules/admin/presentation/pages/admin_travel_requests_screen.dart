import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/app_dialog.dart';
import '../../../../core/app_messenger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/modern_app_bar.dart';
import '../../../../core/di/service_locator.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/utils/travel_request_delete_utils.dart';
import '../../services/admin_report_service.dart';
import '../widgets/admin_requests_filter_sheet.dart';
import '../controllers/admin_travel_requests_controller.dart';

/// Admin Travel Requests Screen
class AdminTravelRequestsScreen extends StatefulWidget {
  const AdminTravelRequestsScreen({super.key});

  @override
  State<AdminTravelRequestsScreen> createState() =>
      _AdminTravelRequestsScreenState();
}

class _AdminTravelRequestsScreenState extends State<AdminTravelRequestsScreen> {
  late final AdminTravelRequestsController _controller;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = AdminTravelRequestsController();
    _controller.start();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ModernAppBar(
        title: 'Travel Requests',
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Advanced Filters',
            onPressed: _showFiltersSheet,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Filtered Requests to Excel',
            onPressed: _exportCurrentList,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter bar
          Container(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            color: AppColors.surface,
            child: Column(
              children: [
                // Search field
                TextField(
                  controller: _searchController,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by name or location...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _controller.searchRequests('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.buttonRadius),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) => _controller.searchRequests(value),
                ),

                const SizedBox(height: 12),

                // Status filter chips
                ValueListenableBuilder<String>(
                  valueListenable: _controller.filterStatus,
                  builder: (context, _, __) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All', 'all'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Ready', 'Ready To Start'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Travelling', 'Travelling'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Meeting', 'In Meeting'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Return', 'Returning'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Completed', 'Completed'),
                        ],
                      ),
                    )),
              ],
            ),
          ),

          // Requests list
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _controller.isLoading,
                _controller.requests,
                _controller.deletingRequestId,
              ]),
              builder: (context, _) {
              if (_controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final requests = _controller.requests.value;
              if (requests.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 64,
                        color: AppColors.textSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No requests found',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchController.text.isNotEmpty
                            ? 'Try adjusting your search'
                            : 'Users haven\'t created any travel requests yet',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _controller.refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    final isDeleting = _controller.deletingRequestId.value ==
                        request.restResourceId;
                    return TravelRequestCard(
                        name: request.displayUserName,
                        employeeCode: request.employeeCode,
                        isAdmin: true,
                        showDeleteButton: canDeleteTravelRequest(request),
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
                        onTap: () => AppNavigation.to(
                            AppRoutes.userRequestDetails,
                            arguments: request),
                        onDelete: () => _handleDeleteRequest(request));
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _controller.filterStatus.value == value;
    final color = _getStatusColor(value);

    return GestureDetector(
      onTap: () => _controller.filterByStatus(value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? Colors.white : const Color(0xFF6B7280),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'all':
        return AppColors.textPrimary;
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

  void _showFiltersSheet() {
    AdminRequestsFilterSheet.show(context, _controller);
  }

  void _exportCurrentList() async {
    final requests = _controller.requests.value;
    if (requests.isEmpty) {
      showAppSnackBar(
        title: 'Empty List',
        message: 'There are no requests to export based on current filters.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    try {
      showAppSnackBar(
        title: 'Exporting...',
        message: 'Generating Excel file...',
        backgroundColor: AppColors.info,
      );
      final service = AdminReportService(travelApi: ServiceLocator.I.get());
      await service.generateExcelFile(requests);
      if (mounted) {
        showAppSnackBar(
          title: 'Success',
          message: 'Report downloaded successfully.',
          backgroundColor: AppColors.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          title: 'Error',
          message: 'Failed to export report: $e',
          backgroundColor: AppColors.error,
        );
      }
    }
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
          'Are you sure you want to delete this travel request? This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await _controller.deleteRequest(request);
    } on NetworkFailure catch (failure) {
      showAppSnackBar(
        title: 'Error',
        message: deleteTravelRequestUserMessage(failure),
        backgroundColor: AppColors.error,
      );
    }
  }
}

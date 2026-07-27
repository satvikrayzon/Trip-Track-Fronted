import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/address_utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// Custom card widget with various styles and animations
enum AppCardType { defaultCard, elevatedCard, outlinedCard, glassCard }

class AppCard extends StatefulWidget {
  final Widget child;
  final AppCardType type;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final double? elevation;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final bool showShimmer;
  final Duration animationDuration;

  const AppCard({
    super.key,
    required this.child,
    this.type = AppCardType.defaultCard,
    this.padding,
    this.margin,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.showShimmer = false,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(duration: widget.animationDuration, vsync: this);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _animationController.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _animationController.reverse();
  }

  BoxDecoration _getDecoration() {
    switch (widget.type) {
      case AppCardType.defaultCard:
        return BoxDecoration(
            color: widget.backgroundColor ?? AppColors.white,
            borderRadius: widget.borderRadius ??
                BorderRadius.circular(AppConstants.cardRadius),
            boxShadow: AppShadows.cardShadow);
      case AppCardType.elevatedCard:
        return BoxDecoration(
            color: widget.backgroundColor ?? AppColors.white,
            borderRadius: widget.borderRadius ??
                BorderRadius.circular(AppConstants.cardRadius),
            boxShadow: AppShadows.cardShadowHover);
      case AppCardType.outlinedCard:
        return BoxDecoration(
            color: widget.backgroundColor ?? AppColors.white,
            borderRadius: widget.borderRadius ??
                BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: AppColors.greyLight, width: 1));
      case AppCardType.glassCard:
        return BoxDecoration(
            color: (widget.backgroundColor ?? AppColors.white).withOpacity(0.9),
            borderRadius: widget.borderRadius ??
                BorderRadius.circular(AppConstants.cardRadius),
            border:
                Border.all(color: AppColors.white.withOpacity(0.3), width: 1),
            boxShadow: AppShadows.glassShadow);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
        margin: widget.margin,
        padding:
            widget.padding ?? const EdgeInsets.all(AppConstants.defaultPadding),
        decoration: _getDecoration(),
        child: widget.child);
    if (widget.onTap != null) {
      card = GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          child: ScaleTransition(scale: _scaleAnimation, child: card));
    }
    return card;
  }
}

/// Specialized Travel Request Card - Clean Minimal Design
class TravelRequestCard extends StatelessWidget {
  final String name;
  final String? employeeCode;
  final String clientName;
  final String fromLocation;
  final String toLocation;
  final String? legsSummary;
  final String? metricsSummary;
  final double? travelAllowance;
  final String? fuelType;
  final bool showClientName;
  final String vehicleType;
  final String status;
  final DateTime dateTime;
  final bool isSynced;
  final String? startImageUrl;
  final String? endImageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showEditButton;
  final bool showDeleteButton;
  final bool isAdmin;
  final bool isDeleteLoading;

  const TravelRequestCard(
      {super.key,
      required this.name,
      this.employeeCode,
      this.clientName = '',
      required this.fromLocation,
      required this.toLocation,
      this.legsSummary,
      this.metricsSummary,
      this.travelAllowance,
      this.fuelType,
      this.showClientName = true,
      required this.vehicleType,
      required this.status,
      required this.dateTime,
      this.isSynced = true,
      this.startImageUrl,
      this.endImageUrl,
      this.onTap,
      this.onEdit,
      this.onDelete,
      this.showEditButton = false,
      this.showDeleteButton = false,
      this.isAdmin = false,
      this.isDeleteLoading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.06),
              offset: const Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row - name, status, and action buttons
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isAdmin &&
                          employeeCode != null &&
                          employeeCode!.trim().isNotEmpty &&
                          name.trim().toLowerCase() !=
                              employeeCode!.trim().toLowerCase()) ...[
                        const SizedBox(height: 2),
                        Text(
                          employeeCode!.trim(),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (travelAllowance != null) ...[
                  const SizedBox(width: 8),
                  _buildAllowanceChip(travelAllowance!),
                ],
                const SizedBox(width: 8),
                _buildStatusBadge(),
              ],
            ),

            const SizedBox(height: 12),

            if (legsSummary != null && legsSummary!.trim().isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.route_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      legsSummary!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (metricsSummary != null && metricsSummary!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: metricsSummary!.split(' · ').map((metric) {
                    IconData icon = Icons.info_outline;
                    String label = metric;
                    if (metric.contains('km')) {
                      icon = Icons.route_outlined;
                    } else if (metric.contains('travel')) {
                      icon = Icons.timer_outlined;
                      label = label.replaceFirst(' travel', '');
                    } else if (metric.contains('meeting time')) {
                      icon = Icons.access_time;
                      label = label.replaceFirst(' meeting time', '');
                    } else if (metric.contains('meeting')) {
                      icon = Icons.groups_outlined;
                    } else if (metric.contains('allowance') || metric.contains('₹')) {
                      icon = Icons.account_balance_wallet_outlined;
                    }
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.greyLight,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.grey.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.trip_origin,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(AddressUtils.shortAddress(fromLocation),
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                child: Container(
                  width: 2,
                  height: 16,
                  decoration: BoxDecoration(
                      color: AppColors.greyLight,
                      borderRadius: BorderRadius.circular(1)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AddressUtils.shortAddress(toLocation),
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Bottom row - client, vehicle, date
            Row(
              children: [
                if (showClientName && clientName.trim().isNotEmpty) ...[
                  const Icon(Icons.business_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      clientName,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Icon(
                  _vehicleIcon(vehicleType),
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  AppConstants.vehicleTypeLabel(vehicleType),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (fuelType != null && fuelType!.trim().isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.local_gas_station_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppConstants.fuelTypeLabel(fuelType),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const Spacer(),
                const Icon(Icons.calendar_today,
                    size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),

            // Meter images row (if any images are uploaded)
            if (startImageUrl != null || endImageUrl != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.greyLight),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.camera_alt,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  const Text(
                    'Meter Readings:',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  if (startImageUrl != null) ...[
                    _buildImageThumbnail(startImageUrl!, 'Start', context),
                    const SizedBox(width: 8),
                  ],
                  if (endImageUrl != null) ...[
                    _buildImageThumbnail(endImageUrl!, 'End', context),
                  ],
                ],
              ),
            ],

            if (_shouldShowActionButtons()) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.greyLight),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [_buildActionButtons()],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _vehicleIcon(String type) {
    switch (type.toLowerCase()) {
      case AppConstants.vehicleTypeCar:
        return Icons.directions_car;
      case AppConstants.vehicleTypeScooter:
        return Icons.electric_scooter;
      case AppConstants.vehicleTypeBike:
      default:
        return Icons.motorcycle;
    }
  }

  Color _getStatusColor() {
    switch (status) {
      case 'Ready To Start':
      case 'Start Missing':
        return AppColors.warning;
      case 'Travelling':
      case 'Returning':
      case 'End Missing':
        return AppColors.info;
      case 'At Client':
      case 'In Meeting':
      case 'Ready For Next':
      case 'Ready To Return':
        return AppColors.primary;
      case 'Completed':
        return AppColors.success;
      default:
        return AppColors.grey;
    }
  }

  Widget _buildAllowanceChip(double amount) {
    final amountText = amount == amount.roundToDouble()
        ? '₹${amount.toStringAsFixed(0)}'
        : '₹${amount.toStringAsFixed(2)}';
    final fuelLabel = AppConstants.fuelTypeLabel(fuelType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            size: 14,
            color: AppColors.success,
          ),
          const SizedBox(width: 4),
          Text(
            amountText,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
          if (fuelLabel.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              '• $fuelLabel',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.success.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.white,
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(String imageUrl, String label, BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullScreenImage(context, imageUrl, label),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: label == 'Start' ? AppColors.success : AppColors.error,
              width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: AppColors.greyLight,
                  child: const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.greyLight,
                  child: const Icon(
                    Icons.image,
                    color: AppColors.grey,
                    size: 20,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Tap indicator overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.zoom_in,
                      color: AppColors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(
    BuildContext context,
    String imageUrl,
    String label,
  ) {
    showDialog(
      context: context,
      barrierColor: AppColors.black.withOpacity(0.9),
      builder: (context) => _FullScreenImageViewer(
        imageUrl: imageUrl,
        label: label,
      ),
    );
  }

  String _formatDateTime() {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  bool _shouldShowActionButtons() {
    return showEditButton || showDeleteButton || _canEdit() || _canDelete();
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        if (_canEdit())
          TextButton.icon(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit', style: TextStyle(fontSize: 13)),
          ),
        if (_canDelete())
          TextButton.icon(
            onPressed: isDeleteLoading ? null : onDelete,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: isDeleteLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.error,
                    ),
                  )
                : const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete', style: TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  bool _canEdit() {
    // Can edit if explicitly enabled
    if (showEditButton) return true;

    // Admin cannot edit (only delete)
    if (isAdmin) return false;

    // Status flow: "Start Missing" → "End Missing" → "Completed"
    // User can edit only if status is "Start Missing" (no photos uploaded yet)
    // Once start photo is uploaded (status becomes "End Missing"), cannot edit
    if (status == 'Start Missing')
      return false; // Users should explicitly enable edit
    if (status == 'End Missing')
      return false; // Cannot edit after start photo uploaded
    if (status == 'Completed') return false; // Cannot edit completed requests

    return false; // Only show edit if explicitly enabled
  }

  bool _canDelete() {
    // Can delete if explicitly enabled
    if (showDeleteButton) return true;

    // Status flow: "Start Missing" → "End Missing" → "Completed"
    // Admin can only delete if status is "Start Missing" (no photos uploaded yet)
    // Admin cannot delete if status is "End Missing" (start photo uploaded) or "Completed"
    if (isAdmin) {
      if (status == 'Start Missing' || status == 'Ready To Start') {
        return true;
      }
      if (status == 'End Missing') return false;
      if (status == 'Completed') return false;
      return false;
    }

    // User can delete their own requests only if status is "Start Missing"
    // (no photos uploaded yet)
    if (status == 'Start Missing')
      return false; // Users should explicitly enable delete
    if (status == 'End Missing') return false;
    if (status == 'Completed') return false;

    return false; // Only show delete if explicitly enabled
  }
}

/// Full-screen interactive image viewer with zoom capability
class _FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String label;

  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.label,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      // Reset zoom
      _transformationController.value = Matrix4.identity();
    } else {
      // Zoom in to 2x at tap position
      final position = _doubleTapDetails!.localPosition;
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx, -position.dy)
        ..scale(2.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Interactive image viewer
          Center(
            child: GestureDetector(
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    color: Colors.transparent,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.transparent,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppColors.white,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top bar with label and close button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.label == 'Start'
                            ? AppColors.success
                            : AppColors.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${widget.label} Meter Reading',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom hint
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, color: AppColors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Pinch to zoom • Double tap to zoom in/out',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

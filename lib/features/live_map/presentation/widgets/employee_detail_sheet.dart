import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/address_utils.dart';
import '../../../tracking/domain/entities/employee_tracking_status.dart';

class EmployeeDetailSheet extends StatelessWidget {
  const EmployeeDetailSheet({
    super.key,
    required this.employee,
    required this.onClose,
    required this.onFocus,
  });

  final TrackedEmployee employee;
  final VoidCallback onClose;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat('h:mm a');
    final displayName = employee.displayName;

    final roleAndTeam = [
      if (employee.role != null && employee.role!.trim().isNotEmpty)
        employee.role!.trim(),
      if (employee.team != null && employee.team!.trim().isNotEmpty)
        employee.team!.trim(),
    ].join(' · ');

    final statusColor = Color(employee.status.colorValue);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top header: Avatar and names
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              PulsingStatusDot(color: statusColor),
                              const SizedBox(width: 6),
                              Text(
                                employee.status.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                              if (roleAndTeam.isNotEmpty) ...[
                                Text(
                                  '  |  $roleAndTeam',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AppColors.greyLight.withValues(alpha: 0.2),
                        padding: const EdgeInsets.all(6),
                      ),
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Location Details section (replaces old From -> To routes)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.surfaceVariant.withValues(alpha: 0.4),
                    border: Border.all(
                        color: AppColors.greyLight.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LIVE LOCATION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            EmployeeAddressText(
                              latitude: employee.position.latitude,
                              longitude: employee.position.longitude,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Wrap status indicators (Last update)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon: Icons.access_time_rounded,
                      label: 'Updated ${timeFmt.format(employee.lastUpdated)}',
                    ),
                  ],
                ),

                // Contact hints card
                if (employee.hasProfileHints) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.greyLight.withValues(alpha: 0.3),
                      ),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (employee.tripFrom != null &&
                            employee.tripFrom!.isNotEmpty &&
                            employee.tripTo != null &&
                            employee.tripTo!.isNotEmpty) ...[
                          _ContactDetailRow(
                            icon: Icons.route_outlined,
                            label: 'Route',
                            value: '${employee.tripFrom} → ${employee.tripTo}',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Divider(height: 1, thickness: 0.5),
                          ),
                        ],
                        if (employee.employeeCode != null &&
                            employee.employeeCode!.isNotEmpty)
                          _ContactDetailRow(
                            icon: Icons.badge_outlined,
                            label: 'Employee Code',
                            value: employee.employeeCode!,
                          ),
                        if (employee.mobile != null &&
                            employee.mobile!.isNotEmpty) ...[
                          if (employee.employeeCode != null &&
                              employee.employeeCode!.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Divider(height: 1, thickness: 0.5),
                            ),
                          _ContactDetailRow(
                            icon: Icons.phone_android_rounded,
                            label: 'Mobile',
                            value: employee.mobile!,
                          ),
                        ],
                        if (employee.email != null &&
                            employee.email!.isNotEmpty) ...[
                          if ((employee.employeeCode != null &&
                                  employee.employeeCode!.isNotEmpty) ||
                              (employee.mobile != null &&
                                  employee.mobile!.isNotEmpty))
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Divider(height: 1, thickness: 0.5),
                            ),
                          _ContactDetailRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: employee.email!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: onFocus,
                    icon: const Icon(Icons.my_location_rounded, size: 20),
                    label: const Text(
                      'Focus on map',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surfaceVariant.withValues(alpha: 0.6),
        border: Border.all(color: AppColors.greyLight.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor ?? AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactDetailRow extends StatelessWidget {
  const _ContactDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(4),
          ),
          icon: const Icon(Icons.copy_all_rounded,
              size: 16, color: AppColors.textSecondary),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied $label to clipboard'),
                duration: const Duration(milliseconds: 1500),
                behavior: SnackBarBehavior.floating,
                width: 250,
              ),
            );
          },
        ),
      ],
    );
  }
}

class PulsingStatusDot extends StatefulWidget {
  final Color color;

  const PulsingStatusDot({super.key, required this.color});

  @override
  State<PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 1.0 - _animation.value),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ],
        );
      },
    );
  }
}

class EmployeeAddressText extends StatefulWidget {
  final double latitude;
  final double longitude;

  const EmployeeAddressText({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<EmployeeAddressText> createState() => _EmployeeAddressTextState();
}

class _EmployeeAddressTextState extends State<EmployeeAddressText> {
  String? _address;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void didUpdateWidget(EmployeeAddressText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _resolveAddress();
    }
  }

  Future<void> _resolveAddress() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _address = null;
    });

    try {
      final addr = await AddressUtils.reverseGeocode(
        widget.latitude,
        widget.longitude,
      );
      if (mounted) {
        setState(() {
          _address = addr;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _address =
              '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Resolving live address...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      _address ?? 'Location coordinates resolved',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../modules/travel/data/models/tracking_coverage_model.dart';
import 'app_card.dart';

/// Shows GPS tracking coverage (tracked vs missing time) for a trip leg.
class TripTrackingCoverageCard extends StatelessWidget {
  const TripTrackingCoverageCard({
    super.key,
    required this.coverage,
    this.isLoading = false,
  });

  final TrackingCoverageResult? coverage;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const AppCard(
        type: AppCardType.outlinedCard,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final data = coverage;
    if (data == null || data.legs.isEmpty) {
      return const SizedBox.shrink();
    }

    final summary = data.summary;
    final sourceLabel = switch (data.source) {
      CoverageSource.remote => 'Server report',
      CoverageSource.cached => 'Cached report',
      CoverageSource.local => 'On-device estimate',
    };

    return AppCard(
      type: AppCardType.outlinedCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'GPS Tracking Coverage',
                style: AppTextStyles.titleSmall.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                sourceLabel,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(summary),
          const SizedBox(height: 12),
          ...data.legs.map(_buildLegSection),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(TrackingCoverageSummary summary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _metricTile(
              'Trip window',
              '${summary.expectedDurationMinutes} min',
              Icons.schedule,
            ),
          ),
          Expanded(
            child: _metricTile(
              'Tracked',
              '${summary.trackedDurationMinutes} min',
              Icons.gps_fixed,
              color: AppColors.success,
            ),
          ),
          Expanded(
            child: _metricTile(
              'Missing',
              '${summary.gapDurationMinutes} min',
              Icons.gps_off,
              color: summary.gapDurationMinutes > 0
                  ? AppColors.warning
                  : AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: _metricTile(
              'Coverage',
              '${summary.coveragePercent.toStringAsFixed(0)}%',
              Icons.pie_chart_outline,
              color: _coverageColor(summary.coveragePercent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color ?? AppColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLegSection(TrackingCoverageLegModel leg) {
    final fmt = DateFormat('dd MMM, hh:mm a');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Leg ${leg.legNumber}: ${leg.fromLocation} → ${leg.toLocation}',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (leg.departureAt != null && leg.arrivalAt != null)
            Text(
              '${fmt.format(leg.departureAt!.toLocal())} – '
              '${fmt.format(leg.arrivalAt!.toLocal())}',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          Text(
            '${leg.coveragePercent.toStringAsFixed(0)}% covered · '
            '${leg.pointCount} GPS points · '
            '${leg.gapDurationMinutes} min missing',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (leg.gaps.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...leg.gaps.take(5).map((gap) => _gapRow(gap, fmt)),
            if (leg.gaps.length > 5)
              Text(
                '+ ${leg.gaps.length - 5} more gap(s)',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _gapRow(TrackingGapModel gap, DateFormat fmt) {
    final cause = gap.suspectedCause?.replaceAll('_', ' ') ?? 'no GPS data';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.warning.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${gap.durationMinutes} min gap · '
              '${fmt.format(gap.from.toLocal())} – ${fmt.format(gap.to.toLocal())}'
              '${gap.suspectedCause != null ? ' · $cause' : ''}',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _coverageColor(double percent) {
    if (percent >= 90) return AppColors.success;
    if (percent >= 70) return AppColors.warning;
    return AppColors.error;
  }
}

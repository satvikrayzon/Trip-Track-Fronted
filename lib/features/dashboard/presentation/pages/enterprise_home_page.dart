import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../modules/travel/data/models/travel_request_model.dart';
import '../../../../shared/widgets/glass_card.dart';
import '../../../../shared/widgets/shimmer_skeleton.dart';
import '../providers/dashboard_provider.dart';

/// Premium employee home dashboard — Uber/Swiggy inspired.
class EnterpriseHomePage extends ConsumerWidget {
  const EnterpriseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final auth = ref.watch(authControllerProvider);
    final sync = ref.watch(syncStatusProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: _Header(
                    name: auth.currentUserData?.name ?? 'Employee',
                    onProfile: () => context.push(AppPaths.profile),
                    onLogout: () async {
                      await auth.signOut();
                      if (context.mounted) context.go(AppPaths.login);
                    },
                  ),
                ),
              ),
              sync.when(
                data: (s) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SyncBanner(status: s),
                  ),
                ),
                loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
              if (dashboard.isLoading && dashboard.recentTrips.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: DashboardSkeleton(),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (dashboard.activeTrip != null)
                          _ActiveTripCard(
                            trip: dashboard.activeTrip!,
                            isTracking: dashboard.isTrackingActive,
                            onTap: () => context.push(
                              AppPaths.trip(dashboard.activeTrip!.restResourceId),
                            ),
                          ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.05),
                        if (dashboard.activeTrip != null)
                          const SizedBox(height: 20),
                        _TodayStatsGrid(
                          distanceKm: dashboard.todayDistanceKm,
                          meetingMinutes: dashboard.meetingMinutesToday,
                          pending: dashboard.pendingTrips,
                          completed: dashboard.completedTrips,
                          isTracking: dashboard.isTrackingActive,
                        ).animate().fadeIn(delay: 80.ms, duration: 280.ms),
                        const SizedBox(height: 24),
                        Text(
                          'Quick Actions',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _QuickActions(
                          onCreateTrip: () => context.push(AppPaths.createTrip),
                          onViewTrips: () => context.push(AppPaths.tripList),
                          onReturnTrip: dashboard.activeTrip != null
                              ? () => context.push(
                                    AppPaths.trip(
                                      dashboard.activeTrip!.restResourceId,
                                    ),
                                  )
                              : null,
                          onAnalytics: () => context.push(AppPaths.tripList),
                        ).animate().fadeIn(delay: 120.ms, duration: 280.ms),
                        const SizedBox(height: 24),
                        Text(
                          'Recent Trips',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final trip = dashboard.recentTrips[index];
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          index == dashboard.recentTrips.length - 1 ? 24 : 10,
                        ),
                        child: _RecentTripTile(
                          trip: trip,
                          onTap: () => context.push(
                            AppPaths.trip(trip.restResourceId),
                          ),
                        ),
                      );
                    },
                    childCount: dashboard.recentTrips.length,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.onProfile,
    required this.onLogout,
  });

  final String name;
  final VoidCallback onProfile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good ${_greeting()}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onProfile,
          icon: const Icon(Icons.person_outline_rounded),
          tooltip: 'Profile',
        ),
        IconButton(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Logout',
        ),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.status});

  final SyncStatusSummary status;

  @override
  Widget build(BuildContext context) {
    if (!status.needsSync && status.isOnline) return const SizedBox.shrink();
    final color = status.isOnline ? Colors.orange : Colors.red;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 14,
        child: Row(
          children: [
            Icon(
              status.isOnline ? Icons.cloud_upload_outlined : Icons.cloud_off,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status.isOnline
                    ? '${status.totalPending} items pending sync'
                    : 'Offline — ${status.totalPending} items queued',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTripCard extends StatelessWidget {
  const _ActiveTripCard({
    required this.trip,
    required this.isTracking,
    required this.onTap,
  });

  final TravelRequestModel trip;
  final bool isTracking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isTracking ? 'Live Tracking' : trip.status,
                      style: const TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            trip.displayToLocation,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            trip.routeSummary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayStatsGrid extends StatelessWidget {
  const _TodayStatsGrid({
    required this.distanceKm,
    required this.meetingMinutes,
    required this.pending,
    required this.completed,
    required this.isTracking,
  });

  final double distanceKm;
  final int meetingMinutes;
  final int pending;
  final int completed;
  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Distance',
                value: '${distanceKm.toStringAsFixed(1)} km',
                icon: Icons.route_rounded,
                color: const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Meeting',
                value: '$meetingMinutes min',
                icon: Icons.groups_rounded,
                color: const Color(0xFFFF9800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Pending',
                value: '$pending',
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFF9C27B0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'GPS',
                value: isTracking ? 'Active' : 'Idle',
                icon: Icons.gps_fixed_rounded,
                color: isTracking
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onCreateTrip,
    required this.onViewTrips,
    required this.onReturnTrip,
    required this.onAnalytics,
  });

  final VoidCallback onCreateTrip;
  final VoidCallback onViewTrips;
  final VoidCallback? onReturnTrip;
  final VoidCallback onAnalytics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ActionChip(
          label: 'Create Trip',
          icon: Icons.add_road_rounded,
          onTap: onCreateTrip,
        ),
        _ActionChip(
          label: 'View Trips',
          icon: Icons.list_alt_rounded,
          onTap: onViewTrips,
        ),
        _ActionChip(
          label: 'Return Trip',
          icon: Icons.u_turn_left_rounded,
          onTap: onReturnTrip,
          enabled: onReturnTrip != null,
        ),
        _ActionChip(
          label: 'Analytics',
          icon: Icons.insights_rounded,
          onTap: onAnalytics,
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: enabled
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.disabledColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.disabledColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTripTile extends StatelessWidget {
  const _RecentTripTile({
    required this.trip,
    required this.onTap,
  });

  final TravelRequestModel trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('MMM d').format(trip.requestDate);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.directions_car_filled_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.displayToLocation,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$date · ${trip.status}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(trip.totalDistanceKm ?? trip.distance ?? 0).toStringAsFixed(1)} km',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

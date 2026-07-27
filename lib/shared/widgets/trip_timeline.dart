import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/tracking/domain/entities/trip_timeline_event.dart';

/// Uber-style vertical trip timeline.
class TripTimeline extends StatelessWidget {
  const TripTimeline({
    super.key,
    required this.events,
  });

  final List<TripTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat('h:mm a');

    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          _TimelineRow(
            event: events[i],
            isLast: i == events.length - 1,
            timeLabel: events[i].timestamp != null
                ? timeFmt.format(events[i].timestamp!)
                : '—',
            theme: theme,
          ),
        ],
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.isLast,
    required this.timeLabel,
    required this.theme,
  });

  final TripTimelineEvent event;
  final bool isLast;
  final String timeLabel;
  final ThemeData theme;

  Color get _dotColor {
    if (event.isActive) return theme.colorScheme.primary;
    if (event.isCompleted) return const Color(0xFF4CAF50);
    return theme.colorScheme.outline;
  }

  IconData get _icon => switch (event.type) {
        TripTimelineEventType.departure => Icons.trip_origin,
        TripTimelineEventType.arrival => Icons.place_rounded,
        TripTimelineEventType.meetingStart => Icons.groups_rounded,
        TripTimelineEventType.meetingEnd => Icons.event_available_rounded,
        TripTimelineEventType.statusChange => Icons.timeline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: event.isActive ? 14 : 12,
                  height: event.isActive ? 14 : 12,
                  decoration: BoxDecoration(
                    color: _dotColor,
                    shape: BoxShape.circle,
                    boxShadow: event.isActive
                        ? [
                            BoxShadow(
                              color: _dotColor.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _dotColor.withValues(alpha: 0.8),
                            theme.dividerColor,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon, size: 20, color: _dotColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (event.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            event.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    timeLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

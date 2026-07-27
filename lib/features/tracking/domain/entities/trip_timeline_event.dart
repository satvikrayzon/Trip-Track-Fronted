import 'package:equatable/equatable.dart';

enum TripTimelineEventType {
  departure,
  arrival,
  meetingStart,
  meetingEnd,
  statusChange,
}

class TripTimelineEvent extends Equatable {
  final TripTimelineEventType type;
  final String title;
  final String? subtitle;
  final DateTime? timestamp;
  final bool isCompleted;
  final bool isActive;

  const TripTimelineEvent({
    required this.type,
    required this.title,
    this.subtitle,
    this.timestamp,
    this.isCompleted = false,
    this.isActive = false,
  });

  @override
  List<Object?> get props => [type, title, timestamp, isCompleted, isActive];
}

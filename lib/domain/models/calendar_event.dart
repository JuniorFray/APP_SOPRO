import 'package:flutter/material.dart';

enum EventSource {
  sopro,
  soproAi,
  google,
  apple,
  outlook,
  other,
}

class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final EventSource source;
  final String? calendarName;
  final Color? color;

  CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    required this.source,
    this.calendarName,
    this.color,
  });
}

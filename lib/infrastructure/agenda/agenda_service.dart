import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/material.dart';

import '../../data/database/daos/agenda_event_dao.dart';
import '../../domain/models/calendar_event.dart';

class AgendaService {
  final dc.DeviceCalendarPlugin _deviceCalendarPlugin;
  final AgendaEventDao _agendaDao;

  AgendaService(this._agendaDao) : _deviceCalendarPlugin = dc.DeviceCalendarPlugin();

  Future<bool> requestPermissions() async {
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !permissionsGranted.data!) {
      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      if (!permissionsGranted.isSuccess || !permissionsGranted.data!) {
        return false;
      }
    }
    return true;
  }

  Future<List<CalendarEvent>> getEventsForDateRange(DateTime start, DateTime end) async {
    final hasPerm = await requestPermissions();
    if (!hasPerm) return [];

    final List<CalendarEvent> allEvents = [];

    // 1. Obter eventos nativos (Google, Apple, Outlook, etc)
    try {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        for (final calendar in calendarsResult.data!) {
          final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
            calendar.id,
            dc.RetrieveEventsParams(startDate: start, endDate: end),
          );

          if (eventsResult.isSuccess && eventsResult.data != null) {
            for (final e in eventsResult.data!) {
              if (e.start == null || e.end == null) continue;
              
              allEvents.add(CalendarEvent(
                id: e.eventId ?? '',
                title: e.title ?? 'Sem Título',
                description: e.description,
                startTime: e.start!,
                endTime: e.end!,
                source: _determineSourceFromCalendarName(calendar.accountName ?? '', calendar.name ?? ''),
                calendarName: calendar.name,
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao ler calendário nativo: $e');
    }

    // 2. Obter eventos exclusivos do Sopro (Drift)
    try {
      final soproEvents = await _agendaDao.getEventsInRange(
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      );
      
      for (final s in soproEvents) {
        allEvents.add(CalendarEvent(
          id: s.id,
          title: s.title,
          description: s.description,
          startTime: DateTime.fromMillisecondsSinceEpoch(s.startTime),
          endTime: DateTime.fromMillisecondsSinceEpoch(s.endTime),
          source: s.source == 'ai_suggestion' ? EventSource.soproAi : EventSource.sopro,
        ));
      }
    } catch (e) {
      debugPrint('Erro ao ler agenda local Sopro: $e');
    }
    
    // Sort chronologically
    allEvents.sort((a, b) => a.startTime.compareTo(b.startTime));

    return allEvents;
  }

  EventSource _determineSourceFromCalendarName(String accountName, String calendarName) {
    final lowerAccount = accountName.toLowerCase();
    final lowerName = calendarName.toLowerCase();

    if (lowerAccount.contains('gmail') || lowerAccount.contains('google') || lowerName.contains('google')) {
      return EventSource.google;
    }
    if (lowerAccount.contains('icloud') || lowerName.contains('icloud') || lowerName.contains('apple')) {
      return EventSource.apple;
    }
    if (lowerAccount.contains('outlook') || lowerAccount.contains('exchange') || lowerAccount.contains('hotmail')) {
      return EventSource.outlook;
    }
    
    return EventSource.other;
  }
}

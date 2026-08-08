import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/agenda/agenda_service.dart';
import '../../domain/models/calendar_event.dart';
import 'database_provider.dart';

final agendaServiceProvider = Provider<AgendaService>((ref) {
  final db = ref.watch(databaseProvider);
  return AgendaService(db.agendaEventDao);
});

class AgendaState {
  final bool isLoading;
  final bool hasPermission;
  final Map<DateTime, List<CalendarEvent>> events;
  final DateTime currentMonth;
  final Set<EventSource> enabledSources;

  AgendaState({
    this.isLoading = false,
    this.hasPermission = true,
    this.events = const {},
    required this.currentMonth,
    this.enabledSources = const {
      EventSource.sopro,
      EventSource.soproAi,
      EventSource.google,
      EventSource.apple,
      EventSource.outlook,
    },
  });

  AgendaState copyWith({
    bool? isLoading,
    bool? hasPermission,
    Map<DateTime, List<CalendarEvent>>? events,
    DateTime? currentMonth,
    Set<EventSource>? enabledSources,
  }) {
    return AgendaState(
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
      events: events ?? this.events,
      currentMonth: currentMonth ?? this.currentMonth,
      enabledSources: enabledSources ?? this.enabledSources,
    );
  }
}

class AgendaNotifier extends StateNotifier<AgendaState> {
  final AgendaService _service;

  AgendaNotifier(this._service)
      : super(AgendaState(
          currentMonth: DateTime.now(),
        )) {
    loadEventsForMonth(DateTime.now());
  }

  Future<void> loadEventsForMonth(DateTime month) async {
    state = state.copyWith(isLoading: true, currentMonth: month);
    
    final hasPerm = await _service.requestPermissions();
    if (!hasPerm) {
      state = state.copyWith(isLoading: false, hasPermission: false, events: {});
      return;
    }

    final start = DateTime(month.year, month.month - 1, 1);
    final end = DateTime(month.year, month.month + 2, 0, 23, 59, 59);

    final rawEvents = await _service.getEventsForDateRange(start, end);
    
    // Filtra pelas fontes ativas
    final filtered = rawEvents.where((e) => state.enabledSources.contains(e.source)).toList();

    final Map<DateTime, List<CalendarEvent>> grouped = {};
    for (final e in filtered) {
      final dateKey = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
      grouped.putIfAbsent(dateKey, () => []).add(e);
      
      if (e.endTime.day != e.startTime.day) {
        var nextDay = dateKey.add(const Duration(days: 1));
        while (nextDay.isBefore(e.endTime) || nextDay.isAtSameMomentAs(DateTime(e.endTime.year, e.endTime.month, e.endTime.day))) {
          grouped.putIfAbsent(nextDay, () => []).add(e);
          nextDay = nextDay.add(const Duration(days: 1));
        }
      }
    }

    state = state.copyWith(isLoading: false, hasPermission: true, events: grouped);
  }

  void toggleSource(EventSource source) {
    final current = Set<EventSource>.from(state.enabledSources);
    if (current.contains(source)) {
      current.remove(source);
    } else {
      current.add(source);
    }
    state = state.copyWith(enabledSources: current);
    loadEventsForMonth(state.currentMonth);
  }
  
  List<CalendarEvent> getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return state.events[key] ?? [];
  }
}

final agendaProvider = StateNotifierProvider<AgendaNotifier, AgendaState>((ref) {
  final service = ref.watch(agendaServiceProvider);
  return AgendaNotifier(service);
});

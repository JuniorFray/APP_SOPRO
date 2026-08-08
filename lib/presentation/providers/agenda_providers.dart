import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/agenda/agenda_service.dart';
import '../../domain/models/calendar_event.dart';
import 'database_provider.dart';

// Chave de persistência das fontes ativas (toggles do sheet de contas). Guarda a
// lista de EventSource.name habilitados; ausente = todas ligadas (default).
const _kEnabledSourcesPref = 'agenda_enabled_sources';

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
      EventSource.other,
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
    _restoreAndLoad();
  }

  // Restaura as fontes ativas persistidas ANTES do primeiro load (evita um flash
  // com fontes que o usuário havia desligado). Persistência local no próprio
  // notifier — não no AppInitializer — para não instanciar o provider cedo no boot
  // (o que dispararia o pedido de permissão de calendário fora de hora).
  Future<void> _restoreAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kEnabledSourcesPref);
      if (saved != null) {
        final restored = <EventSource>{
          for (final e in EventSource.values)
            if (saved.contains(e.name)) e,
        };
        state = state.copyWith(enabledSources: restored);
      }
    } catch (_) {/* prefs indisponível — mantém o default (todas ligadas) */}
    loadEventsForMonth(DateTime.now());
  }

  Future<void> _persistEnabledSources(Set<EventSource> sources) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kEnabledSourcesPref,
        sources.map((e) => e.name).toList(),
      );
    } catch (_) {/* best-effort: falha de persistência não quebra o toggle */}
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
    _persistEnabledSources(current); // fire-and-forget: sobrevive ao restart
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

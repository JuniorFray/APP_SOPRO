import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_colors.dart';
import '../../providers/agenda_providers.dart';
import '../../../domain/models/calendar_event.dart';
import 'agenda_accounts_sheet.dart';
import 'agenda_day_screen.dart';
import 'agenda_event_dialog.dart';

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agendaProvider);
    final notifier = ref.read(agendaProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Agenda', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.backgroundSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.accent),
            tooltip: 'Novo Evento',
            onPressed: () => _showAddEventDialog(context, _selectedDay ?? DateTime.now()),
          ),
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'Sincronização & Filtros',
            onPressed: () => _showAccountsSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Atualizar',
            onPressed: () => notifier.loadEventsForMonth(_focusedDay),
          ),
        ],
      ),
      body: _buildBody(state, notifier),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('IA Sopro: Analisando seus emails e rotina...')),
          );
        },
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text('Organizar com IA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBody(AgendaState state, AgendaNotifier notifier) {
    if (!state.hasPermission) {
      return _buildPermissionDenied(notifier);
    }
    
    if (state.isLoading && state.events.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.backgroundSurface,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TableCalendar<CalendarEvent>(
            locale: 'pt_BR',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            daysOfWeekHeight: 32,
            rowHeight: 48,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AgendaDayScreen(day: selectedDay),
                ),
              );
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
              notifier.loadEventsForMonth(focusedDay);
            },
            eventLoader: notifier.getEventsForDay,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
              leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.textPrimary),
              rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.textPrimary),
              headerPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13),
              weekendStyle: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            calendarStyle: CalendarStyle(
              defaultTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              weekendTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
              outsideTextStyle: TextStyle(color: AppColors.textDisabled.withOpacity(0.3), fontSize: 14),
              todayDecoration: BoxDecoration(
                color: AppColors.backgroundCardHighlight,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent.withOpacity(0.5)),
              ),
              selectedDecoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              markerDecoration: const BoxDecoration(
                color: Color(0xFF4285F4),
                shape: BoxShape.circle,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return const SizedBox();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: events.take(3).map((e) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 4),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getColorForSource(e.source),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
        const Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_outlined, color: AppColors.textDisabled, size: 36),
                SizedBox(height: 8),
                Text(
                  'Toque em um dia para ver ou adicionar horários',
                  style: TextStyle(color: AppColors.textDisabled, fontStyle: FontStyle.italic, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getColorForSource(EventSource source) {
    switch (source) {
      case EventSource.sopro: return AppColors.accent;
      case EventSource.soproAi: return AppColors.onboardingNotification;
      case EventSource.google: return const Color(0xFF4285F4);
      case EventSource.apple: return const Color(0xFFA3AAAE);
      case EventSource.outlook: return const Color(0xFF0078D4);
      default: return AppColors.textDisabled;
    }
  }

  Widget _buildPermissionDenied(AgendaNotifier notifier) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            const Text(
              'Permissão Negada',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'O Sopro precisa ler seu calendário para exibir compromissos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => notifier.loadEventsForMonth(DateTime.now()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Tentar Novamente', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AgendaAccountsSheet(),
    );
  }

  void _showAddEventDialog(BuildContext context, DateTime date) {
    showDialog(
      context: context,
      builder: (_) => AgendaEventDialog(initialDate: date),
    );
  }
}

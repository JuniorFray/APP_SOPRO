import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../providers/agenda_providers.dart';
import '../../../domain/models/calendar_event.dart';
import 'agenda_event_dialog.dart';
import 'agenda_event_detail_dialog.dart';

class AgendaDayScreen extends ConsumerStatefulWidget {
  final DateTime day;

  const AgendaDayScreen({super.key, required this.day});

  @override
  ConsumerState<AgendaDayScreen> createState() => _AgendaDayScreenState();
}

class _AgendaDayScreenState extends ConsumerState<AgendaDayScreen> {
  final ScrollController _scrollController = ScrollController();
  final double _hourHeight = 60.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final now = DateTime.now();
        final offset = (now.hour - 1) * _hourHeight;
        _scrollController.jumpTo(offset.clamp(0.0, 24 * _hourHeight));
      }
    });
  }

  void _showAddEventDialog() {
    showDialog(
      context: context,
      builder: (_) => AgendaEventDialog(initialDate: widget.day),
    );
  }

  void _showEventDetail(CalendarEvent event) {
    showDialog(
      context: context,
      builder: (_) => AgendaEventDetailDialog(event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(agendaProvider.notifier);
    ref.watch(agendaProvider); // Rebuild on state change
    final events = notifier.getEventsForDay(widget.day);
    
    final dayFormatted = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(widget.day);

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(
          dayFormatted[0].toUpperCase() + dayFormatted.substring(1),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.backgroundSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_task, color: AppColors.accent),
            tooltip: 'Novo Evento',
            onPressed: _showAddEventDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddEventDialog,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Stack(
          children: [
            // Fundo: Linhas das horas
            Column(
              children: List.generate(25, (index) {
                return Container(
                  height: _hourHeight,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: AppColors.border.withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 4, right: 16),
                        child: Text(
                          '${index.toString().padLeft(2, '0')}:00',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                );
              }),
            ),
            
            // Camada de Eventos Clicáveis
            ...events.map((e) {
              final topOffset = _calculateOffset(e.startTime);
              final height = _calculateHeight(e.startTime, e.endTime);
              
              return Positioned(
                top: topOffset,
                left: 68,
                right: 16,
                height: height,
                child: GestureDetector(
                  onTap: () => _showEventDetail(e),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: _getColorForSource(e.source).withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: _getColorForSource(e.source),
                          width: 4,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (height > 32)
                          Text(
                            '${DateFormat('HH:mm').format(e.startTime)} - ${DateFormat('HH:mm').format(e.endTime)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  double _calculateOffset(DateTime time) {
    if (time.day != widget.day.day) {
      return 0;
    }
    return (time.hour + (time.minute / 60.0)) * _hourHeight;
  }

  double _calculateHeight(DateTime start, DateTime end) {
    DateTime effectiveStart = start;
    if (start.isBefore(DateTime(widget.day.year, widget.day.month, widget.day.day))) {
      effectiveStart = DateTime(widget.day.year, widget.day.month, widget.day.day);
    }
    
    DateTime effectiveEnd = end;
    if (end.isAfter(DateTime(widget.day.year, widget.day.month, widget.day.day, 23, 59, 59))) {
      effectiveEnd = DateTime(widget.day.year, widget.day.month, widget.day.day, 23, 59, 59);
    }

    final durationInMinutes = effectiveEnd.difference(effectiveStart).inMinutes;
    final height = (durationInMinutes / 60.0) * _hourHeight;
    return height < 24 ? 24 : height; 
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
}

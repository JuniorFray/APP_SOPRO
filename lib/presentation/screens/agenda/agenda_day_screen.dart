import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../providers/agenda_providers.dart';
import '../../../domain/models/calendar_event.dart';
import '../../widgets/glass_surface.dart';
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

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(agendaProvider.notifier);
    ref.watch(agendaProvider); // Rebuild on state change
    final events = notifier.getEventsForDay(widget.day);
    
    final dayFormatted = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(widget.day);
    final isToday = _isToday(widget.day);
    final now = DateTime.now();
    final nowOffset = (now.hour + (now.minute / 60.0)) * _hourHeight;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(
          dayFormatted[0].toUpperCase() + dayFormatted.substring(1),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.backgroundSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
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
        child: const Icon(Icons.add, color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        child: GlassSurface(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            children: [
              // Fundo: Linhas das horas com visual suave
              Column(
                children: List.generate(25, (index) {
                  return Container(
                    height: _hourHeight,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: AppColors.border,
                          width: 0.5,
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
                              color: AppColors.textDisabled,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  );
                }),
              ),
              
              // Linha horizontal da hora atual (exibida APENAS se a data for HOJE)
              if (isToday)
                Positioned(
                  top: nowOffset,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1.5,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),

              // Camada de Eventos Clicáveis com Glass e AppRadius consistentes
              ...events.map((e) {
                final topOffset = _calculateOffset(e.startTime);
                final height = _calculateHeight(e.startTime, e.endTime);
                final sourceColor = _getColorForSource(e.source);
                
                return Positioned(
                  top: topOffset,
                  left: 68,
                  right: 12,
                  height: height,
                  child: GestureDetector(
                    onTap: () => _showEventDetail(e),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: sourceColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border(
                          left: BorderSide(
                            color: sourceColor,
                            width: 3.5,
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
                              color: AppColors.textPrimary,
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
      case EventSource.sopro:
        return AppColors.accent;
      case EventSource.soproAi:
        return AppColors.onboardingNotification;
      case EventSource.google:
        return AppColors.onboardingBle;
      case EventSource.apple:
        return AppColors.textSecondary;
      case EventSource.outlook:
        return AppColors.accentPurple;
      default:
        return AppColors.textDisabled;
    }
  }
}

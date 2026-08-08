import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/calendar_event.dart';
import '../../providers/agenda_providers.dart';
import '../../providers/database_provider.dart';
import 'agenda_event_dialog.dart';

class AgendaEventDetailDialog extends ConsumerWidget {
  final CalendarEvent event;

  const AgendaEventDetailDialog({super.key, required this.event});

  Future<void> _deleteEvent(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Text('Excluir Evento', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Deseja realmente excluir este evento da sua Agenda Sopro?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final db = ref.read(databaseProvider);
      await db.agendaEventDao.deleteEvent(event.id);
      
      // Reload events
      ref.read(agendaProvider.notifier).loadEventsForMonth(event.startTime);

      if (context.mounted) {
        Navigator.pop(context); // Close detail dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evento excluído com sucesso!')),
        );
      }
    }
  }

  void _editEvent(BuildContext context, WidgetRef ref) {
    Navigator.pop(context); // Close detail dialog
    // Passa o evento existente → o dialog faz UPDATE no mesmo id (não duplica).
    showDialog(
      context: context,
      builder: (_) => AgendaEventDialog(
        initialDate: event.startTime,
        existingEvent: event,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSoproEvent = event.source == EventSource.sopro || event.source == EventSource.soproAi;
    final dateFormatted = DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'pt_BR').format(event.startTime);
    final timeFormatted = '${DateFormat('HH:mm').format(event.startTime)} - ${DateFormat('HH:mm').format(event.endTime)}';

    return Dialog(
      backgroundColor: AppColors.backgroundSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Category badge & close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getColorForSource(event.source).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getColorForSource(event.source)),
                  ),
                  child: Text(
                    _getSourceLabel(event.source),
                    style: TextStyle(
                      color: _getColorForSource(event.source),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Event Title
            Text(
              event.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Date & Time
            Row(
              children: [
                const Icon(Icons.access_time, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeFormatted,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      dateFormatted[0].toUpperCase() + dateFormatted.substring(1),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description if available
            if (event.description != null && event.description!.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.notes, color: AppColors.textSecondary, size: 20),
                  SizedBox(width: 10),
                  Text('Descrição', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  event.description!,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Note for native events vs Sopro events
            if (!isSoproEvent) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundCardHighlight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.textSecondary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Evento sincronizado externamente.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            if (isSoproEvent) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteEvent(context, ref),
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      label: const Text('Excluir', style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _editEvent(context, ref),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Editar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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

  String _getSourceLabel(EventSource source) {
    switch (source) {
      case EventSource.sopro: return 'Sopro Pessoal';
      case EventSource.soproAi: return 'Sugestão IA';
      case EventSource.google: return 'Google Calendar';
      case EventSource.apple: return 'iCloud Calendar';
      case EventSource.outlook: return 'Outlook Calendar';
      default: return 'Calendário';
    }
  }
}

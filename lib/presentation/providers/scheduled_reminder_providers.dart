import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/scheduled_reminder_entity.dart';
import 'database_provider.dart';

// Observa o próximo lembrete ativo (menor scheduledAt) — card "Próximo
// lembrete" da Home. null quando não há lembretes ativos.
final nextReminderProvider =
    StreamProvider<ScheduledReminderEntity?>((ref) {
  return ref.watch(scheduledReminderRepositoryProvider).watchNext();
});

// Observa todos os lembretes ativos em tempo real (lista da tela de lembretes).
final allActiveRemindersProvider =
    StreamProvider<List<ScheduledReminderEntity>>((ref) {
  return ref.watch(scheduledReminderRepositoryProvider).watchAllActive();
});

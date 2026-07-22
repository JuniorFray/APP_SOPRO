import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/activity_log_entry_entity.dart';
import 'database_provider.dart';

// Observa as atividades mais recentes em tempo real — seção "Atividade
// Recente" da Home. Mais novas primeiro, limitado ao default do repositório.
final recentActivityProvider =
    StreamProvider<List<ActivityLogEntryEntity>>((ref) {
  return ref.watch(activityLogRepositoryProvider).watchRecent();
});

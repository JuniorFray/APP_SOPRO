import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/activity_log_entry_entity.dart';
import '../../domain/repositories/i_activity_log_repository.dart';
import '../../presentation/providers/database_provider.dart';
import '../conversation/conversation_state.dart';

// Memory Engine — organiza a memória que o Sopro JÁ tem sob uma interface comum
// de curto/longo prazo (voice_structure_doc/architecture/06-Memory-Engine.md).
//
// Estágio 7 (mínimo viável, comportamento-preservado): NÃO adiciona storage novo.
// Só unifica o que existe:
//   - Curto prazo  → ConversationContext (RAM, TTL 2min) — assunto/entidades da
//                    conversa atual, injetado no prompt.
//   - Longo prazo  → ActivityLogRepository (SQLite) — histórico persistente.
// Os call sites atuais continuam usando os dois diretamente; esta camada é
// aditiva (fachada + provider) para futura evolução (perfil, busca semântica).

// Memória de curto prazo: contexto transitório da conversa.
abstract class ShortTermMemory {
  // Trecho de contexto para o prompt (vazio se expirado/sem conteúdo).
  String promptSummary();
  // Já passou do TTL? (deve ser descartada antes de reutilizar).
  bool get isExpired;
  // Zera o contexto (conversa concluída/cancelada/expirada).
  void clear();
}

// Memória de longo prazo: fatos persistentes (hoje, o histórico de atividades).
abstract class LongTermMemory {
  // Registra um fato/atividade.
  Future<void> record({
    required ActivityType type,
    required String title,
    String subtitle,
    String? environmentId,
  });
  // Observa os registros mais recentes.
  Stream<List<ActivityLogEntryEntity>> recent({int limit});
}

// Adapta o ConversationContext existente ao contrato de curto prazo.
class ConversationShortTermMemory implements ShortTermMemory {
  final ConversationContext _ctx;
  const ConversationShortTermMemory(this._ctx);

  @override
  String promptSummary() => _ctx.promptSummary();
  @override
  bool get isExpired => _ctx.isExpired;
  @override
  void clear() => _ctx.clear();
}

// Adapta o ActivityLogRepository existente ao contrato de longo prazo.
class ActivityLongTermMemory implements LongTermMemory {
  final IActivityLogRepository _repo;
  const ActivityLongTermMemory(this._repo);

  @override
  Future<void> record({
    required ActivityType type,
    required String title,
    String subtitle = '',
    String? environmentId,
  }) =>
      _repo.log(
        type: type,
        title: title,
        subtitle: subtitle,
        environmentId: environmentId,
      );

  @override
  Stream<List<ActivityLogEntryEntity>> recent({int limit = 20}) =>
      _repo.watchRecent(limit: limit);
}

// Fachada única de memória — segura curto + longo prazo.
class MemoryEngine {
  final ShortTermMemory shortTerm;
  final LongTermMemory longTerm;
  const MemoryEngine({required this.shortTerm, required this.longTerm});
}

// Provider — liga os dois componentes de memória JÁ existentes, sem storage novo.
final memoryEngineProvider = Provider<MemoryEngine>((ref) => MemoryEngine(
      shortTerm:
          ConversationShortTermMemory(ref.watch(conversationContextProvider)),
      longTerm: ActivityLongTermMemory(ref.watch(activityLogRepositoryProvider)),
    ));

// Entidade pura de domínio para um Gatilho (intenção vinculada a um local).
// Um Trigger é o "sussurro" que o app entrega quando o usuário chega ao ambiente.
class TriggerEntity {
  // Identificador único gerado via UUID v4
  final String id;

  // FK para o Environment ao qual este gatilho pertence
  final String environmentId;

  // Título curto exibido na notificação
  final String title;

  // Conteúdo detalhado do gatilho (lembrete, instrução, etc.)
  final String content;

  // Indica se o gatilho está ativo e deve disparar ao entrar no geofence
  final bool isActive;

  // Data de criação do registro
  final DateTime createdAt;

  // Dono do gatilho quando é cópia read-only de outro usuário (Fase 3). null = meu.
  final String? ownerId;

  const TriggerEntity({
    required this.id,
    required this.environmentId,
    required this.title,
    required this.content,
    required this.isActive,
    required this.createdAt,
    this.ownerId,
  });

  // true = gatilho de outra pessoa (do dono, ou do convidado visto pelo dono) →
  // exibido somente leitura na tela do ambiente.
  bool get isReadOnly => ownerId != null;
}

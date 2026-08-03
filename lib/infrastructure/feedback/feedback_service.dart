import '../logging/app_logger.dart';
import '../logging/core/logger_configuration.dart';
import '../logging/core/session_manager.dart';

// Envia o feedback digitado pelo usuário para a tabela `feedback` do Supabase.
//
// Reaproveita o transporte HTTP de AppLogger.postToTable (mesmo client, mesma
// autenticação publishable, encoding UTF-8 e fire-and-forget) — só muda a
// tabela de destino e o corpo do POST. Nenhuma infraestrutura de conexão nova.
//
// Corpo enviado: { device_id, message, app_version, created_at }.
// A coluna `category` existe na tabela mas fica de fora por ora (aceita null).
class FeedbackService {
  FeedbackService._();

  // POST fire-and-forget em `feedback`. Falhas de rede são silenciosas — a UI
  // confirma de forma otimista (mesma semântica do logging).
  static Future<void> send(String message) {
    return AppLogger.postToTable('feedback', {
      // Mesmo installation_id já usado nos logs (SessionManager).
      'device_id': SessionManager.installationId,
      'message': message,
      // Versão do app reaproveitada da configuração de logging.
      'app_version': LoggerConfiguration.appVersion,
      // Timestamp em UTC ISO-8601 (a coluna também tem DEFAULT NOW()).
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

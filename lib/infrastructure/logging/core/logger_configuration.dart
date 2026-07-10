import 'package:flutter/foundation.dart';

// Configuração central do sistema de logging.
// Todos os parâmetros são estáticos e mutáveis, permitindo ajuste em runtime
// (ex.: habilitar verbose logging em QA sem rebuild).
class LoggerConfiguration {
  LoggerConfiguration._();

  // Ativa trace/debug e desabilita mascaramento de campos de diagnóstico.
  // Em produção deve ser false.
  static bool debugLogging = kDebugMode;

  // Habilita envio de eventos para o Supabase.
  static bool enableSupabase = true;

  // Habilita saída de log no console (debugPrint).
  static bool enableConsole = kDebugMode;

  // Formata a saída do console com JSON indentado em vez de uma linha só.
  static bool enablePrettyPrint = kDebugMode;

  // Aplica LogSanitizer sobre o payload antes de persistir/enviar.
  static bool enableDataMasking = true;

  // Tamanho máximo da fila de eventos pendentes (fase futura — queue).
  static int maxQueueSize = 100;

  // Número de eventos enviados por lote ao Supabase (fase futura — batch).
  static int batchSize = 10;

  // Tentativas de reenvio em caso de falha de rede (fase futura — retry).
  static int retryAttempts = 3;

  // Versão do app — alimentada pelo AppInitializer na inicialização.
  static String appVersion = '0.1.0';

  // Build number — alimentado pelo AppInitializer na inicialização.
  static String buildNumber = '1';

  // Plataforma alvo (ex.: 'android', 'ios').
  static String platform = 'android';
}

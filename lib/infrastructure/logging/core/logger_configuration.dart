import 'package:flutter/foundation.dart';

import 'log_level.dart';

// Configuração central do sistema de logging Sopro.
//
// Todos os parâmetros são estáticos e mutáveis para permitir ajuste em
// runtime sem rebuild (ex.: habilitar verbose em QA, desativar console em
// produção via feature flag).
//
// Ordem de leitura recomendada para entender o sistema:
//   1. debugLogging  — modo geral
//   2. minimumLevel  — filtragem por severidade
//   3. enableConsole / enablePrettyPrint — saída local
//   4. enableSupabase — saída remota
//   5. enableDataMasking — privacidade
//   6. maxQueueSize / batchSize / retryAttempts — fase futura
class LoggerConfiguration {
  LoggerConfiguration._();

  // ── Versionamento do schema de log ───────────────────────────────────────

  // Versão do schema JSON do LogEvent. Incluída automaticamente pelo Logger
  // em todos os eventos — nunca preenchida manualmente pelo desenvolvedor.
  //
  // Regra de incremento:
  //   • Incrementar quando um campo obrigatório for adicionado ou removido.
  //   • Incrementar quando a semântica de um campo existente mudar.
  //   • NÃO incrementar para adição de campos opcionais compatíveis.
  //
  // Consumidores (Supabase, dashboards, pipelines) devem filtrar por
  // schema_version para tratar formatos diferentes sem quebrar.
  static const int schemaVersion = 1;

  // ── Modo de operação ──────────────────────────────────────────────────────

  // Ativa trace/debug e desabilita mascaramento de campos de diagnóstico
  // (transcript, intent, gemini_response…). DEVE ser false em produção.
  // Padrão: kDebugMode (true em debug, false em release/profile).
  static bool debugLogging = kDebugMode;

  // ── Filtragem por nível ───────────────────────────────────────────────────

  // Nível mínimo para emissão de eventos fora do modo debug.
  // Em modo debug, o nível efetivo é sempre LogLevel.trace.
  // Em produção (debugLogging == false), eventos abaixo deste nível são
  // descartados silenciosamente antes de qualquer processamento.
  // Padrão: LogLevel.info (trace e debug suprimidos em produção).
  static LogLevel minimumLevel = LogLevel.info;

  // ── Destinos de saída ─────────────────────────────────────────────────────

  // Habilita envio de eventos ao Supabase (via AppLogger._send()).
  // Desativar em testes automatizados para evitar chamadas de rede reais.
  static bool enableSupabase = true;

  // Habilita saída de log no console via debugPrint.
  // Padrão: kDebugMode (silencioso em produção para evitar leak de dados).
  static bool enableConsole = kDebugMode;

  // Formata o JSON do console com indentação legível.
  // Se false, emite uma linha compacta por evento.
  // Padrão: kDebugMode.
  static bool enablePrettyPrint = kDebugMode;

  // ── Privacidade ───────────────────────────────────────────────────────────

  // Aplica LogSanitizer sobre o payload antes de qualquer saída.
  // Desativar apenas em ambientes de teste controlados.
  static bool enableDataMasking = true;

  // ── Fase futura: fila e retry ─────────────────────────────────────────────

  // Número máximo de LogEvents aguardando envio na fila em memória.
  // Eventos além deste limite são descartados com log interno de overflow.
  // (não implementado nesta fase)
  static int maxQueueSize = 100;

  // Número de eventos agrupados por requisição ao Supabase.
  // Reduz overhead de rede em cenários de alta frequência de eventos.
  // (não implementado nesta fase)
  static int batchSize = 10;

  // Tentativas de reenvio em caso de falha de rede antes de descartar.
  // (não implementado nesta fase)
  static int retryAttempts = 3;

  // ── Metadados do app ─────────────────────────────────────────────────────

  // Versão semântica do app. Atualizado pelo AppInitializer se disponível.
  // Valor padrão reflete a versão atual do pubspec.yaml.
  static String appVersion = '0.1.0';

  // Build number do app. Atualizado pelo AppInitializer se disponível.
  static String buildNumber = '1';

  // Plataforma alvo. Atualizado no init para refletir o dispositivo real.
  // Valores esperados: 'android', 'ios'.
  static String platform = 'android';
}

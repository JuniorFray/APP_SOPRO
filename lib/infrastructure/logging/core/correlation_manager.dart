import 'package:uuid/uuid.dart';

// Gerencia correlation IDs para rastreamento de operações de ponta a ponta.
//
// ── Por que um Map em vez de um único ID global? ──────────────────────────
// O app executa múltiplos fluxos assíncronos simultaneamente:
//   • Voz (Voice): gravação → Gemini → TTS
//   • BLE: scan → GATT → dedup
//   • Geofence: GPS stream → enter/exit
//   • Background: WorkManager task
//   • Notificações: disparo de trigger
//
// Com um único ID global, a operação B sobrescreveria o ID de A se iniciada
// antes de A terminar. Todos os logs de A passariam a carregar o ID de B.
//
// A solução: cada operação recebe uma chave nomeada (ex.: 'voice', 'ble').
// O correlation_id fica isolado por operação, sem interferência cruzada.
//
// ── Ciclo de vida de uma operação ─────────────────────────────────────────
//   final id = CorrelationManager.beginOperation('voice');
//   // Logger lê o correlationId automaticamente, ou o chamador pode usar:
//   Logger.info('voice_start', correlationId: id);
//   // ... processamento ...
//   CorrelationManager.endOperation('voice');
//
// ── Compatibilidade retroativa ────────────────────────────────────────────
// O getter [currentCorrelationId] retorna o ID da operação iniciada mais
// recentemente, permitindo que código legado que não nomeia operações
// continue funcionando sem alteração.
class CorrelationManager {
  CorrelationManager._();

  static const _uuid = Uuid();

  // Mapa de operações ativas: operationName → correlationId.
  // Dart é single-threaded por isolate; este mapa é modificado apenas em
  // código síncrono, tornando as operações atomicamente seguras.
  static final Map<String, String> _active = {};

  // Nome da última operação iniciada (para [currentCorrelationId]).
  static String? _lastKey;

  // Inicia uma operação rastreável identificada por [operationName].
  //
  // Retorna o correlationId gerado. O chamador pode armazená-lo para passar
  // explicitamente a Logger.info(..., correlationId: id) quando múltiplas
  // operações do mesmo tipo ocorrem simultaneamente.
  //
  // Se [operationName] já estava ativo, o ID anterior é substituído e um
  // novo ciclo rastreável começa.
  static String beginOperation(String operationName) {
    final id = _uuid.v4();
    _active[operationName] = id;
    _lastKey = operationName;
    return id;
  }

  // Encerra a operação [operationName] e descarta seu correlationId.
  // Não lança exceção se [operationName] não estava ativo.
  static void endOperation(String operationName) {
    _active.remove(operationName);
    if (_lastKey == operationName) {
      _lastKey = _active.isEmpty ? null : _active.keys.last;
    }
  }

  // Retorna o correlationId da operação [operationName], ou null se inativa.
  // Use quando precisar do ID de uma operação específica em contexto concorrente.
  static String? correlationIdFor(String operationName) =>
      _active[operationName];

  // Retorna o correlationId da operação iniciada mais recentemente.
  // Útil para contextos onde apenas uma operação está ativa por vez.
  // Em cenários concorrentes, prefira [correlationIdFor].
  static String? get currentCorrelationId =>
      _lastKey != null ? _active[_lastKey] : null;

  // Snapshot somente-leitura de todas as operações ativas e seus IDs.
  // Útil para diagnóstico e logging de contexto completo.
  static Map<String, String> get activeOperations =>
      Map.unmodifiable(_active);

  // Encerra todas as operações ativas. Use apenas em testes ou reset de estado.
  static void resetAll() {
    _active.clear();
    _lastKey = null;
  }
}

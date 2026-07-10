import 'package:uuid/uuid.dart';

// Gerencia o correlation_id usado para rastrear operações de ponta a ponta.
//
// Uso típico (fluxo de voz, por exemplo):
//   CorrelationManager.beginOperation();
//   // ... chamadas ao Gemini, DB, TTS ...
//   CorrelationManager.endOperation();
//
// Todos os LogEvents emitidos entre begin e end compartilham o mesmo
// correlation_id, permitindo reconstruir a cadeia de eventos no observability.
class CorrelationManager {
  CorrelationManager._();

  static const _uuid = Uuid();
  static String? _currentCorrelationId;

  // ID da operação em andamento, ou null se nenhuma operação foi iniciada.
  static String? get currentCorrelationId => _currentCorrelationId;

  // Inicia uma nova operação rastreável, gerando um correlation_id fresco.
  // O parâmetro [operationName] é reservado para uso futuro (ex.: tracing).
  static void beginOperation([String? operationName]) {
    _currentCorrelationId = _uuid.v4();
  }

  // Encerra a operação atual e descarta o correlation_id.
  static void endOperation() {
    _currentCorrelationId = null;
  }
}

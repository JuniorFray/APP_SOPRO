import 'dart:async';

// Event Bus — publish/subscribe simples e desacoplado
// (voice_structure_doc/architecture/12-Event-Bus.md).
//
// Estágio 8 (aditivo): NÃO substitui a telemetria atual (Logger/Supabase). É uma
// camada de evento INTERNO que espelha as instrumentações mais relevantes do
// fluxo de voz, para que Observability/Memory/Plugins possam reagir sem acoplar.
// Broadcast: sem assinantes, os eventos são simplesmente descartados (zero custo,
// sem buffer/leak), então publicar é sempre seguro.

// Evento imutável do barramento (estrutura do spec 12: type/timestamp/source/payload).
class AppEvent {
  final String type;
  final DateTime timestamp;
  final String source;
  final Map<String, dynamic> payload;

  AppEvent({
    required this.type,
    required this.source,
    Map<String, dynamic>? payload,
    DateTime? timestamp,
  })  : payload = payload ?? const {},
        timestamp = timestamp ?? DateTime.now();
}

class EventBus {
  EventBus._();

  // Singleton — um barramento por processo.
  static final EventBus instance = EventBus._();

  final _controller = StreamController<AppEvent>.broadcast();

  // Fluxo de todos os eventos.
  Stream<AppEvent> get stream => _controller.stream;

  // Fluxo filtrado por tipo (açúcar para assinantes).
  Stream<AppEvent> on(String type) =>
      _controller.stream.where((e) => e.type == type);

  // Publica um evento. Sem assinantes → descartado silenciosamente.
  void publish(AppEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  // Encerramento (testes/shutdown).
  Future<void> dispose() => _controller.close();
}

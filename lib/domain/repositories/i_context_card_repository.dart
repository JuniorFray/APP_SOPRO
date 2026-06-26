import '../entities/context_card_entity.dart';

// Contrato do repositório de ContextCards.
abstract interface class IContextCardRepository {
  // Retorna o cartão ativo (mais recentemente atualizado)
  Future<ContextCardEntity?> getActive();

  // Observa o cartão ativo em tempo real — para a tela de edição de perfil
  Stream<ContextCardEntity?> watchActive();

  // Insere ou atualiza um cartão; updatedAt é preenchido automaticamente
  Future<void> save(ContextCardEntity entity);

  // Remove um cartão pelo ID
  Future<void> delete(String id);
}

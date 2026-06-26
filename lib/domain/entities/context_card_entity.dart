// Entidade pura de domínio para o ContextCard (perfil público trocado via BLE).
// Representa as informações que o usuário escolhe compartilhar com outros
// usuários Sopro próximos fisicamente.
class ContextCardEntity {
  // Identificador único gerado via UUID v4
  final String id;

  // Nome de exibição escolhido pelo usuário
  final String displayName;

  // Texto livre descrevendo o usuário ou sua intenção atual
  final String bio;

  // Tags de interesse/contexto separadas por vírgula (ex: "tech,música,café")
  final String tags;

  // Data de criação do cartão
  final DateTime createdAt;

  // Data da última atualização — permite ao receptor saber se está desatualizado
  final DateTime updatedAt;

  const ContextCardEntity({
    required this.id,
    required this.displayName,
    required this.bio,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });
}

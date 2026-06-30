// Entidade pura de domínio para o ContextCard (perfil público trocado via BLE).
// Representa as informações que o usuário escolhe compartilhar com outros
// usuários Sopro próximos fisicamente.
//
// Sprint 8: adicionados campos role (cargo) e company (empresa).
// Sprint 13: adicionado campo phone (WhatsApp/telefone, opcional).
class ContextCardEntity {
  // Identificador único gerado via UUID v4
  final String id;

  // Nome de exibição escolhido pelo usuário
  final String displayName;

  // Cargo profissional (ex: "Desenvolvedor Flutter")
  final String role;

  // Empresa ou organização (ex: "Google", "USP")
  final String company;

  // Nota pessoal — texto livre sobre o usuário ou sua intenção atual
  final String bio;

  // Tags de interesse/contexto separadas por vírgula (ex: "tech,música,café")
  final String tags;

  // Número de telefone/WhatsApp (só dígitos, ex: "11999998888") — opcional
  final String phone;

  // Data de criação do cartão
  final DateTime createdAt;

  // Data da última atualização — permite ao receptor BLE detectar versões mais novas
  final DateTime updatedAt;

  const ContextCardEntity({
    required this.id,
    required this.displayName,
    required this.role,
    required this.company,
    required this.bio,
    required this.tags,
    this.phone = '',
    required this.createdAt,
    required this.updatedAt,
  });

  // Linha de cargo/empresa para exibição compacta no cartão BLE
  String get occupationLine {
    if (role.isNotEmpty && company.isNotEmpty) return '$role · $company';
    if (role.isNotEmpty) return role;
    if (company.isNotEmpty) return company;
    return '';
  }

  // Primeira letra do nome para uso em avatares
  String get initial =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

  ContextCardEntity copyWith({
    String? id,
    String? displayName,
    String? role,
    String? company,
    String? bio,
    String? tags,
    String? phone,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ContextCardEntity(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        company: company ?? this.company,
        bio: bio ?? this.bio,
        tags: tags ?? this.tags,
        phone: phone ?? this.phone,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

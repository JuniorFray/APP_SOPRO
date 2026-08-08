// Entidade pura de domínio para um Ambiente (local físico com geofence).
// Não depende de nenhuma biblioteca externa — só Dart puro.
class EnvironmentEntity {
  // Identificador único gerado via UUID v4
  final String id;

  // Nome legível pelo usuário (ex: "Casa", "Trabalho")
  final String name;

  // Coordenadas do centro do geofence
  final double latitude;
  final double longitude;

  // Raio do geofence em metros
  final double radiusMeters;

  // Data de criação do registro
  final DateTime createdAt;

  // Marca o ambiente como Mercado (lista de compras no lugar dos gatilhos)
  final bool isMarket;

  // Caminho local da foto da plaquinha 3D deste ambiente (null → arte padrão).
  // Opcional para não quebrar construções existentes; nunca sai do dispositivo.
  final String? pinImagePath;

  // Dono da linha quando este ambiente é uma CÓPIA read-only compartilhada por
  // outro usuário (Fase 3). null = ambiente próprio. Guia a UI read-only.
  final String? ownerId;

  const EnvironmentEntity({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
    required this.isMarket,
    this.pinImagePath,
    this.ownerId,
  });

  // true = ambiente compartilhado por outro dono → geometria é somente leitura.
  bool get isShared => ownerId != null;
}

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

  const EnvironmentEntity({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
  });
}

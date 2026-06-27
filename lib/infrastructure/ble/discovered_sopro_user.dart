import '../../domain/entities/context_card_entity.dart';

// Representa um usuário Sopro detectado via BLE scan.
// Criado quando o scan encontra um dispositivo anunciando o SERVICE_UUID Sopro.
// O ContextCard é carregado sob demanda via GATT quando o usuário toca no item.
class DiscoveredSoproUser {
  // ID do dispositivo Bluetooth (MAC no Android, UUID no iOS)
  final String deviceId;

  // Nome exibido: vem do advertisement localName ou "Usuário Sopro" como fallback
  final String deviceName;

  // Intensidade do sinal em dBm — quanto mais próximo de 0, mais perto
  final int rssi;

  // Última vez que este dispositivo foi visto no scan
  final DateTime lastSeen;

  // ContextCard carregado via GATT; null enquanto não foi buscado
  final ContextCardEntity? card;

  const DiscoveredSoproUser({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    required this.lastSeen,
    this.card,
  });

  // Cria uma cópia com campos substituídos — necessário porque a classe é imutável
  DiscoveredSoproUser copyWith({
    String? deviceId,
    String? deviceName,
    int? rssi,
    DateTime? lastSeen,
    ContextCardEntity? card,
  }) {
    return DiscoveredSoproUser(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      card: card ?? this.card,
    );
  }

  // Classifica a intensidade do sinal para exibição (valores típicos Android)
  RssiLevel get rssiLevel {
    if (rssi >= -60) return RssiLevel.strong;   // < 3m
    if (rssi >= -80) return RssiLevel.medium;   // 3–10m
    return RssiLevel.weak;                       // > 10m
  }
}

// Nível de intensidade do sinal BLE para UI
enum RssiLevel { strong, medium, weak }

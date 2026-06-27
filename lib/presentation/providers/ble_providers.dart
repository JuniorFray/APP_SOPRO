import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/ble/ble_service.dart';
import '../../infrastructure/ble/discovered_sopro_user.dart';

// Provider singleton do BleService — compartilhado por toda a app.
// Descartado quando o ProviderScope é desmontado (ao fechar o app).
final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  // Garante que scan/advertising são parados e o stream é fechado ao descartar
  ref.onDispose(service.dispose);
  return service;
});

// Stream de usuários Sopro detectados pelo scan BLE.
// Emite lista vazia ao iniciar; atualiza conforme novos dispositivos são detectados.
// O scan é iniciado/parado pelo PeopleNearbyScreen via bleServiceProvider.
final nearbyUsersProvider = StreamProvider<List<DiscoveredSoproUser>>((ref) {
  return ref.watch(bleServiceProvider).devicesStream;
});

// Estado do advertising: true = BLE advertising atualmente ativo.
// Gerenciado pela PeopleNearbyScreen ao iniciar/parar o advertising.
final bleAdvertisingProvider = StateProvider<bool>((ref) => false);

// Preferência de visibilidade do usuário: true = quer ser visto por outros.
// Configurado na tela de Perfil. Respeitado pela PeopleNearbyScreen antes de iniciar advertising.
// Padrão: true (usuário visível quando abre "Pessoas Aqui").
final bleVisibleProvider = StateProvider<bool>((ref) => true);

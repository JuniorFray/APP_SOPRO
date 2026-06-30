import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provider que controla se notificações de gatilhos estão habilitadas.
// Valor inicial: true (ativado por padrão).
// Persistência: AppInitializer carrega o valor salvo em SharedPreferences
// ('notifications_enabled') durante a inicialização do app.
final notificationsEnabledProvider = StateProvider<bool>((ref) => true);

// Provider que controla se as notificações de trigger são emitidas com som.
// Valor inicial: true (com som). Persistência via SharedPreferences
// ('notification_sound_enabled'). Quando false, usa o canal silencioso.
final notificationSoundProvider = StateProvider<bool>((ref) => true);

// Provider que define o intervalo mínimo (em minutos) entre notificações.
// 0 = sem limite (sempre notifica). Persistência via SharedPreferences
// ('notification_cooldown_minutes'). Valores válidos: 0, 5, 15, 30, 60.
final notificationCooldownMinutesProvider = StateProvider<int>((ref) => 0);

// Provider para o nível de potência de transmissão BLE do advertising.
// 0=ULTRA_LOW (~2m), 1=LOW (~5m, padrão), 2=MEDIUM (~10m), 3=HIGH (~20m+).
// Mapeado para AdvertiseSettings.ADVERTISE_TX_POWER_* no Android via MethodChannel.
// Persistência via SharedPreferences ('ble_tx_power').
final bleTxPowerProvider = StateProvider<int>((ref) => 1);

// Provider que controla se o telefone/WhatsApp é incluído no payload BLE.
// Se false, o campo phone é omitido do cartão trocado mesmo que esteja
// preenchido no perfil — o usuário pode ter o número salvo sem compartilhá-lo.
// Persistência via SharedPreferences ('share_whatsapp').
final shareWhatsAppProvider = StateProvider<bool>((ref) => true);

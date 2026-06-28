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

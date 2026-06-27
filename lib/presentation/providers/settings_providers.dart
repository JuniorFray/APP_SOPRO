import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provider que controla se notificações de gatilhos estão habilitadas.
// Valor inicial: true (ativado por padrão).
// Persistência: AppInitializer carrega o valor salvo em SharedPreferences
// ('notifications_enabled') durante a inicialização do app.
// SettingsScreen salva em SharedPreferences quando o usuário altera o toggle.
final notificationsEnabledProvider = StateProvider<bool>((ref) => true);

import 'package:shared_preferences/shared_preferences.dart';

// Nome de exibição do usuário (personalização — Fase 3).
//
// Independente de conta: capturado no onboarding (opcional) e salvo local em
// SharedPreferences. Se o usuário criar conta depois, o mesmo nome sobe pro
// profiles.name no signup. A persona (behavior_engine) lê o cache em RAM de
// forma síncrona — por isso o valor é hidratado uma vez no startup (AppInitializer).
//
// Chave Dart 'user_display_name' → chave nativa 'flutter.user_display_name'
// (prefixo aplicado pelo plugin), acessível ao lado nativo no futuro se preciso.
class UserNameStore {
  UserNameStore._();

  static const prefKey = 'user_display_name';

  // Cache em RAM (null = sem nome). Lido pela persona sem await.
  static String? current;

  // Hidrata o cache a partir de um SharedPreferences já aberto (startup).
  static void hydrate(SharedPreferences prefs) {
    current = _clean(prefs.getString(prefKey));
  }

  // Carrega do disco (quando não há prefs em mãos).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    hydrate(prefs);
  }

  // Salva (ou limpa, se vazio) o nome. Atualiza o cache imediatamente.
  static Future<void> save(String? name) async {
    final cleaned = _clean(name);
    current = cleaned;
    final prefs = await SharedPreferences.getInstance();
    if (cleaned == null) {
      await prefs.remove(prefKey);
    } else {
      await prefs.setString(prefKey, cleaned);
    }
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

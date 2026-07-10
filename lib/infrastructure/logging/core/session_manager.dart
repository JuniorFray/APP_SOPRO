import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Gerencia dois identificadores de ciclo de vida com garantias distintas:
//
//   installation_id — UUID v4 gerado na PRIMEIRA execução do app e persistido
//                     em SharedPreferences com a chave 'logger_device_id'.
//                     • Permanece inalterado entre sessões, upgrades e reboots.
//                     • Nunca é removido por fluxos normais do aplicativo.
//                     • Compatível com o AppLogger legado (mesma chave).
//
//   session_id      — UUID v4 gerado a cada chamada a init() (início do app).
//                     • Vive apenas em memória: nunca é persistido.
//                     • Muda a cada abertura — permite isolar eventos por sessão.
//                     • Nunca reutilizado entre execuções.
//
// Thread safety (modelo Dart):
//   Dart executa em um único thread por isolate, mas operações async podem
//   ser intercaladas. O padrão _initFuture garante que apenas uma execução de
//   _doInit() aconteça por ciclo de vida do isolate, mesmo que init() seja
//   chamado por múltiplos locais antes de completar.
//
// Uso:
//   await SessionManager.init();          // uma vez no AppLogger.init()
//   SessionManager.installationId;        // UUID estável
//   SessionManager.sessionId;             // UUID da sessão corrente
class SessionManager {
  SessionManager._();

  // Chave SharedPreferences mantida igual ao AppLogger legado para não perder
  // o installation_id de instalações já existentes.
  static const _installationIdKey = 'logger_device_id';
  static const _uuid = Uuid();

  static String? _installationId;
  static String? _sessionId;

  // Armazena o Future em andamento para evitar inicialização dupla.
  // Chamadas concorrentes a init() recebem o mesmo Future e aguardam juntas.
  static Future<void>? _initFuture;

  // UUID estável por instalação. Retorna '' se init() não foi chamado.
  static String get installationId => _installationId ?? '';

  // UUID efêmero por sessão. Retorna '' se init() não foi chamado.
  static String get sessionId => _sessionId ?? '';

  // Indica se a inicialização foi concluída ao menos uma vez.
  static bool get isInitialized =>
      _installationId != null && _sessionId != null;

  // Inicializa ambos os identificadores.
  // Chamadas simultâneas antes da conclusão aguardam o mesmo Future —
  // nunca produzem dois installation_ids diferentes.
  // Deve ser chamado uma única vez no início do app (AppLogger.init()).
  static Future<void> init() => _initFuture ??= _doInit();

  static Future<void> _doInit() async {
    // session_id é sempre gerado antes de qualquer await para garantir que
    // o valor seja atribuído no início desta execução.
    _sessionId = _uuid.v4();

    final prefs = await SharedPreferences.getInstance();
    _installationId = prefs.getString(_installationIdKey);
    if (_installationId == null) {
      _installationId = _uuid.v4();
      await prefs.setString(_installationIdKey, _installationId!);
    }
  }
}

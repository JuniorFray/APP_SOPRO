import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Responsável por dois identificadores de ciclo de vida distintos:
//
//   installation_id — UUID v4 gerado na primeira execução do app e persistido
//                     em SharedPreferences. Permanece inalterado entre sessões,
//                     upgrades e reboots. Nunca é removido por fluxos normais.
//
//   session_id      — UUID v4 gerado a cada abertura do app (em memória).
//                     Permite correlacionar eventos dentro de uma única sessão
//                     sem cruzar dados de sessões anteriores.
//
// A chave 'logger_device_id' é mantida compatível com o AppLogger legado para
// não perder o installation_id de instalações já existentes.
class SessionManager {
  SessionManager._();

  static const _installationIdKey = 'logger_device_id';
  static const _uuid = Uuid();

  static String? _installationId;
  static String? _sessionId;

  // UUID estável por instalação. Retorna '' antes de init().
  static String get installationId => _installationId ?? '';

  // UUID efêmero por sessão. Retorna '' antes de init().
  static String get sessionId => _sessionId ?? '';

  // Inicializa ambos os identificadores.
  // Deve ser chamado uma única vez no início do app (AppLogger.init()).
  static Future<void> init() async {
    _sessionId = _uuid.v4();

    final prefs = await SharedPreferences.getInstance();
    _installationId = prefs.getString(_installationIdKey);
    if (_installationId == null) {
      _installationId = _uuid.v4();
      await prefs.setString(_installationIdKey, _installationId!);
    }
  }
}

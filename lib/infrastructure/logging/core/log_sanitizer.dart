import 'logger_configuration.dart';

// Aplica mascaramento automático sobre payloads de log para proteger dados
// sensíveis antes de qualquer saída (console, Supabase, etc.).
//
// Estratégia em duas camadas:
//   1. Por nome de chave — chaves com nomes sensíveis têm o valor substituído
//      por '[REDACTED]' ou '[LOCATION]', independentemente do conteúdo.
//   2. Por conteúdo de valor — strings são varridas por regex que detectam
//      tokens, e-mails, CPFs, telefones, JWTs e Bearer tokens.
//
// Isenções em modo debug (LoggerConfiguration.debugLogging == true):
//   As chaves abaixo NÃO são mascaradas para permitir diagnóstico de voz/NLU:
//     transcript, environment_name, gemini_response, intent, speech_result
class LogSanitizer {
  LogSanitizer._();

  // Chaves isentas de mascaramento quando debugLogging está ativo.
  static const _debugExemptKeys = {
    'transcript',
    'environment_name',
    'gemini_response',
    'intent',
    'speech_result',
  };

  // Chaves cujo valor deve ser completamente ocultado.
  static final _sensitiveKeyPattern = RegExp(
    r'^(?:authorization|apikey|api_key|token|bearer|password|senha|'
    r'cookie|secret|private_key|access_key|refresh_token|'
    r'supabase_key|gemini_key)$',
    caseSensitive: false,
  );

  // Chaves que contêm coordenadas geográficas.
  static final _locationKeyPattern = RegExp(
    r'lat(?:itude)?|lon(?:gitude)?|lng',
    caseSensitive: false,
  );

  // JWT compacto (header.payload.signature em base64url).
  static final _jwtPattern = RegExp(
    r'eyJ[\w\-]+\.eyJ[\w\-]+\.[\w\-]+',
  );

  // Bearer token em valores de string.
  static final _bearerPattern = RegExp(
    r'Bearer\s+\S+',
    caseSensitive: false,
  );

  // Endereço de e-mail.
  static final _emailPattern = RegExp(
    r'\b[\w.\-]+@[\w.\-]+\.\w{2,}\b',
  );

  // CPF no formato XXX.XXX.XXX-XX.
  static final _cpfPattern = RegExp(
    r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b',
  );

  // Telefone brasileiro (com ou sem DDD, com ou sem +55).
  static final _phonePattern = RegExp(
    r'\b(?:\+55\s?)?(?:\(?\d{2}\)?[\s\-]?)(?:9\s?)?\d{4}[\-\s]?\d{4}\b',
  );

  // Aplica sanitização ao payload. Retorna cópia sanitizada.
  // Se enableDataMasking == false, retorna o mapa original sem alterações.
  static Map<String, dynamic> sanitize(Map<String, dynamic> payload) {
    if (!LoggerConfiguration.enableDataMasking) return payload;
    return _sanitizeMap(payload);
  }

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      // Isenção de depuração: chaves diagnósticas não são mascaradas em debug.
      final isExempt = LoggerConfiguration.debugLogging &&
          _debugExemptKeys.contains(key.toLowerCase());
      if (isExempt) return MapEntry(key, value);

      // Mascaramento por nome de chave sensível.
      if (_sensitiveKeyPattern.hasMatch(key.toLowerCase())) {
        return MapEntry(key, '[REDACTED]');
      }

      // Mascaramento de coordenadas geográficas.
      if (_locationKeyPattern.hasMatch(key)) {
        return MapEntry(key, '[LOCATION]');
      }

      return MapEntry(key, _sanitizeValue(value));
    });
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value is String) return _sanitizeString(value);
    if (value is Map<String, dynamic>) return _sanitizeMap(value);
    if (value is List) return value.map(_sanitizeValue).toList();
    return value;
  }

  static String _sanitizeString(String value) {
    var result = value;
    result = result.replaceAll(_jwtPattern, '[JWT]');
    result = result.replaceAll(_bearerPattern, 'Bearer [REDACTED]');
    result = result.replaceAll(_emailPattern, '[EMAIL]');
    result = result.replaceAll(_cpfPattern, '[CPF]');
    result = result.replaceAll(_phonePattern, '[PHONE]');
    return result;
  }
}

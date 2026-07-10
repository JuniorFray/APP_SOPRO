import 'logger_configuration.dart';

// Aplica mascaramento automático sobre payloads de log antes de qualquer saída
// (console, Supabase, arquivo, etc.).
//
// ── Estratégia de mascaramento (duas camadas) ─────────────────────────────
//
//   Camada 1 — Por nome de chave:
//     Chaves reconhecidas como sensíveis têm o valor substituído por
//     '[REDACTED]' ou '[LOCATION]', independentemente do conteúdo.
//     Exemplos: "token", "password", "lat", "user_id".
//
//   Camada 2 — Por conteúdo de valor (regex):
//     Strings são varridas por padrões que detectam JWTs, Bearer tokens,
//     e-mails, CPFs, telefones brasileiros e URLs com query params sensíveis.
//     Aplicada recursivamente em Maps aninhados e itens de List.
//
// ── Sanitização recursiva ─────────────────────────────────────────────────
//   _sanitizeMap  → processa cada entrada; chama _sanitizeValue por valor
//   _sanitizeValue → despacha para String, Map ou List
//   _sanitizeString → aplica todos os padrões regex em ordem
//   _sanitizeMap  (recursão em Maps aninhados)
//   _sanitizeValue (recursão em listas heterogêneas)
//
// ── Isenções em modo debug ────────────────────────────────────────────────
//   Quando LoggerConfiguration.debugLogging == true, as chaves abaixo NÃO
//   são mascaradas — necessárias para diagnóstico de voz e NLU:
//     transcript, environment_name, gemini_response, intent, speech_result
//   TODOS os demais campos continuam mascarados mesmo em debug.
class LogSanitizer {
  LogSanitizer._();

  // ── Chaves isentas (somente em debug) ────────────────────────────────────

  static const _debugExemptKeys = {
    'transcript',
    'environment_name',
    'gemini_response',
    'intent',
    'speech_result',
  };

  // ── Padrões de nome de chave sensível ────────────────────────────────────

  // Chaves cujo valor inteiro deve ser ocultado com '[REDACTED]'.
  // Usa full-string match via ^...$ para evitar falsos positivos em nomes
  // compostos (ex.: "custom_token_count" não deve ser mascarado).
  static final _sensitiveKeyPattern = RegExp(
    r'^(?:authorization|apikey|api_key|token|bearer|password|senha|'
    r'cookie|secret|private_key|access_key|refresh_token|'
    r'supabase_key|gemini_key|user_id|uid|account_id|profile_id|person_id)$',
    caseSensitive: false,
  );

  // Chaves que contêm coordenadas geográficas → substituídas por '[LOCATION]'.
  // Word boundaries (\b) evitam falsos positivos em keys como "platform"
  // (contém "lat"?) ou "relations" (contém "lat" via "re-lat-ions").
  // Sem \b, hasMatch("platform") retornaria true incorretamente.
  static final _locationKeyPattern = RegExp(
    r'\blat(?:itude)?\b|\blon(?:gitude)?\b|\blng\b',
    caseSensitive: false,
  );

  // ── Padrões de conteúdo de valor ─────────────────────────────────────────

  // JWT compacto: três segmentos base64url separados por ponto.
  // O prefixo "eyJ" é característico do header JSON codificado.
  static final _jwtPattern = RegExp(
    r'eyJ[\w\-]+\.eyJ[\w\-]+\.[\w\-]+',
  );

  // Bearer token em qualquer header ou valor de string.
  static final _bearerPattern = RegExp(
    r'Bearer\s+\S+',
    caseSensitive: false,
  );

  // Endereço de e-mail (padrão RFC 5321 simplificado).
  static final _emailPattern = RegExp(
    r'\b[\w.\-]+@[\w.\-]+\.\w{2,}\b',
  );

  // CPF no formato canônico XXX.XXX.XXX-XX.
  // Não mascara sequências de 11 dígitos sem pontuação para evitar falsos
  // positivos em IDs, timestamps e contadores.
  static final _cpfPattern = RegExp(
    r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b',
  );

  // Telefone brasileiro: +55 opcional, DDD entre parênteses opcional,
  // 8 ou 9 dígitos com separadores opcionais.
  static final _phonePattern = RegExp(
    r'\b(?:\+55\s?)?(?:\(?\d{2}\)?[\s\-]?)(?:9\s?)?\d{4}[\-\s]?\d{4}\b',
  );

  // Query parameters sensíveis em URLs.
  // Captura o nome do parâmetro (grupo 1) para reescrever apenas o valor.
  // Exemplo: "?token=abc123"   → "?token=[REDACTED]"
  //          "&api_key=xyz"    → "&api_key=[REDACTED]"
  // Interrompe no próximo separador de query (&), espaço ou fim de linha.
  static final _urlTokenPattern = RegExp(
    r'([?&](?:token|api_key|apikey|access_token|key|secret|auth|authorization|bearer)=)[^&\s]+',
    caseSensitive: false,
  );

  // ── API pública ───────────────────────────────────────────────────────────

  // Aplica sanitização ao payload. Retorna uma cópia sanitizada.
  // Se enableDataMasking == false, retorna o mapa original sem cópia.
  static Map<String, dynamic> sanitize(Map<String, dynamic> payload) {
    if (!LoggerConfiguration.enableDataMasking) return payload;
    return _sanitizeMap(payload);
  }

  // ── Implementação interna ─────────────────────────────────────────────────

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      // Isenção de diagnóstico: aplica somente quando debugLogging está ativo.
      final isExempt = LoggerConfiguration.debugLogging &&
          _debugExemptKeys.contains(key.toLowerCase());
      if (isExempt) return MapEntry(key, value);

      // Camada 1a: chave identificada como sensível → oculta valor inteiro.
      if (_sensitiveKeyPattern.hasMatch(key.toLowerCase())) {
        return MapEntry(key, '[REDACTED]');
      }

      // Camada 1b: chave de coordenada geográfica → placeholder de localização.
      if (_locationKeyPattern.hasMatch(key)) {
        return MapEntry(key, '[LOCATION]');
      }

      // Camada 2: inspeciona o conteúdo do valor (recursivo para Maps e Lists).
      return MapEntry(key, _sanitizeValue(value));
    });
  }

  // Despacha para o sanitizador correto conforme o tipo do valor.
  // Garante sanitização recursiva em toda a hierarquia do payload.
  static dynamic _sanitizeValue(dynamic value) {
    if (value is String) return _sanitizeString(value);
    if (value is Map<String, dynamic>) return _sanitizeMap(value);
    if (value is Map) {
      // Fallback para Map com tipos dinâmicos (ex.: Map<dynamic, dynamic>).
      return _sanitizeMap(value.cast<String, dynamic>());
    }
    if (value is List) {
      return value.map(_sanitizeValue).toList();
    }
    return value;
  }

  // Aplica todos os padrões regex em ordem sobre um valor string.
  // A ordem importa: JWT e Bearer são detectados antes de padrões menores.
  static String _sanitizeString(String value) {
    var result = value;
    result = result.replaceAll(_jwtPattern, '[JWT]');
    result = result.replaceAll(_bearerPattern, 'Bearer [REDACTED]');
    result = result.replaceAllMapped(
      _urlTokenPattern,
      (m) => '${m.group(1)}[REDACTED]',
    );
    result = result.replaceAll(_emailPattern, '[EMAIL]');
    result = result.replaceAll(_cpfPattern, '[CPF]');
    result = result.replaceAll(_phonePattern, '[PHONE]');
    return result;
  }
}

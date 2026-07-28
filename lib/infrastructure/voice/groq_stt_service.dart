// STT na nuvem via Groq (endpoint compativel com OpenAI Whisper).
//
// Decisao de produto: a voz deixa de ser 100% on-device. O STT tenta a NUVEM
// primeiro (mais rapido e preciso) e cai automaticamente no Whisper LOCAL
// (SherpaSttService, sherpa-onnx) quando nao ha internet ou a nuvem falha.
// Este servico NAO faz retry nem fallback: em qualquer indisponibilidade lanca
// [GroqUnavailableException] para o CHAMADOR (VoiceService) decidir o fallback.
//
// Modelo: whisper-large-v3-turbo (barato: US$0,04/h, 228x tempo real). pt-BR.
// Envia o WAV como multipart/form-data usando dart:io HttpClient — mesmo padrao
// HTTP do resto do VoiceService, sem adicionar dependencia (pacote http).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // BytesBuilder (evita import indireto deprecado via dart:io)

import 'package:sopro/core/constants/app_constants.dart';
import 'package:sopro/infrastructure/logging/core/logger.dart';

// Lancada quando a transcricao na nuvem nao pode ser concluida por
// indisponibilidade: sem chave, sem internet, timeout, erro de servidor (>=500)
// ou qualquer status != 200. O chamador captura e cai no Whisper local.
// [reason] e um rotulo curto para log (no_key, timeout, socket, http_500...).
class GroqUnavailableException implements Exception {
  final String reason;
  const GroqUnavailableException(this.reason);
  @override
  String toString() => 'GroqUnavailableException($reason)';
}

class GroqSttService {
  // Endpoint de transcricao de audio da Groq (OpenAI-compatible).
  static const _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const _model = 'whisper-large-v3-turbo';
  // Timeout curto e explicito: se a nuvem nao responde rapido, cair pro local
  // e melhor UX do que esperar. Cobre connect + a chamada inteira.
  static const _timeout = Duration(seconds: 10);

  // Transcreve [wavFilePath] via Groq. Retorna o texto (pt-BR) ou null quando a
  // resposta vem vazia (nada falado). Lanca [GroqUnavailableException] em
  // qualquer falha de rede/servidor — o chamador faz o fallback local.
  Future<String?> transcribe(String wavFilePath) async {
    final key = AppConstants.groqApiKey;
    if (key.isEmpty) throw const GroqUnavailableException('no_key');

    final file = File(wavFilePath);
    if (!await file.exists()) {
      throw const GroqUnavailableException('file_missing');
    }
    final wavBytes = await file.readAsBytes();
    if (wavBytes.isEmpty) throw const GroqUnavailableException('empty_file');

    final sw = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      // Corpo multipart/form-data montado a mao (sem dependencia extra).
      final boundary = '----soproGroq${DateTime.now().microsecondsSinceEpoch}';
      final body = _multipartBody(boundary, wavBytes);

      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.headers.contentType = ContentType(
          'multipart', 'form-data',
          parameters: {'boundary': boundary});
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close().timeout(_timeout);
      final status = response.statusCode;
      final respBody = await response.transform(utf8.decoder).join();

      if (status != 200) {
        // 5xx (servidor) e 4xx (ex. chave invalida) → indisponivel: melhor cair
        // pro local do que falhar o comando do usuario. Nao logamos o corpo.
        Logger.warn('groq_stt_http',
            payload: {'status': status, 'ms': sw.elapsedMilliseconds},
            feature: 'voice', action: 'groq_stt');
        throw GroqUnavailableException('http_$status');
      }

      // response_format=text → corpo e o texto puro da transcricao. Privacidade:
      // logamos so duracao e tamanho, nunca o texto transcrito.
      final transcript = respBody.trim();
      Logger.info('groq_stt_ok',
          payload: {'ms': sw.elapsedMilliseconds, 'len': transcript.length},
          feature: 'voice', action: 'groq_stt',
          durationMs: sw.elapsedMilliseconds);
      return transcript.isEmpty ? null : transcript;
    } on GroqUnavailableException {
      rethrow; // ja e a nossa excecao — nao reembrulha
    } on TimeoutException {
      Logger.warn('groq_stt_timeout',
          payload: {'ms': sw.elapsedMilliseconds},
          feature: 'voice', action: 'groq_stt');
      throw const GroqUnavailableException('timeout');
    } on SocketException {
      // Sem conectividade (modo aviao etc.) — o caso classico de fallback.
      Logger.info('groq_stt_offline',
          payload: {'ms': sw.elapsedMilliseconds},
          feature: 'voice', action: 'groq_stt');
      throw const GroqUnavailableException('socket');
    } on HttpException {
      throw const GroqUnavailableException('http_exception');
    } finally {
      client.close();
    }
  }

  // Serializa os campos (model/language/response_format) + o arquivo WAV no
  // formato multipart/form-data. Retorna os bytes prontos para o corpo do POST.
  List<int> _multipartBody(String boundary, List<int> wavBytes) {
    final b = BytesBuilder();
    void field(String name, String value) {
      b.add(utf8.encode('--$boundary\r\n'));
      b.add(utf8.encode(
          'Content-Disposition: form-data; name="$name"\r\n\r\n'));
      b.add(utf8.encode('$value\r\n'));
    }

    field('model', _model);
    field('language', 'pt');
    field('response_format', 'text');
    // Parte do arquivo (WAV bruto).
    b.add(utf8.encode('--$boundary\r\n'));
    b.add(utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n'));
    b.add(utf8.encode('Content-Type: audio/wav\r\n\r\n'));
    b.add(wavBytes);
    b.add(utf8.encode('\r\n'));
    b.add(utf8.encode('--$boundary--\r\n'));
    return b.takeBytes();
  }
}

// HomeScreen — Tela principal do Sopro.
//
// Responsabilidades:
//   1. Verificar primeiro acesso via SharedPreferences ('onboarding_done'):
//      - false → pushReplacementNamed('/onboarding') — sem await, sem recursão
//      - true  → inicia geofences e exibe a tela normalmente
//   2. Listar ambientes cadastrados pelo usuário
//   3. FAB de voz: _VoiceFab — botão 64 dp hold-to-record que auto-executa ações
//      via Gemini Audio API sem nenhuma confirmação manual (estilo WhatsApp)
//   4. FAB principal: "Novo Ambiente"
//   5. AppBar: BLE Social, Perfil, Configurações

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../domain/entities/trigger_entity.dart';
import '../../../infrastructure/location/location_guard.dart';
import '../../../infrastructure/logging/app_logger.dart';
import '../../widgets/device_requirements_guard.dart';
import '../../../infrastructure/voice/voice_service.dart';
import '../../../infrastructure/voice/execution_plan.dart';
import '../../../infrastructure/voice/voice_action_executor.dart';
import '../../../infrastructure/voice/conversation_context.dart';
import '../../../infrastructure/voice/location_source_resolver.dart';
import '../../../infrastructure/geocoding/geocoding_repository.dart';
import '../../../infrastructure/geocoding/geocoding_platform_interface.dart';
import '../../../infrastructure/geocoding/location_ranker.dart';
import '../../../infrastructure/geocoding/query_normalizer.dart';
import '../../providers/database_provider.dart';
import '../../providers/environment_providers.dart';
import '../../providers/trigger_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/environment_card.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_primary_button.dart';
import '../../widgets/sopro_text_field.dart';
import '../ble/people_nearby_screen.dart';
import '../environment/add_environment_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // false enquanto verifica o flag de onboarding e inicia serviços
  bool _ready = false;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Invalida o provider ao voltar ao foreground — garante que ambientes/triggers
    // criados pelo botão flutuante (SQLite direto) apareçam sem reiniciar o app.
    _lifecycleListener = AppLifecycleListener(
      onResume: () async {
        final prefs = await SharedPreferences.getInstance();
        final needsRefresh = prefs.getBool('needs_refresh') ?? false;
        if (needsRefresh) {
          await prefs.setBool('needs_refresh', false);
        }
        ref.invalidate(environmentsProvider);
        ref.invalidate(triggersByEnvironmentProvider);

        // Sprint F3-3 — ambiente criado por voz sem coords (FloatingVoiceService).
        // Abre a AddEnvironmentScreen em modo só-localização. Limpa o pending antes
        // de navegar para não reabrir no próximo resume.
        final pendingEnvId = prefs.getString('pending_location_env_id');
        if (pendingEnvId != null) {
          final pendingEnvName = prefs.getString('pending_location_env_name');
          await prefs.remove('pending_location_env_id');
          await prefs.remove('pending_location_env_name');
          if (mounted) {
            pushScreen(
              context,
              AddEnvironmentScreen(
                pendingEnvironmentId: pendingEnvId,
                pendingEnvironmentName: pendingEnvName,
              ),
            );
          }
        }
      },
    );
    // Executa depois do primeiro frame para que o Navigator esteja disponível
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnboarding());
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  // Verifica se o onboarding já foi concluído pelo usuário.
  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;

    if (!onboardingDone) {
      // Substitui HomeScreen pelo onboarding no primeiro acesso
      Navigator.pushReplacementNamed(context, '/onboarding');
      return;
    }

    // Verifica requisitos do dispositivo antes de iniciar funcionalidades
    if (mounted) await DeviceRequirementsGuard.check(context, ref);
    if (!mounted) return;

    // Onboarding concluído: inicia geofences com permissões já concedidas
    await ref.read(geofenceManagerProvider).start();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // Exibe loading enquanto verifica SharedPreferences / inicia geofences
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2.5,
            strokeCap: StrokeCap.round,
          ),
        ),
      );
    }

    final environmentsAsync = ref.watch(environmentsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Liquid Glass — conteúdo que rola sob a AppBar aparece desfocado.
        // Delega ao primitivo central GlassSurface (identidade única do app).
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
        // tracking 0.8 = identidade de marca Sopro
        title: const Text(
          AppStrings.homeTitle,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => pushScreen(context, const PeopleNearbyScreen()),
            icon: const Icon(Icons.people_outline, color: AppColors.appBarButtonIcon),
            tooltip: AppStrings.peopleNearby,
            style: ButtonStyle(
              backgroundColor: const WidgetStatePropertyAll(AppColors.appBarButtonBg),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border, width: 0.5),
              )),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.person_outline, color: AppColors.appBarButtonIcon),
            tooltip: AppStrings.profileTooltip,
            style: ButtonStyle(
              backgroundColor: const WidgetStatePropertyAll(AppColors.appBarButtonBg),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border, width: 0.5),
              )),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => pushScreen(context, const SettingsScreen()),
            icon: const Icon(Icons.settings_outlined, color: AppColors.appBarButtonIcon),
            tooltip: AppStrings.settingsTooltip,
            style: ButtonStyle(
              backgroundColor: const WidgetStatePropertyAll(AppColors.appBarButtonBg),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border, width: 0.5),
              )),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: environmentsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2.5,
            strokeCap: StrokeCap.round,
          ),
        ),
        error: (e, _) => Center(
          child: Text(
            AppStrings.errorGeneric,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        data: (environments) => environments.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, 160),
                itemCount: environments.length,
                itemBuilder: (_, i) =>
                    EnvironmentCard(environment: environments[i]),
              ),
      ),
      // FABs empilhados: microfone (hold-to-record) acima do botão principal
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // FAB de voz redesenhado — 72 dp, hold=gravar, arrastar=cancelar
          const _VoiceFab(),
          const SizedBox(height: AppSpacing.md),
          // Botão "Novo Ambiente" — gradiente pink-red premium
          GestureDetector(
            onTap: () => pushScreen(context, const AddEnvironmentScreen()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF6178), Color(0xFFF04666)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.button),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40FF4566),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.newEnvironment,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Estados do botão de voz ────────────────────────────────────────────────────

enum _FabState {
  idle,       // mic parado, aguardando pressão
  recording,  // gravando áudio (vermelho pulsante)
  processing, // Gemini processando + executando ação
  success,    // checkmark verde por 1 s após sucesso
  error,      // mic_off vermelho breve após falha de permissão
}

// Fase 1 — descreve uma confirmação por voz pendente.
// [question] é a pergunta falada; [onYes] é executado somente se o usuário
// responder afirmativamente na gravação seguinte. Imutável e efêmero (RAM).
class _VoiceConfirmRequest {
  final String question;
  final Future<void> Function() onYes;
  const _VoiceConfirmRequest({required this.question, required this.onYes});
}

// Resolução Inteligente de Localização — etapa da conversa de criação de ambiente
// que a PRÓXIMA gravação vai responder. Efêmero (RAM), como _VoiceConfirmRequest.
enum _EnvTurn {
  confirmGps,     // "usar sua localização atual?" → sim/não
  askAddress,     // "qual o endereço?" → texto ditado
  askSpecifier,   // "qual mercado?" → texto ditado (categoria genérica)
  choosePlace,    // vários resultados → usuário escolhe um
  confirmPlace,   // 1 resultado forte → "você quis dizer X?" → sim/não
}

// Estado da resolução de localização pendente. [name] é o ambiente sendo criado;
// [candidates] só é usado nas etapas choosePlace/confirmPlace.
class _EnvLocationPending {
  final String name;
  final _EnvTurn turn;
  final List<GeocodingResult> candidates;
  const _EnvLocationPending({
    required this.name,
    required this.turn,
    this.candidates = const [],
  });
}

// ── Botão de voz flutuante (WhatsApp-style) ───────────────────────────────────
//
// - SEGURAR: inicia gravação (vermelho pulsante + contador de segundos)
// - ARRASTAR PARA CIMA > 60 dp: exibe lixeira vermelha → soltar cancela
// - SOLTAR (sem cancelar): para gravação → Gemini Audio API → auto-executa
// - Sem nenhuma confirmação manual — ação é executada imediatamente
class _VoiceFab extends ConsumerStatefulWidget {
  const _VoiceFab();

  @override
  ConsumerState<_VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends ConsumerState<_VoiceFab>
    with SingleTickerProviderStateMixin {

  _FabState _fabState = _FabState.idle;

  // Animação de pulso durante gravação: escala 1.0 ↔ 1.12 em 700 ms
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // Contador de segundos exibido durante gravação
  int    _recordingSeconds = 0;
  Timer? _recordingTimer;
  // Teto de SEGURANÇA (não é VAD): em hold-to-talk o dedo controla o fim, mas se
  // o botão ficar preso encerra após 60 s para não deixar o mic aberto. Alto o
  // suficiente para não cortar frases longas (Regra 4).
  static const _maxSeconds = 60;

  // Subscription ao stream de auto-stop do VoiceService (silêncio / max duration)
  StreamSubscription<void>? _autoStopSub;

  // Momento em que o dedo pressionou o botão — usado para verificar mínimo de 500 ms
  DateTime? _pressStartTime;

  // BUG 4 (temporário) — cronômetro do pipeline inteiro (captura→execução→TTS).
  // Iniciado em _stopAndProcess, lido em _executePlan para total_duration_ms.
  Stopwatch? _pipelineSw;

  // Canal de comunicação com o FloatingVoiceService (overlay nativo)
  static const _overlayChannel = MethodChannel('com.sopro.sopro/overlay');

  // FIX 4: quando true, a próxima gravação captura o nome do ambiente.
  // Ativado por _handleOpenEnvironment quando Gemini não retorna environmentName.
  bool _pendingEnvCreate = false;

  // Fase 1 — confirmação por voz reutilizável.
  // Quando != null, o app fez uma pergunta de sim/não e aguarda a resposta falada.
  // A PRÓXIMA gravação NÃO é enviada como comando ao Gemini: é interpretada como
  // resposta de confirmação (sim → executa onYes; não/ambíguo → cancela).
  // Mantido em RAM (não persiste) — some se a tela for descartada.
  _VoiceConfirmRequest? _pendingConfirm;

  // Resolução Inteligente de Localização — quando != null, a próxima gravação
  // responde a uma pergunta da conversa de criação de ambiente (confirmar GPS,
  // ditar endereço, escolher estabelecimento). Efêmero (RAM), como _pendingConfirm.
  _EnvLocationPending? _envLocationPending;

  // Ações do plano (gatilhos etc.) que aguardam a criação do ambiente para rodar
  // no ambiente recém-criado — reutilizadas pelo executor SEM resolver GPS.
  // Efêmero (RAM); consumido em _finishEnvCreation.
  List<VoiceAction>? _pendingPostEnvActions;

  // Visual press feedback (0.96 scale) — revertido após 200 ms pelo timer
  bool   _isVisuallyPressed = false;
  Timer? _pressScaleTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Escuta auto-stop do VoiceService (silêncio de 1500 ms ou 10 s max).
    // O VoiceService cancela seus timers internos e sinaliza aqui — o FAB
    // chama _stopAndProcess() para buscar o arquivo e enviar ao Gemini.
    _autoStopSub = ref.read(voiceServiceProvider).onAutoStop.listen((_) {
      if (mounted && _isRecording) _stopAndProcess();
    });

    // Escuta o canal nativo: dois métodos possíveis.
    _overlayChannel.setMethodCallHandler((call) async {
      if (call.method == 'openVoiceFromOverlay' &&
          mounted && _fabState == _FabState.idle) {
        // FloatingVoiceService quer abrir o app e iniciar gravação
        _onPressStart();
      } else if (call.method == 'processPendingIntent') {
        // FloatingVoiceService deixou um pedido pendente (ex: create_environment)
        // que exige GPS — processado agora que o app está em foreground
        final json = call.arguments as String?;
        if (json != null && mounted) _handleServicePendingIntent(json);
      }
    });
  }

  @override
  void dispose() {
    _autoStopSub?.cancel();
    _overlayChannel.setMethodCallHandler(null); // cancela o listener ao sair da tela
    _pulseCtrl.dispose();
    _recordingTimer?.cancel();
    _pressScaleTimer?.cancel();
    // Garante que gravação seja cancelada se o widget for descartado durante uso
    ref.read(voiceServiceProvider).cancelRecording();
    super.dispose();
  }

  bool get _isRecording => _fabState == _FabState.recording;

  // ── Eventos de ponteiro (Listener — baixo nível, confiável no Android) ──────
  //
  // Listener usa eventos raw do sistema operacional (PointerDown / PointerUp),
  // sem nenhum threshold de tempo. Isso elimina a ambiguidade do GestureDetector
  // (onLongPressEnd não era disparado confiavelmente no Motorola G52 / Android 12).

  // Dedo toca o botão → inicia gravação imediatamente e registra o instante
  void _onPressStart() {
    if (_fabState != _FabState.idle) return;
    _pressStartTime = DateTime.now();
    setState(() {
      _isVisuallyPressed = true;
      _fabState           = _FabState.recording;
      _recordingSeconds   = 0;
    });
    // Reverte o scale de press após 200 ms (animação tátil breve)
    _pressScaleTimer?.cancel();
    _pressScaleTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _isVisuallyPressed = false);
    });
    _pulseCtrl.repeat(reverse: true);
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= _maxSeconds) { t.cancel(); _stopAndProcess(); }
    });
    _startRecording(); // dispara nativo async — falha reverte o estado
  }

  // Dedo levanta → verifica duração mínima (500 ms) antes de processar
  void _onPressEnd() {
    _pressScaleTimer?.cancel();
    if (mounted) setState(() => _isVisuallyPressed = false);
    if (!_isRecording) return;
    final elapsed = DateTime.now()
        .difference(_pressStartTime ?? DateTime.now())
        .inMilliseconds;
    if (elapsed < 500) {
      // Gravação muito curta — cancela e orienta o usuário
      _cancelRecording();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(AppStrings.voiceHoldLonger),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    _stopAndProcess();
  }

  // Evento de cancelamento do SO (ligação, notificação que roubou o foco, etc.)
  void _onPressCancel() {
    _pressScaleTimer?.cancel();
    if (mounted) setState(() => _isVisuallyPressed = false);
    _cancelRecording();
  }

  // ── Ciclo de gravação ──────────────────────────────────────────────────────

  // Ativa o microfone nativo (async). Estado e timer já foram configurados
  // em _onLongPressStart — este método só precisa lidar com falha de init.
  Future<void> _startRecording() async {
    final service = ref.read(voiceServiceProvider);
    // Sprint Unificação: hold-to-talk — o dedo é o único fim de gravação (sem VAD).
    final ok      = await service.startRecording(holdToTalk: true);
    if (!mounted) return;

    if (ok) {
      // Sucesso: se o usuário já soltou enquanto o mic iniciava,
      // _stopAndProcess() já foi chamado e o estado não é mais recording —
      // nesse caso a gravação real começa mas será parada no fluxo normal.
      return;
    }

    // Falha (permissão negada / hardware): reverte tudo
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    setState(() => _fabState = _FabState.error);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _fabState = _FabState.idle);
  }

  // Para gravação e envia áudio ao Gemini para processar + auto-executar
  Future<void> _stopAndProcess() async {
    if (!_isRecording) return;
    _pipelineSw = Stopwatch()..start(); // BUG 4 (temporário) — total do pipeline
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    if (!mounted) return;
    setState(() => _fabState = _FabState.processing);

    final service  = ref.read(voiceServiceProvider);
    final filePath = await service.stopRecording();
    if (!mounted) return;

    if (filePath == null) {
      // Gravação falhou silenciosamente (arquivo não criado)
      setState(() => _fabState = _FabState.idle);
      return;
    }

    // GATE DE ENVIO — DECISÃO ÚNICA antes de QUALQUER chamada ao Gemini (cobre
    // comando novo, confirmação sim/não e captura de nome). Gemini só é chamado
    // quando TODAS as condições do gate adaptativo forem verdadeiras:
    //   speechDetected == true  E  speechFrames >= mínimo  E  noiseFloor calibrado.
    // Caso contrário: bloqueia, encerra o fluxo e NUNCA chama o Gemini.
    final gSpeechDetected = service.speechDetected;
    final gSpeechFrames   = service.speechFrames;
    final gCalibrated     = service.noiseCalibrated;
    final shouldSend = gSpeechDetected &&
        gSpeechFrames >= VoiceService.minSpeechFramesRequired &&
        gCalibrated;
    if (!shouldSend) {
      _pendingConfirm     = null;
      _pendingEnvCreate   = false;
      _envLocationPending = null; // Resolução de Localização — não ouviu a resposta
      await _handleNoSpeech();
      return;
    }

    // Fase 1 — se há uma confirmação por voz pendente, esta gravação é a
    // resposta sim/não, não um comando novo. Desvia antes do fluxo do Gemini.
    if (_pendingConfirm != null) {
      await _resolveVoiceConfirmation(filePath);
      return;
    }

    // Resolução Inteligente de Localização — se há uma pergunta pendente da
    // conversa de criação de ambiente, esta gravação é a resposta (sim/não,
    // endereço ou escolha). Desvia antes do fluxo de comando do Gemini.
    if (_envLocationPending != null) {
      await _resolveEnvLocationTurn(filePath);
      return;
    }

    try {
      // 300 ms de feedback visual antes de chamar o Gemini
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      // CORRECAO 2: busca nomes dos ambientes antes de chamar o Gemini
      // para que o modelo retorne o nome EXATO como está no banco
      final envs     = await ref.read(environmentRepositoryProvider).getAll();
      final envNames = envs.map((e) => e.name).toList();
      // Fase 2.1 — IDs paralelos (mesma ordem) enviados ao Gemini junto do nome
      // para ele decidir reutilizar ambiente existente vs criar novo.
      final envIds   = envs.map((e) => e.id).toList();

      // Fluxo legado "aguardando nome do ambiente" (Fase 1): a gravação é o nome
      // ditado — transcreve (1 Gemini) e delega ao handler de criação por GPS.
      if (_pendingEnvCreate) {
        _pendingEnvCreate = false;
        final transcript = await service.transcribeAudio(filePath);
        if (!mounted) return;
        final envName = (transcript ?? '').trim();
        if (envName.isNotEmpty && !VoiceService.isInvalidTranscript(envName)) {
          await _handleOpenEnvironment(VoiceResult(
            intent:          VoiceIntent.createEnvironment,
            transcript:      envName,
            environmentName: envName,
          ));
        } else {
          await _handleNoSpeech();
        }
        return;
      }

      // Fase 2 — assistente: UMA chamada Gemini devolve resposta natural + plano
      // de ações + follow-up + atualizações de contexto.
      final ctx = ref.read(conversationContextProvider);
      // Contexto expirado (TTL) é descartado antes de reutilizar (não vaza p/ nova conversa)
      if (ctx.isExpired && !ctx.isEmpty) {
        ctx.clear();
        AppLogger.log('conversation_context_cleared', {'reason': 'ttl'});
      }
      final geminiSw = Stopwatch()..start(); // BUG 4 (temporário)
      final planRes0 = await service.processAudioAsPlan(
        filePath,
        existingEnvironments: envNames,
        existingEnvironmentIds: envIds, // Fase 2.1 — nome + ID (reutilizar vs criar)
        contextSummary: ctx.promptSummary(),
      );
      // BUG 4 (temporário) — latência isolada da chamada Gemini (Home).
      AppLogger.log('home_gemini_finished',
          {'surface': 'home', 'gemini_duration_ms': geminiSw.elapsedMilliseconds});
      if (!mounted) return;

      // TEMP: remover após auditoria do Place Search
      AppLogger.log('voice_transcript_received', {
        'surface':    'home',
        'transcript': planRes0.transcript,
      });

      // REGRA 4 / BUG 3 — 2ª PROTEÇÃO: NUNCA executa plano com transcrição
      // inválida (vazia, só espaços, "...", "00:00", só pontuação), mesmo que o
      // Gemini tenha alucinado ações a partir de ruído. Dupla proteção: gate de
      // energia (antes do Gemini) + esta validação (antes do ExecutionPlan).
      if (VoiceService.isInvalidTranscript(planRes0.transcript)) {
        AppLogger.log('execution_plan_blocked',
            {'surface': 'home', 'reason': 'invalid_transcript'});
        AppLogger.log('execution_plan_invalid_transcript',
            {'surface': 'home', 'transcript': planRes0.transcript});
        await _handleNoSpeech();
        return;
      }

      // BUG 12 — guarda de prioridade destrutiva (paridade com o Overlay).
      // Se a fala pede exclusão TOTAL de ambientes, força o plano correto ANTES
      // de qualquer ação construtiva vinda do Gemini.
      final planRes = _applyDestructivePriority(planRes0);

      // 2ª rede da guarda de vazio (o gate por amplitude já barra antes do Gemini)
      if (planRes.hasNothing &&
          VoiceService.isInvalidTranscript(planRes.transcript)) {
        await _handleNoSpeech();
        return;
      }

      // Retrocompatibilidade: resposta no schema antigo (intent) → fluxo Fase 1.
      if (planRes.plan.isEmpty && planRes.legacyResult != null) {
        await _executeResult(planRes.legacyResult!);
        return;
      }

      // Sem ações: só conversa (informação faltando / resposta natural / unknown).
      if (planRes.plan.isEmpty) {
        await _handleConversationalReply(planRes, ctx);
        return;
      }

      // Com ações: monta e executa o plano (confirma por voz se houver destrutiva).
      await _runAssistantPlan(planRes, ctx);
    } catch (e) {
      debugPrint('[_VoiceFab] Erro ao processar áudio: $e');
      if (mounted) {
        setState(() => _fabState = _FabState.error);
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) setState(() => _fabState = _FabState.idle);
      }
    }
  }

  // Cancela gravação sem processar (usuário arrastou para cima ou evento cancelado)
  void _cancelRecording() {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    ref.read(voiceServiceProvider).cancelRecording();
    if (mounted) {
      setState(() => _fabState = _FabState.idle);
    }
  }

  // Exibe checkmark verde por 1 s e volta ao estado idle
  Future<void> _setSuccess() async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.success);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _fabState = _FabState.idle);
  }

  // Fala [text] via TTS se o toggle "Responder com áudio" estiver ativo.
  // Respeita a velocidade configurada pelo usuário. Falha silenciosa.
  Future<void> _speak(String text) async {
    if (!ref.read(voiceAudioResponseProvider)) return;
    final rate = ref.read(voiceSpeechRateProvider);
    try {
      await ref.read(voiceServiceProvider).speak(text, rate: rate);
    } catch (e) {
      debugPrint('[_VoiceFab] TTS erro: $e');
    }
  }

  // Exclui trigger, loga no Supabase, exibe snackbar e fala a confirmação.
  // Usado por _handleDeleteTrigger em qualquer variante (1 resultado ou picker).
  Future<void> _deleteTriggerDirectly(TriggerEntity t) async {
    // Reseta o FAB (pode vir do estado "processing" da confirmação por voz)
    if (mounted && _fabState != _FabState.idle) {
      setState(() => _fabState = _FabState.idle);
    }
    await ref.read(triggerRepositoryProvider).delete(t.id);
    AppLogger.log('voice_delete', {
      'intent':        'delete_trigger',
      'trigger_title': t.title,
      'environment':   null,
      'sucesso':       true,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:  Text(AppStrings.voiceTriggerDeleted),
      behavior: SnackBarBehavior.floating,
    ));
    await _speak('Lembrete removido.');
  }

  // Fase 1 — confirmação por voz antes de remover um gatilho encontrado por
  // COMANDO de voz (match único). Nos pickers, o toque já é a confirmação
  // explícita, então lá seguimos chamando _deleteTriggerDirectly diretamente.
  Future<void> _confirmDeleteTrigger(TriggerEntity t) async {
    final label = t.title.isNotEmpty ? t.title : t.content;
    await _confirmByVoice(
      'Você deseja remover o lembrete $label?',
      () => _deleteTriggerDirectly(t),
    );
  }

  // ── Fase 1 — sem popups + confirmação por voz ─────────────────────────────

  // Encerra o fluxo quando não houve fala válida.
  // Objetivo: substituir o antigo _FallbackSheet por feedback de voz + toast,
  // sem NENHUM popup. Não chama o Gemini (o guard já barrou antes).
  Future<void> _handleNoSpeech() async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);
    AppLogger.log('speech_no_match', {'surface': 'home'}); // BUG 9 — surface
    // REGRA 3 — responder APENAS "Não consegui ouvir você." Nada além disso
    // (snackbar extra removido nesta hotfix).
    await _speak(AppStrings.voiceNoSpeechHeard);
  }

  // Fluxo reutilizável de confirmação por voz para operações destrutivas.
  //
  // Motivo: a sprint exige que TODA operação destrutiva seja confirmada por voz,
  // sem AlertDialog nem botão. Em vez de duplicar lógica em cada handler, este
  // método centraliza: fala a [question], arma _pendingConfirm e orienta o usuário
  // a responder. A resposta é capturada na próxima gravação e resolvida em
  // _resolveVoiceConfirmation, que executa [onYes] apenas se o usuário confirmar.
  //
  // Casos especiais: se o widget for descartado, _pendingConfirm some (RAM) e nada
  // é executado — comportamento seguro para ação irreversível.
  Future<void> _confirmByVoice(
    String question,
    Future<void> Function() onYes,
  ) async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);
    _pendingConfirm = _VoiceConfirmRequest(question: question, onYes: onYes);
    AppLogger.log('voice_confirmation_started', {'surface': 'home'}); // BUG 9
    await _speak(question);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:  Text(AppStrings.voiceAnswerYesNo),
      duration: Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Interpreta a gravação como resposta de confirmação (sim/não).
  //
  // Fluxo: transcreve o áudio (mesma infra Gemini — sem popup) e usa o parser
  // 100% local VoiceService.parseYesNo. sim → executa onYes; não/ambíguo →
  // cancela por segurança (ação destrutiva nunca ocorre sem "sim" explícito).
  // O retorno antecipado em cada ramo garante que _pendingConfirm seja sempre
  // limpo, evitando estado preso.
  Future<void> _resolveVoiceConfirmation(String filePath) async {
    final pending = _pendingConfirm;
    _pendingConfirm = null; // consome o estado antes de qualquer await/erro
    if (pending == null) return;

    if (mounted) setState(() => _fabState = _FabState.processing);
    final service    = ref.read(voiceServiceProvider);
    // BUG 2 — transcrição PURA (prompt mínimo, sem NLU). A decisão sim/não é
    // 100% local em parseYesNo. Nunca envia a confirmação ao classificador.
    final transcript = await service.transcribeOnly(filePath);
    if (!mounted) return;
    // BUG 2 (temporário) — confirmação resolvida localmente (nunca remota).
    AppLogger.log('voice_confirmation_local', {'surface': 'home'});

    final answer = VoiceService.parseYesNo(transcript);
    if (answer == true) {
      AppLogger.log('voice_confirmation_yes', {'surface': 'home'}); // BUG 9
      await pending.onYes();
    } else {
      // não OU ambíguo → cancela (log distingue negação explícita de ruído)
      AppLogger.log('voice_confirmation_no',
          {'surface': 'home', 'explicit': (answer == false)}); // BUG 9
      if (mounted) setState(() => _fabState = _FabState.idle);
      await _speak(AppStrings.voiceOperationCancelled);
    }
  }

  // ── Fase 2 — assistente: plano de ações + conversa natural ────────────────

  // Resposta sem ações: o Gemini só conversou (pediu um dado, respondeu algo,
  // ou não entendeu). Fala o reply; se houver follow-up, guarda como pergunta
  // pendente no contexto e também a fala. Sem reply → fallback natural.
  Future<void> _handleConversationalReply(
      VoicePlanResult planRes, ConversationContext ctx) async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);

    if (planRes.reply.trim().isEmpty) {
      await _handleFallback(
          VoiceResult(intent: VoiceIntent.fallback, transcript: planRes.transcript));
      return;
    }

    // Atualiza contexto (o Gemini pode ter fixado o ambiente em foco)
    ctx.applyUpdates(planRes.contextUpdates);
    if (planRes.followUp != null) {
      ctx.lastQuestion = planRes.followUp;
      ctx.state = ConversationState.awaitingInformation;
    } else {
      ctx.state = ConversationState.completed;
    }
    ctx.touch();
    AppLogger.log('conversation_updated',
        {'has_follow_up': planRes.followUp != null});

    await _speak(planRes.reply);
    if (planRes.followUp != null && mounted) await _speak(planRes.followUp!);
  }

  // BUG 12 — guarda de prioridade destrutiva (paridade com o Overlay
  // applyDestructivePriority). Roda sobre a TRANSCRIÇÃO, não sobre a
  // classificação do Gemini: se a fala tem verbo destrutivo + "todos/todas/tudo"
  // SEM palavra de gatilho/lembrete, força [deleteAllEnvironments] e descarta
  // qualquer ação construtiva. Impede que "apagar todos os ambientes" vire
  // createTrigger. Exclusão de lembretes de um local é deixada ao plano do Gemini.
  VoicePlanResult _applyDestructivePriority(VoicePlanResult res) {
    final t = res.transcript.toLowerCase();
    final verb = ['apag', 'remov', 'exclu', 'delet', 'limp'].any(t.contains);
    if (!verb) return res;
    final total = ['todos', 'todas', 'tudo'].any(t.contains);
    final trg =
        ['gatilho', 'lembrete', 'lembranca', 'lembrança'].any(t.contains);
    if (total && !trg) {
      // LOG TEMPORÁRIO (BUG 12) — prioridade destrutiva aplicada na Home.
      AppLogger.log('intent_priority_applied',
          {'surface': 'home', 'forced': 'delete_all_environments'});
      return VoicePlanResult(
        transcript:     res.transcript,
        reply:          res.reply,
        plan:           ExecutionPlan(
            [VoiceAction(type: VoiceActionType.deleteAllEnvironments)]),
        followUp:       res.followUp,
        contextUpdates: res.contextUpdates,
      );
    }
    return res;
  }

  // Recebe um plano com ações. Se houver ação destrutiva, confirma UMA vez por
  // voz antes de executar tudo; caso contrário, fala o reply e executa direto.
  Future<void> _runAssistantPlan(
      VoicePlanResult planRes, ConversationContext ctx) async {
    if (!mounted) return;
    AppLogger.log('execution_plan_created', {
      'count':       planRes.plan.actions.length,
      'destructive': planRes.plan.hasDestructive,
    });

    // ── LOGS TEMPORARIOS DE CALIBRACAO (Fase 2.1) — remover apos ajustar o prompt.
    // Auditam como o Gemini estruturou a fala: acoes cruas, agrupamento por local
    // e contagem de create_environment vs create_trigger (detecta ambiente inventado
    // ou reutilizacao que virou criacao).
    AppLogger.log('execution_plan_raw', {
      'actions': planRes.plan.actions
          .map((a) => {'type': a.type.name, ...a.params})
          .toList(),
    });
    final grouping = <String, List<String>>{};
    for (final a in planRes.plan.actions) {
      if (a.type == VoiceActionType.createTrigger) {
        final env = a.str(['environment', 'name']) ?? '?';
        (grouping[env] ??= []).add(a.str(['title']) ?? '?');
      }
    }
    AppLogger.log('environment_grouping', {'groups': grouping});
    AppLogger.log('execution_plan_validation', {
      'create_environment': planRes.plan.actions
          .where((a) => a.type == VoiceActionType.createEnvironment).length,
      'create_trigger': planRes.plan.actions
          .where((a) => a.type == VoiceActionType.createTrigger).length,
    });

    if (planRes.plan.hasDestructive) {
      // Confirmação única cobrindo as ações destrutivas do plano.
      ctx.state = ConversationState.awaitingConfirmation;
      await _confirmByVoice(
        _planDestructiveQuestion(planRes.plan),
        () => _executePlan(planRes, ctx),
      );
      return;
    }

    // Resolução Inteligente de Localização — fluxo ÚNICO de criação de ambiente.
    // Qualquer plano com UM ambiente NOVO (mesmo misto: ambiente + gatilhos) passa
    // pelo resolvedor (Place Search / GPS confirmado). As ações restantes (gatilhos)
    // ficam pendentes e rodam DEPOIS que a localização é resolvida e o ambiente
    // criado — nunca via GPS cego. Assim planos simples e mistos usam o MESMO fluxo.
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final newCreateEnvs = planRes.plan.actions
        .where((a) =>
            a.type == VoiceActionType.createEnvironment &&
            _matchEnv(envs, a.str(['name', 'environment'])) == null)
        .toList();
    if (newCreateEnvs.length == 1) {
      final envAction = newCreateEnvs.first;
      final name = envAction.str(['name', 'environment']);
      // TEMP: remover após auditoria do Place Search
      AppLogger.log('execution_plan_place_name', {
        'environment_name': name,
        'action':           'create_environment',
        'source':           'gemini',
      });
      if (name != null && name.trim().isNotEmpty) {
        // Gatilhos e demais ações rodam após a criação (o ambiente já existirá →
        // handler retorna 'ja_existia' sem tocar em GPS; gatilhos casam pelo nome).
        _pendingPostEnvActions =
            planRes.plan.actions.where((x) => x != envAction).toList();
        if (mounted) setState(() => _fabState = _FabState.idle);
        await _resolveEnvironmentLocation(name.trim(), ctx);
        return;
      }
    }

    // Não destrutivo: resposta natural imediata + execução em background.
    if (mounted) setState(() => _fabState = _FabState.idle);
    if (planRes.reply.trim().isNotEmpty) await _speak(planRes.reply);
    await _executePlan(planRes, ctx);
  }

  // Executa o ExecutionPlan em sequência (falha não aborta), atualiza contexto e
  // providers, e dá a resposta natural final (sucesso / parcial / follow-up).
  Future<void> _executePlan(
      VoicePlanResult planRes, ConversationContext ctx) async {
    if (mounted) setState(() => _fabState = _FabState.processing);
    ctx.state = ConversationState.executing;
    // BUG 6 (temporário) — início do plano com surface/actions.
    AppLogger.log('execution_plan_started',
        {'surface': 'home', 'actions': planRes.plan.actions.length});
    // BUG 8 (temporário) — evento nomeado do executor da Home.
    AppLogger.log('home_executor_started', {'surface': 'home'});

    // Resolve o GPS UMA vez se o plano criar ambientes (evita N fixes/latência).
    ({double lat, double lng})? sharedLoc;
    if (planRes.plan.needsLocation) sharedLoc = await _resolveSharedLocation();

    final execSw   = Stopwatch()..start(); // BUG 4 (temporário) — só a execução
    final executor = VoiceActionExecutor(_buildActionHandlers(sharedLoc));
    final summary  = await executor.run(planRes.plan);
    final execMs   = execSw.elapsedMilliseconds;

    // Refresh das listas (mesmos providers usados no onResume)
    ref.invalidate(environmentsProvider);
    ref.invalidate(triggersByEnvironmentProvider);

    // Atualiza memória de conversa
    ctx.applyUpdates(planRes.contextUpdates);
    if (planRes.followUp != null) ctx.lastQuestion = planRes.followUp;
    ctx.state = ConversationState.completed;
    ctx.touch();
    AppLogger.log('conversation_updated', {'last_environment': ctx.lastEnvironment});

    if (summary.partialFailure) {
      AppLogger.log('execution_plan_partial_failure',
          {'ok': summary.ok, 'failed': summary.failed});
    }
    // BUG 6 (temporário) — falha total do plano (nenhuma ação concluída).
    if (summary.ok == 0 && summary.failed > 0) {
      AppLogger.log('execution_plan_failed', {
        'surface': 'home', 'actions': summary.total, 'failed': summary.failed,
      });
    }
    // BUG 6 (temporário) — fim do plano com surface/actions/ok/failed/duration_ms.
    AppLogger.log('execution_plan_finished', {
      'surface':     'home',
      'actions':     summary.total,
      'ok':          summary.ok,
      'failed':      summary.failed,
      'duration_ms': execMs,
    });
    // BUG 8 (temporário) — evento nomeado do executor da Home.
    AppLogger.log('home_executor_finished', {'surface': 'home'});
    // BUG 4 (temporário) — latência total do pipeline (captura→execução).
    AppLogger.log('voice_timing', {
      'surface':           'home',
      'execution_duration_ms': execMs,
      'total_duration_ms': _pipelineSw?.elapsedMilliseconds,
    });

    if (!mounted) return;

    // Resposta final natural conforme o resultado
    if (summary.ok == 0 && summary.failed > 0) {
      setState(() => _fabState = _FabState.idle);
      await _speak('Não consegui concluir agora. Pode tentar de novo?');
    } else if (summary.partialFailure) {
      setState(() => _fabState = _FabState.idle);
      await _speak('Fiz a maior parte. ${summary.failed} não deram certo.');
    } else {
      await _setSuccess();
      if (planRes.followUp != null &&
          planRes.followUp!.trim().isNotEmpty &&
          mounted) {
        await _speak(planRes.followUp!);
      }
    }
  }

  // Resolve a localização atual uma única vez (reuso pelo executor).
  // Retorna null se GPS indisponível — create_environment então falha isolado.
  Future<({double lat, double lng})?> _resolveSharedLocation() async {
    try {
      final service = ref.read(nativeLocationServiceProvider);
      final loc = await getLocationWithGpsCheck(context, service);
      if (loc == null) return null;
      return (lat: loc.latitude, lng: loc.longitude);
    } catch (e) {
      debugPrint('[_VoiceFab] GPS do plano falhou: $e');
      return null;
    }
  }

  // ── Resolução Inteligente de Localização ─────────────────────────────────
  //
  // Entrada única para criar um ambiente por voz sem usar GPS cego. Classifica a
  // origem da localização (location_source) e conduz a conversa: confirmar GPS,
  // pedir endereço, ou pesquisar estabelecimento. A criação só ocorre no fim.
  // Reutiliza a infra existente: geocodingRepository (busca), _createEnvironmentFromGps
  // (GPS), parseYesNo/transcribeOnly (voz) e o geofence nativo.
  Future<void> _resolveEnvironmentLocation(
      String name, ConversationContext ctx) async {
    // LOG TEMPORÁRIO — início da resolução de localização.
    AppLogger.log('location_resolution_started', {'name': name});
    ctx.pendingEnvName = name;
    ctx.state = ConversationState.awaitingInformation;

    // Já existe no banco? Reutiliza sem recriar (não duplica ambiente).
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final existing = _matchEnv(envs, name);
    if (existing != null) {
      // LOG TEMPORÁRIO — origem detectada.
      AppLogger.log('location_source_detected',
          {'name': name, 'source': LocationSource.existingEnvironment.name});
      ctx.lastEnvironment = existing.name;
      ctx.pendingEnvName = null;
      ctx.state = ConversationState.completed;
      // LOG TEMPORÁRIO — fim da resolução (já existia).
      AppLogger.log('location_resolution_finished',
          {'created': false, 'reason': 'exists'});
      // Gatilhos pendentes ainda rodam no ambiente já existente (mesmo executor).
      await _runPendingPostEnvActions();
      if (mounted) await _speak('Você já tem o ambiente ${existing.name}.');
      return;
    }

    final source = LocationSourceResolver.classify(name);
    // LOG TEMPORÁRIO — origem detectada.
    AppLogger.log('location_source_detected', {'name': name, 'source': source.name});

    switch (source) {
      // GPS ou indeterminado → confirma uso da localização atual.
      case LocationSource.gpsCurrent:
      case LocationSource.unknown:
        await _askGpsConfirm(name);
      // Referência possessiva ("Casa da mãe") → pede o endereço.
      case LocationSource.addressText:
        await _askEnvAddress(name);
      // Estabelecimento → categoria genérica pede "qual?"; marca busca direto.
      case LocationSource.placeSearch:
        if (LocationSourceResolver.needsSpecifier(name)) {
          await _askSpecifier(name);
        } else {
          await _runPlaceSearch(name, name);
        }
      // Já tratado acima (existência checada antes da classificação).
      case LocationSource.existingEnvironment:
        break;
    }
  }

  // Fala [question] e ENTRA EM ESPERA (WAITING_USER_RESPONSE). BUG 2: encerra
  // qualquer captura, volta ao IDLE e NÃO reabre o microfone — a próxima gravação
  // só inicia quando o usuário pressionar de novo (paridade com _confirmByVoice).
  // Impede que a máquina de estados vá de TTS → RECORDING sozinha.
  Future<void> _askAndWait(String question) async {
    await _forceStopRecording('waiting_user_response');
    if (!mounted) return;
    // LOG TEMPORÁRIO — entrou em espera pela resposta do usuário.
    AppLogger.log('location_resolution_waiting', {'surface': 'home'});
    AppLogger.log('waiting_user_response',
        {'surface': 'home', 'state': 'await_location_resolution'});
    AppLogger.log('voice_state_changed',
        {'surface': 'home', 'state': 'waiting_user_response'});
    await _speak(question);
  }

  // BUG 2 — encerra COMPLETAMENTE a captura de áudio e volta ao IDLE ao entrar em
  // espera: cancela o timer de gravação, para o pulso e cancela o MediaRecorder +
  // listener de amplitude do VoiceService (cancelRecording zera timers/subscription).
  // Zera o estado transitório do FAB. Idempotente — seguro sem gravação ativa.
  Future<void> _forceStopRecording(String reason) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    try {
      await ref.read(voiceServiceProvider).cancelRecording();
    } catch (_) {}
    if (mounted) setState(() => _fabState = _FabState.idle);
    // LOG TEMPORÁRIO — captura encerrada à força ao entrar em espera.
    AppLogger.log('recording_force_stopped', {'surface': 'home', 'reason': reason});
  }

  // Pergunta se pode usar a localização atual (Casos 1 e 5).
  Future<void> _askGpsConfirm(String name) async {
    final ctx = ref.read(conversationContextProvider);
    ctx.pendingLocationStage = 'confirm_gps';
    final q = 'Você quer usar sua localização atual para o ambiente $name?';
    ctx.lastQuestion = q;
    _envLocationPending = _EnvLocationPending(name: name, turn: _EnvTurn.confirmGps);
    // LOG TEMPORÁRIO — confirmação iniciada.
    AppLogger.log('location_confirmation_started',
        {'name': name, 'stage': 'confirm_gps'});
    await _askAndWait(q);
  }

  // Pede o endereço para geocodificar (Caso 4 e fallback de GPS/place negados).
  Future<void> _askEnvAddress(String name) async {
    final ctx = ref.read(conversationContextProvider);
    ctx.pendingLocationStage = 'await_address';
    const q = 'Qual o endereço?';
    ctx.lastQuestion = q;
    _envLocationPending = _EnvLocationPending(name: name, turn: _EnvTurn.askAddress);
    await _askAndWait(q);
  }

  // Pede QUAL estabelecimento quando o nome é uma categoria genérica (Caso 3).
  Future<void> _askSpecifier(String name) async {
    final ctx = ref.read(conversationContextProvider);
    ctx.pendingLocationStage = 'await_specifier';
    final q = 'Qual ${name.toLowerCase()} você deseja usar?';
    ctx.lastQuestion = q;
    _envLocationPending = _EnvLocationPending(name: name, turn: _EnvTurn.askSpecifier);
    await _askAndWait(q);
  }

  // Executa a busca de estabelecimento REUTILIZANDO o geocodingRepository
  // (cache → Geocoder → Photon). [name] é o nome do ambiente; [query] o texto pesquisado.
  Future<void> _runPlaceSearch(String name, String query) async {
    if (mounted) setState(() => _fabState = _FabState.processing);
    // TEMP: remover após auditoria do Place Search
    final prefs = await SharedPreferences.getInstance();
    double? lastCoord(String k) {
      final v = prefs.get(k);
      if (v is double) return v;
      if (v is String) return double.tryParse(v);
      return null;
    }
    AppLogger.log('place_search_request', {
      'query':     query,
      'surface':   'home',
      'latitude':  lastCoord('last_known_lat'),
      'longitude': lastCoord('last_known_lon'),
    });
    List<GeocodingResult> results = const [];
    try {
      results = await ref.read(geocodingRepositoryProvider).search(query);
    } catch (e) {
      debugPrint('[_VoiceFab] place search erro: $e');
    }
    if (!mounted) return;
    // TEMP: remover após auditoria do Place Search
    AppLogger.log('place_search_response', {
      'query':         query,
      'count':         results.length,
      'first_result':  results.isNotEmpty
          ? results.first.displayName.split('\n').first
          : '',
      'first_address': results.isNotEmpty && results.first.displayName.contains('\n')
          ? results.first.displayName.split('\n').sublist(1).join(', ')
          : '',
    });
    // Etapa 2 — classifica a confiança sobre a lista já retornada (determinístico,
    // puro). Reaproveita o QueryNormalizer p/ os mesmos hints da camada de busca.
    final norm = QueryNormalizer.normalize(query);
    final rank = LocationRanker.rank(
      query, results,
      userLat: lastCoord('last_known_lat'),
      userLon: lastCoord('last_known_lon'),
      brandHint: norm.brandHint,
      locationHints: norm.locationHints,
      categoryHint: norm.categoryHint,
    );
    // TEMP remover após validação da Etapa 2.
    AppLogger.log('ranking_confidence', {
      'confidence': rank.confidence.name,
      'reason':     rank.reason,
    });
    await _presentPlaceResults(name, rank);
  }

  // DecisionEngine (Etapa 2) — roteia pela CONFIANÇA do RankResult, sem score:
  //   HIGH     → cria automaticamente o primeiro candidato;
  //   MEDIUM   → confirma apenas o primeiro ("Você quis dizer …?");
  //   LOW      → lista os candidatos e pede a escolha;
  //   no_match → pede um endereço mais específico.
  Future<void> _presentPlaceResults(String name, RankResult rank) async {
    final ctx = ref.read(conversationContextProvider);
    final results = rank.orderedCandidates;

    // Sem resultados / sem casamento → pede endereço.
    if (results.isEmpty || rank.reason == 'no_match') {
      ctx.pendingLocationStage = 'await_address';
      _envLocationPending = _EnvLocationPending(name: name, turn: _EnvTurn.askAddress);
      await _askAndWait('Não encontrei $name. Qual o endereço?');
      return;
    }

    // Regra de decisão a partir da confiança.
    final String rule;
    final bool autoSelected;
    switch (rank.confidence) {
      case LocationConfidence.high:
        rule = 'high_auto';
        autoSelected = true;
      case LocationConfidence.medium:
        rule = 'medium_confirm';
        autoSelected = false;
      case LocationConfidence.low:
        rule = 'low_list';
        autoSelected = false;
    }
    // TEMP remover após validação da Etapa 2.
    AppLogger.log('decision_rule', {
      'rule':          rule,
      'auto_selected': autoSelected,
    });

    // HIGH → cria automaticamente o primeiro.
    if (rank.confidence == LocationConfidence.high) {
      final r = results.first;
      await _createEnvironmentAtCoords(name, r.lat, r.lon, ctx);
      return;
    }

    // MEDIUM → confirma apenas o primeiro candidato (fluxo confirm_place).
    if (rank.confidence == LocationConfidence.medium) {
      final r = results.first;
      ctx.pendingLocationStage = 'confirm_place';
      _envLocationPending = _EnvLocationPending(
          name: name, turn: _EnvTurn.confirmPlace, candidates: [r]);
      // LOG TEMPORÁRIO — confirmação de local único.
      AppLogger.log('location_confirmation_started',
          {'name': name, 'stage': 'confirm_place'});
      await _askAndWait('Você quis dizer ${_spoken(r.displayName)}?');
      return;
    }

    // LOW → lista os primeiros e pede a escolha (fluxo choose_place).
    final top = results.take(3).toList();
    ctx.pendingLocationStage = 'choose_place';
    _envLocationPending = _EnvLocationPending(
        name: name, turn: _EnvTurn.choosePlace, candidates: top);
    final buf = StringBuffer('Encontrei alguns locais. ');
    for (var i = 0; i < top.length; i++) {
      buf.write('${i + 1}: ${_spoken(top[i].displayName)}. ');
    }
    buf.write('Qual deles?');
    await _askAndWait(buf.toString());
  }

  // Resolve a gravação de resposta de acordo com a etapa pendente da conversa.
  // Consome _envLocationPending antes de qualquer await (evita estado preso).
  Future<void> _resolveEnvLocationTurn(String filePath) async {
    final pending = _envLocationPending;
    _envLocationPending = null;
    if (pending == null) return;
    final ctx = ref.read(conversationContextProvider);
    if (mounted) setState(() => _fabState = _FabState.processing);
    final service = ref.read(voiceServiceProvider);

    switch (pending.turn) {
      // Sim/não para usar o GPS. Sim → cria via GPS; não → pede endereço.
      case _EnvTurn.confirmGps:
        final ansGps =
            VoiceService.parseYesNo(await service.transcribeOnly(filePath));
        if (!mounted) return;
        if (ansGps == true) {
          setState(() => _fabState = _FabState.processing);
          final env = await _createEnvironmentFromGps(pending.name);
          if (!mounted) return;
          if (env != null) {
            await _finishEnvCreation(env.name, ctx);
          } else {
            await _askEnvAddress(pending.name); // GPS falhou → pede endereço
          }
        } else {
          await _askEnvAddress(pending.name);
        }
      // Sim/não para o local único encontrado. Sim → cria nas coordenadas.
      case _EnvTurn.confirmPlace:
        final replyPlace = await service.transcribeOnly(filePath);
        if (!mounted) return;
        // BUG 2 — "nenhum/não é esse": descarta o resultado e pede endereço mais
        // específico (nunca reapresenta o mesmo local).
        if (_isNoneAnswer(replyPlace)) {
          await _askMoreSpecificAddress(pending.name);
          return;
        }
        final ansPlace = VoiceService.parseYesNo(replyPlace);
        if (ansPlace == true && pending.candidates.isNotEmpty) {
          final r = pending.candidates.first;
          // TEMP: remover após auditoria da resolução de localização
          AppLogger.log('location_confirmation_accepted', {
            'environment': pending.name,
            'place_name':  r.displayName.split('\n').first,
            'address':     r.displayName.contains('\n')
                ? r.displayName.split('\n').sublist(1).join(', ')
                : '',
            'latitude':    r.lat,
            'longitude':   r.lon,
            'source':      r.source,
          });
          await _createEnvironmentAtCoords(pending.name, r.lat, r.lon, ctx);
        } else {
          await _askEnvAddress(pending.name);
        }
      // Endereço ditado → geocodifica e apresenta.
      case _EnvTurn.askAddress:
        final addr = await service.transcribeOnly(filePath);
        if (!mounted) return;
        if (addr == null || VoiceService.isInvalidTranscript(addr)) {
          setState(() => _fabState = _FabState.idle);
          await _speak('Não entendi o endereço.');
          return;
        }
        await _runPlaceSearch(pending.name, addr);
      // Especificador da categoria ("Assaí") → pesquisa.
      case _EnvTurn.askSpecifier:
        final spec = await service.transcribeOnly(filePath);
        if (!mounted) return;
        if (spec == null || VoiceService.isInvalidTranscript(spec)) {
          setState(() => _fabState = _FabState.idle);
          await _speak('Não entendi.');
          return;
        }
        await _runPlaceSearch(pending.name, spec);
      // Escolha entre vários → identifica o candidato e cria.
      case _EnvTurn.choosePlace:
        final answerChoose = await service.transcribeOnly(filePath);
        if (!mounted) return;
        // BUG 2 — "nenhum/não é esse/outra opção": descarta a lista, limpa a
        // seleção e pede endereço mais específico. Nunca repete a mesma lista.
        if (_isNoneAnswer(answerChoose)) {
          await _askMoreSpecificAddress(pending.name);
          return;
        }
        final chosen = _pickCandidate(answerChoose, pending.candidates);
        if (chosen != null) {
          // TEMP: remover após auditoria da resolução de localização
          AppLogger.log('location_confirmation_accepted', {
            'environment': pending.name,
            'place_name':  chosen.displayName.split('\n').first,
            'address':     chosen.displayName.contains('\n')
                ? chosen.displayName.split('\n').sublist(1).join(', ')
                : '',
            'latitude':    chosen.lat,
            'longitude':   chosen.lon,
            'source':      chosen.source,
          });
          await _createEnvironmentAtCoords(pending.name, chosen.lat, chosen.lon, ctx);
        } else {
          setState(() => _fabState = _FabState.idle);
          await _speak('Não entendi qual. Pode repetir?');
        }
    }
  }

  // Identifica qual candidato o usuário escolheu: por ordinal falado
  // ("primeiro/segundo") ou por trecho do endereço/nome mencionado.
  GeocodingResult? _pickCandidate(
      String? text, List<GeocodingResult> candidates) {
    if (text == null || candidates.isEmpty) return null;
    final t = text.toLowerCase();
    const ordinals = {
      'primeir': 0, ' um': 0, '1': 0,
      'segund': 1, 'dois': 1, '2': 1,
      'terceir': 2, 'tres': 2, 'três': 2, '3': 2,
    };
    for (final e in ordinals.entries) {
      if (t.contains(e.key) && e.value < candidates.length) {
        return candidates[e.value];
      }
    }
    // Casamento por palavra (>3 letras) presente no displayName do candidato.
    final words = t.split(RegExp(r'\s+')).where((w) => w.length > 3);
    for (final c in candidates) {
      final d = _spoken(c.displayName).toLowerCase();
      if (words.any((w) => d.contains(w))) return c;
    }
    return null;
  }

  // BUG 2 — reconhece respostas que rejeitam TODOS os resultados apresentados
  // ("nenhum", "não é esse", "outra opção", "nenhum deles"...). Local, sem rede.
  static bool _isNoneAnswer(String? text) {
    if (text == null) return false;
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return false;
    const phrases = [
      'nenhum', 'nenhuma',                 // cobre "nenhum deles", "não é nenhum"
      'não é esse', 'nao é esse', 'não e esse', 'nao e esse',
      'não é essa', 'nao é essa', 'não e essa', 'nao e essa',
      'outra opção', 'outra opcao',
    ];
    return phrases.any((p) => t.contains(p));
  }

  // BUG 2 — descarta a seleção pendente e pede um endereço/ponto de referência
  // mais específico. Nunca reapresenta a mesma lista automaticamente.
  Future<void> _askMoreSpecificAddress(String name) async {
    final ctx = ref.read(conversationContextProvider);
    ctx.pendingLocationStage = 'await_address';
    const q =
        'Pode me informar um endereço mais específico ou um ponto de referência?';
    ctx.lastQuestion = q;
    // Novo turno de endereço com candidatos ZERADOS (lista antiga descartada).
    _envLocationPending = _EnvLocationPending(name: name, turn: _EnvTurn.askAddress);
    await _askAndWait(q);
  }

  // Cria o ambiente em coordenadas conhecidas (busca/endereço) reutilizando o
  // repositório e o geofence nativo — mesmo caminho de _createEnvironmentFromGps.
  Future<void> _createEnvironmentAtCoords(
      String name, double lat, double lon, ConversationContext ctx,
      {int radiusMeters = 100}) async {
    if (mounted) setState(() => _fabState = _FabState.processing);
    // TEMP: remover após auditoria da resolução de localização
    AppLogger.log('environment_coordinates_before_creation', {
      'environment': name,
      'latitude':    lat,
      'longitude':   lon,
      'source':      'place_search',
    });
    final env = EnvironmentEntity(
      id:           const Uuid().v4(),
      name:         _capitalize(name),
      latitude:     lat,
      longitude:    lon,
      radiusMeters: radiusMeters.toDouble(),
      createdAt:    DateTime.now(),
    );
    // TEMP: remover após calibração da resolução de localização
    AppLogger.log('environment_creation_coordinates', {
      'environment': env.name,
      'lat':         env.latitude,
      'lng':         env.longitude,
      'source':      'place_search',
    });
    // TEMP: remover após auditoria da resolução de localização
    AppLogger.log('environment_repository_save', {
      'environment': env.name,
      'latitude':    env.latitude,
      'longitude':   env.longitude,
    });
    await ref.read(environmentRepositoryProvider).save(env);
    // TEMP: remover após auditoria da resolução de localização
    AppLogger.log('environment_saved', {
      'environment': env.name,
      'id':          env.id,
      'latitude':    env.latitude,
      'longitude':   env.longitude,
    });
    // TEMP: remover após auditoria da resolução de localização
    AppLogger.log('geofence_coordinates', {
      'environment': env.name,
      'latitude':    env.latitude,
      'longitude':   env.longitude,
      'radius':      env.radiusMeters,
    });
    await ref.read(nativeGeofenceServiceProvider).addSingleGeofence(env);
    // TEMP: remover após calibração da resolução de localização
    AppLogger.log('location_resolution_result', {
      'resolved':               true,
      'source':                 'place_search',
      'used_current_location':  false,
    });
    AppLogger.log('env_created_by_voice', {'env_id': env.id, 'env_name': env.name});
    await _finishEnvCreation(env.name, ctx);
  }

  // Encerra a criação: atualiza providers e contexto, confirma por voz e mostra sucesso.
  Future<void> _finishEnvCreation(String name, ConversationContext ctx) async {
    ref.invalidate(environmentsProvider);
    ref.invalidate(triggersByEnvironmentProvider);
    ctx.lastEnvironment = name;
    ctx.pendingEnvName = null;
    ctx.pendingLocationStage = null;
    ctx.state = ConversationState.completed;
    ctx.touch();
    // LOG TEMPORÁRIO — fim da resolução de localização.
    AppLogger.log('location_resolution_finished', {'created': true, 'name': name});
    // Executa os gatilhos pendentes do plano no ambiente recém-criado.
    await _runPendingPostEnvActions();
    if (!mounted) return;
    await _speak('Ambiente $name criado.');
    await _setSuccess();
  }

  // Executa as ações restantes do plano (gatilhos) reutilizando o MESMO executor
  // SEM resolver GPS: a localização já foi resolvida e o ambiente já existe, então
  // o handler de createEnvironment retorna 'ja_existia' (sem tocar em GPS) e os
  // gatilhos casam pelo nome do ambiente recém-criado. Garante fluxo único.
  Future<void> _runPendingPostEnvActions() async {
    final post = _pendingPostEnvActions;
    _pendingPostEnvActions = null;
    if (post == null || post.isEmpty) return;
    final executor = VoiceActionExecutor(_buildActionHandlers(null));
    await executor.run(ExecutionPlan(post));
    ref.invalidate(environmentsProvider);
    ref.invalidate(triggersByEnvironmentProvider);
  }

  // Normaliza o displayName para leitura por voz (a fix de geocoding usa '\n'
  // entre nome do estabelecimento e endereço).
  String _spoken(String s) => s.replaceAll('\n', ', ');

  // Monta a pergunta de confirmação de um plano com ações destrutivas.
  String _planDestructiveQuestion(ExecutionPlan plan) {
    final destr = plan.actions.where((a) => a.isDestructive).toList();
    if (destr.any((a) => a.type == VoiceActionType.deleteAllEnvironments)) {
      return 'Você deseja excluir todos os ambientes e seus lembretes?';
    }
    if (destr.length == 1) {
      final a = destr.first;
      switch (a.type) {
        case VoiceActionType.deleteEnvironment:
          return 'Você deseja excluir o ambiente ${a.str(['environment', 'name']) ?? ''}?';
        case VoiceActionType.deleteAllTriggers:
          return 'Você deseja remover todos os lembretes de ${a.str(['environment']) ?? ''}?';
        case VoiceActionType.deleteTrigger:
          return 'Você deseja remover o lembrete ${a.str(['title']) ?? ''}?';
        default:
          break;
      }
    }
    return 'Você confirma remover ${destr.length} itens?';
  }

  // Constrói os handlers do executor ligando cada tipo de ação à regra de negócio
  // real (repositórios, GPS, geofence). Handlers lançam exceção em falha — o
  // executor isola e continua. [loc] é o GPS resolvido uma vez para o plano todo.
  Map<VoiceActionType, ActionHandler> _buildActionHandlers(
      ({double lat, double lng})? loc) {
    final envRepo = ref.read(environmentRepositoryProvider);
    final trgRepo = ref.read(triggerRepositoryProvider);
    final geofence = ref.read(nativeGeofenceServiceProvider);

    return {
      // Cria ambiente na localização atual. Reusa se já existir (não duplica).
      VoiceActionType.createEnvironment: (a) async {
        final name = a.str(['name', 'environment']);
        if (name == null) {
          // TEMP: remover após calibração da resolução de localização
          AppLogger.log('execution_handler_failed',
              {'action': 'create_environment', 'reason': 'nome_vazio'});
          throw 'nome_vazio';
        }
        final existing = _matchEnv(await envRepo.getAll(), name);
        if (existing != null) {
          // LOG TEMPORARIO CALIBRACAO (Fase 2.1) — ambiente ja existia: reutilizado.
          AppLogger.log('existing_environment_detected',
              {'requested': name, 'matched': existing.name});
          return 'ja_existia';
        }
        // LOG TEMPORARIO CALIBRACAO (Fase 2.1) — ambiente novo sera criado.
        AppLogger.log('new_environment_detected', {'name': name});
        if (loc == null) {
          // TEMP: remover após calibração da resolução de localização
          AppLogger.log('execution_handler_failed',
              {'action': 'create_environment', 'reason': 'sem_gps'});
          throw 'sem_gps';
        }
        // TEMP: remover após auditoria da resolução de localização
        AppLogger.log('environment_coordinates_before_creation', {
          'environment': name,
          'latitude':    loc.lat,
          'longitude':   loc.lng,
          'source':      'gps_current',
        });
        final env = EnvironmentEntity(
          id:           const Uuid().v4(),
          name:         _capitalize(name),
          latitude:     loc.lat,
          longitude:    loc.lng,
          radiusMeters: 100,
          createdAt:    DateTime.now(),
        );
        // TEMP: remover após calibração da resolução de localização
        AppLogger.log('environment_creation_coordinates', {
          'environment': env.name,
          'lat':         env.latitude,
          'lng':         env.longitude,
          'source':      'gps_current',
        });
        // TEMP: remover após auditoria da resolução de localização
        AppLogger.log('environment_repository_save', {
          'environment': env.name,
          'latitude':    env.latitude,
          'longitude':   env.longitude,
        });
        await envRepo.save(env);
        // TEMP: remover após auditoria da resolução de localização
        AppLogger.log('environment_saved', {
          'environment': env.name,
          'id':          env.id,
          'latitude':    env.latitude,
          'longitude':   env.longitude,
        });
        // TEMP: remover após auditoria da resolução de localização
        AppLogger.log('geofence_coordinates', {
          'environment': env.name,
          'latitude':    env.latitude,
          'longitude':   env.longitude,
          'radius':      env.radiusMeters,
        });
        await geofence.addSingleGeofence(env);
        // TEMP: remover após calibração da resolução de localização
        AppLogger.log('location_resolution_result', {
          'resolved':              true,
          'source':                'gps_current',
          'used_current_location': true,
        });
        return 'ambiente_criado';
      },

      // Cria lembrete num ambiente (que pode ter sido criado antes no mesmo plano).
      VoiceActionType.createTrigger: (a) async {
        final envName = a.str(['environment', 'name']);
        final title   = a.str(['title', 'trigger_title']);
        if (title == null) {
          // TEMP: remover após calibração da resolução de localização
          AppLogger.log('execution_handler_failed',
              {'action': 'create_trigger', 'reason': 'titulo_vazio'});
          throw 'titulo_vazio';
        }
        final env = _matchEnv(await envRepo.getAll(), envName);
        if (env == null) {
          // TEMP: remover após calibração da resolução de localização
          AppLogger.log('execution_handler_failed',
              {'action': 'create_trigger', 'reason': 'ambiente_nao_encontrado'});
          throw 'ambiente_nao_encontrado';
        }
        await trgRepo.save(TriggerEntity(
          id:            const Uuid().v4(),
          environmentId: env.id,
          title:         title,
          content:       a.str(['content']) ?? '',
          isActive:      true,
          createdAt:     DateTime.now(),
        ));
        return 'lembrete_criado';
      },

      // Atualiza um lembrete existente (título e/ou conteúdo) por match de título.
      VoiceActionType.updateTrigger: (a) async {
        final title = a.str(['title']);
        if (title == null) throw 'titulo_vazio';
        final env = _matchEnv(await envRepo.getAll(), a.str(['environment']));
        final triggers = env != null ? await trgRepo.getByEnvironment(env.id) : <TriggerEntity>[];
        final lower = title.toLowerCase();
        TriggerEntity? t;
        for (final x in triggers) {
          if (x.title.toLowerCase().contains(lower)) { t = x; break; }
        }
        if (t == null) throw 'lembrete_nao_encontrado';
        await trgRepo.save(TriggerEntity(
          id:            t.id, // mesmo id = upsert (atualiza)
          environmentId: t.environmentId,
          title:         a.str(['new_title']) ?? t.title,
          content:       a.str(['content']) ?? t.content,
          isActive:      t.isActive,
          createdAt:     t.createdAt,
        ));
        return 'lembrete_atualizado';
      },

      // Atualiza um ambiente (por ora, o raio) e re-registra o geofence.
      VoiceActionType.updateEnvironment: (a) async {
        final env = _matchEnv(await envRepo.getAll(), a.str(['name', 'environment']));
        if (env == null) throw 'ambiente_nao_encontrado';
        final radius = (a.params['radius'] as num?)?.toDouble() ?? env.radiusMeters;
        final updated = EnvironmentEntity(
          id:           env.id,
          name:         env.name,
          latitude:     env.latitude,
          longitude:    env.longitude,
          radiusMeters: radius,
          createdAt:    env.createdAt,
        );
        await envRepo.save(updated);
        await geofence.addSingleGeofence(updated);
        return 'ambiente_atualizado';
      },

      // Exclui um ambiente (cascade nos gatilhos) + remove geofence.
      // Sem popup por item: a confirmação foi feita no nível do plano.
      VoiceActionType.deleteEnvironment: (a) async {
        final env = _matchEnv(await envRepo.getAll(), a.str(['environment', 'name']));
        if (env == null) throw 'ambiente_nao_encontrado';
        await envRepo.delete(env.id);
        try { await geofence.removeGeofence(env.id); } catch (_) {}
        return 'ambiente_removido';
      },

      // Exclui TODOS os ambientes + limpa geofences.
      VoiceActionType.deleteAllEnvironments: (a) async {
        final all = await envRepo.getAll();
        for (final env in all) { await envRepo.delete(env.id); }
        try { await geofence.clearGeofences(); } catch (_) {}
        return 'todos_ambientes_removidos:${all.length}';
      },

      // Remove um lembrete por match de título no ambiente informado.
      VoiceActionType.deleteTrigger: (a) async {
        final title = a.str(['title']);
        if (title == null) throw 'titulo_vazio';
        final env = _matchEnv(await envRepo.getAll(), a.str(['environment']));
        final triggers = env != null ? await trgRepo.getByEnvironment(env.id) : <TriggerEntity>[];
        final lower = title.toLowerCase();
        TriggerEntity? t;
        for (final x in triggers) {
          if (x.title.toLowerCase().contains(lower)) { t = x; break; }
        }
        if (t == null) throw 'lembrete_nao_encontrado';
        await trgRepo.delete(t.id);
        return 'lembrete_removido';
      },

      // Remove todos os lembretes de um ambiente.
      VoiceActionType.deleteAllTriggers: (a) async {
        final env = _matchEnv(await envRepo.getAll(), a.str(['environment']));
        if (env == null) throw 'ambiente_nao_encontrado';
        final triggers = await trgRepo.getByEnvironment(env.id);
        for (final t in triggers) { await trgRepo.delete(t.id); }
        return 'lembretes_removidos:${triggers.length}';
      },
    };
  }

  // ── Auto-execução de intenções (zero confirmação para ações não destrutivas) ─

  // Despacha o resultado do Gemini para o handler correto.
  // Cada handler executa a ação diretamente ou abre um sheet de continuação.
  Future<void> _executeResult(VoiceResult result) async {
    switch (result.intent) {
      case VoiceIntent.createTrigger:
        await _handleCreateTrigger(result);
      case VoiceIntent.createEnvironment:
        await _handleOpenEnvironment(result);
      case VoiceIntent.createEnvironmentWithTrigger:
        await _handleCreateEnvironmentWithTrigger(result);
      case VoiceIntent.updateEnvironment:
        await _handleUpdateEnvironment(result);
      case VoiceIntent.listEnvironments:
        await _handleListEnvironments();
      case VoiceIntent.resolveTrigger:
        await _handleResolveTrigger(result);
      case VoiceIntent.listTriggers:
        await _handleListTriggers(result);
      // ── Exclusão por voz (V2-VoicePro-Etapa3) ─────────────────────────────
      case VoiceIntent.deleteEnvironment:
        await _handleDeleteEnvironment(result);
      case VoiceIntent.deleteTrigger:
        await _handleDeleteTrigger(result);
      case VoiceIntent.deleteAllTriggers:
        await _handleDeleteAllTriggers(result);
      // Fase 1 — nova intent global, sempre confirmada por voz
      case VoiceIntent.deleteAllEnvironments:
        await _handleDeleteAllEnvironments(result);
      case VoiceIntent.fallback:
        await _handleFallback(result);
    }
  }

  // Busca ambiente por nome. Reutiliza SOMENTE quando é realmente o mesmo local:
  // igualdade exata (ignorando apenas caixa e espaços extras) OU similaridade > 95%.
  // BUG 1: sem contains/startsWith/prefixo — "Casa" ≠ "Casa da mãe",
  // "Mercado" ≠ "Mercado Extra". A similaridade só cobre acento/erro de digitação.
  EnvironmentEntity? _matchEnv(List<EnvironmentEntity> envs, String? query) {
    if (query == null || query.trim().isEmpty) return null;
    final q = _normEnvName(query);
    // 1. Igualdade exata (caixa/espaços normalizados) — prioridade máxima.
    final exact = envs.where((e) => _normEnvName(e.name) == q).firstOrNull;
    if (exact != null) return exact;
    // 2. Similaridade alta (> 95%) — nunca reutiliza nomes distintos.
    for (final e in envs) {
      if (_nameSimilarity(_normEnvName(e.name), q) > 0.95) return e;
    }
    return null;
  }

  // Normaliza para comparação de nomes: minúsculas + colapsa espaços repetidos.
  static String _normEnvName(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  // Similaridade 0..1 = 1 - distância de Levenshtein / tamanho do maior nome.
  static double _nameSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - _levenshtein(a, b) / maxLen;
  }

  // Distância de edição de Levenshtein (duas linhas, O(n) de memória).
  static int _levenshtein(String a, String b) {
    final n = b.length;
    var prev = List<int>.generate(n + 1, (i) => i);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1, ins = cur[j - 1] + 1, sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final tmp = prev; prev = cur; cur = tmp;
    }
    return prev[n];
  }

  // Capitaliza a primeira letra de uma string
  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // "lembra de X quando chegar em Y" → salva TriggerEntity diretamente no banco.
  // FIX 3: content = triggerContent extraído pelo Gemini (não o transcript completo).
  Future<void> _handleCreateTrigger(VoiceResult result) async {
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final env  = _matchEnv(envs, result.environmentName);

    if (env != null) {
      // Ambiente encontrado → cria trigger sem interação do usuário
      final title = result.triggerAction ?? '';
      final trigger = TriggerEntity(
        id:            const Uuid().v4(),
        environmentId: env.id,
        // FIX 3: title = campo extraído pelo Gemini (jamais o transcript completo)
        title:         title,
        // FIX 3: content = detalhe extraído pelo Gemini (vazio se não fornecido)
        content:       result.triggerContent ?? '',
        isActive:      true,
        createdAt:     DateTime.now(),
      );
      await ref.read(triggerRepositoryProvider).save(trigger);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${AppStrings.voiceTriggerSavedIn} ${env.name} ✓'),
        // ignore: deprecated_member_use
        backgroundColor: AppColors.snackbarSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ));
      // FIX 4: TTS confirma a ação ao usuário
      await _speak(
        'Anotado! Vou te lembrar de $title quando chegar em ${env.name}.',
      );
      await _setSuccess();
    } else {
      // Ambiente não encontrado → oferece criar agora (GPS) ou escolher outro
      AppLogger.log('trigger_voice_failed', {
        'env_name_from_gemini': result.environmentName,
        'trigger_action':       result.triggerAction,
        'transcript':           result.transcript,
      });
      if (!mounted) return;
      setState(() => _fabState = _FabState.idle);
      // FIX 4: TTS informa que o ambiente não foi encontrado
      await _speak(
        'Não encontrei o ambiente ${result.environmentName ?? ''}. Quer criar agora?',
      );
      _showSheet(_EnvNotFoundSheet(
        envName:      result.environmentName ?? '',
        triggerTitle: result.triggerAction ?? '',
        onCreateNow: () {
          Navigator.pop(context);
          _saveAndConfirmWithGps(result);
        },
        onChooseOther: () {
          Navigator.pop(context);
          _showSheet(_EnvPickerSheet(
            title:         AppStrings.voiceEnvPickerTitle,
            subtitle:      result.triggerAction ?? result.transcript,
            onEnvSelected: (env) => _saveAndConfirm(env, result),
          ));
        },
      ));
    }
  }

  // Salva o trigger no ambiente escolhido pelo seletor e exibe snackbar.
  // FIX 3: content = triggerContent extraído pelo Gemini (não o transcript).
  Future<void> _saveAndConfirm(EnvironmentEntity env, VoiceResult result) async {
    final title = result.triggerAction ?? '';
    final trigger = TriggerEntity(
      id:            const Uuid().v4(),
      environmentId: env.id,
      title:         title,
      content:       result.triggerContent ?? '', // FIX 3
      isActive:      true,
      createdAt:     DateTime.now(),
    );
    await ref.read(triggerRepositoryProvider).save(trigger);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${AppStrings.voiceTriggerSavedIn} ${env.name} ✓'),
      // ignore: deprecated_member_use
      backgroundColor: AppColors.snackbarSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ));
    await _speak('Anotado! Vou te lembrar de $title quando chegar em ${env.name}.'); // FIX 4
  }

  // Processa pedido pendente deixado pelo FloatingVoiceService nas SharedPreferences.
  // Chamado por MainActivity.onResume() via overlayChannel.
  // Suporta: create_environment (precisa de GPS — feito aqui com app em foreground).
  Future<void> _handleServicePendingIntent(String json) async {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final intent = map['intent'] as String?;
      if (intent == 'create_environment') {
        final name = map['name'] as String? ?? '';
        if (name.isNotEmpty) {
          await _handleOpenEnvironment(VoiceResult(
            intent:          VoiceIntent.createEnvironment,
            transcript:      name,
            environmentName: name,
          ));
        }
      }
    } catch (e) {
      debugPrint('[_VoiceFab] Erro ao processar pending intent: $e');
    }
  }

  // ── Helpers de criação por GPS ─────────────────────────────────────────────

  // Obtém GPS, cria EnvironmentEntity no banco e registra o geofence nativo.
  // Retorna a entidade criada, ou null se o GPS falhar.
  Future<EnvironmentEntity?> _createEnvironmentFromGps(
    String name, {
    int radiusMeters = 100,
  }) async {
    try {
      final service = ref.read(nativeLocationServiceProvider);
      final loc = await getLocationWithGpsCheck(context, service);
      if (loc == null) return null;

      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('environment_coordinates_before_creation', {
        'environment': name,
        'latitude':    loc.latitude,
        'longitude':   loc.longitude,
        'source':      'gps_current',
      });
      final env = EnvironmentEntity(
        id:           const Uuid().v4(),
        name:         _capitalize(name),
        latitude:     loc.latitude,
        longitude:    loc.longitude,
        radiusMeters: radiusMeters.toDouble(),
        createdAt:    DateTime.now(),
      );
      // TEMP: remover após calibração da resolução de localização
      AppLogger.log('environment_creation_coordinates', {
        'environment': env.name,
        'lat':         env.latitude,
        'lng':         env.longitude,
        'source':      'gps_current',
      });
      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('environment_repository_save', {
        'environment': env.name,
        'latitude':    env.latitude,
        'longitude':   env.longitude,
      });
      await ref.read(environmentRepositoryProvider).save(env);
      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('environment_saved', {
        'environment': env.name,
        'id':          env.id,
        'latitude':    env.latitude,
        'longitude':   env.longitude,
      });

      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('geofence_coordinates', {
        'environment': env.name,
        'latitude':    env.latitude,
        'longitude':   env.longitude,
        'radius':      env.radiusMeters,
      });
      // Registra no GeofencingClient imediatamente e loga native_geofence_added
      await ref.read(nativeGeofenceServiceProvider).addSingleGeofence(env);
      // TEMP: remover após calibração da resolução de localização
      AppLogger.log('location_resolution_result', {
        'resolved':              true,
        'source':                'gps_current',
        'used_current_location': true,
      });

      AppLogger.log('env_created_by_voice', {
        'env_id':   env.id,
        'env_name': env.name,
      });
      return env;
    } catch (e) {
      debugPrint('[_VoiceFab] Erro ao criar ambiente via GPS: $e');
      return null;
    }
  }

  // Cria ambiente via GPS e salva o trigger nele (usado pelo _EnvNotFoundSheet).
  // Exibe snackbar combinado e chama _setSuccess() ao concluir.
  // Fallback: se GPS falhar, abre _EnvPickerSheet para o usuário escolher ambiente existente.
  Future<void> _saveAndConfirmWithGps(VoiceResult result) async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.processing);

    final name  = result.environmentName ?? '';
    final title = result.triggerAction ?? '';
    final env   = await _createEnvironmentFromGps(name);
    if (!mounted) return;

    if (env != null) {
      await ref.read(triggerRepositoryProvider).save(TriggerEntity(
        id:            const Uuid().v4(),
        environmentId: env.id,
        title:         title,
        content:       result.triggerContent ?? '', // FIX 3
        isActive:      true,
        createdAt:     DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${AppStrings.voiceEnvAndTriggerCreated}: ${env.name} ✓',
        ),
        // ignore: deprecated_member_use
        backgroundColor: AppColors.snackbarSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ));
      await _speak('Anotado! Ambiente ${env.name} criado com o lembrete $title.'); // FIX 4
      await _setSuccess();
    } else {
      // GPS falhou → cai no seletor de ambientes existentes como fallback
      setState(() => _fabState = _FabState.idle);
      _showSheet(_EnvPickerSheet(
        title:         AppStrings.voiceEnvPickerTitle,
        subtitle:      result.triggerAction ?? result.transcript,
        onEnvSelected: (e) => _saveAndConfirm(e, result),
      ));
    }
  }

  // "salva esse lugar como X" → cria ambiente diretamente via GPS.
  // Abre AddEnvironmentScreen como fallback se o GPS falhar.
  // FIX 4: se o nome estiver vazio, pede por TTS e reinicia gravação para capturá-lo.
  Future<void> _handleOpenEnvironment(VoiceResult result) async {
    if (!mounted) return;

    final name   = result.environmentName ?? '';
    final radius = result.environmentRadius ?? 100;

    // FIX 4: nome ausente → TTS + nova gravação automática para capturar o nome
    if (name.trim().isEmpty) {
      setState(() => _fabState = _FabState.idle);
      await _speak('Qual o nome do ambiente?');
      if (!mounted) return;
      _pendingEnvCreate = true;
      // Aguarda 500 ms para o TTS iniciar antes de abrir o microfone
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted && _fabState == _FabState.idle) _onPressStart();
      return;
    }

    setState(() => _fabState = _FabState.processing);

    final env    = await _createEnvironmentFromGps(name, radiusMeters: radius);
    if (!mounted) return;

    if (env != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${AppStrings.voiceEnvCreated}: ${env.name} ✓'),
        // ignore: deprecated_member_use
        backgroundColor: AppColors.snackbarSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ));
      await _speak('Pronto! Ambiente ${env.name} criado.'); // FIX 4
      await _setSuccess();
    } else {
      // GPS falhou → abre tela de adição com nome pré-preenchido
      setState(() => _fabState = _FabState.idle);
      // ignore: use_build_context_synchronously
      pushScreen(
        context,
        AddEnvironmentScreen(initialName: _capitalize(name)),
      );
    }
  }

  // "resolvi X" → desativa o primeiro trigger que corresponda ao título
  Future<void> _handleResolveTrigger(VoiceResult result) async {
    final triggers = await _searchAllTriggers(result.triggerAction ?? '');
    if (!mounted) return;

    if (triggers.isNotEmpty) {
      final first = triggers.first;
      await ref
          .read(triggerRepositoryProvider)
          .setActive(first.id, active: false);
      if (!mounted) return;
      final resolvedTitle = first.title.isNotEmpty ? first.title : first.content;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${AppStrings.voiceTriggerDeactivated}: "$resolvedTitle"',
        ),
        // ignore: deprecated_member_use
        backgroundColor: AppColors.snackbarSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ));
      await _speak('Feito! Lembrete $resolvedTitle marcado como resolvido.'); // FIX 4
      await _setSuccess();
    } else {
      // Trigger não encontrado — sem checkmark, apenas snackbar
      setState(() => _fabState = _FabState.idle);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${AppStrings.voiceTriggerNotFound}: "${result.triggerAction}"',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ));
      await _speak('Não encontrei esse lembrete.'); // FIX 4
    }
  }

  // "o que tenho pendente em X?" → lista triggers ativos inline (sem navegar).
  // FIX 4: fala o resumo de quantos lembretes há antes de abrir o sheet.
  Future<void> _handleListTriggers(VoiceResult result) async {
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final env  = _matchEnv(envs, result.environmentName);
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);

    if (env != null) {
      // Busca antecipada para TTS — o sheet buscará novamente mas é leve
      final triggers = await ref
          .read(triggerRepositoryProvider)
          .getActiveByEnvironment(env.id);
      if (triggers.isEmpty) {
        await _speak('Nenhum lembrete em ${env.name} ainda.');
      } else {
        final n      = triggers.length;
        final titles = triggers.map((t) => t.title.isNotEmpty ? t.title : t.content).join(', ');
        await _speak(
          'Você tem $n lembrete${n == 1 ? '' : 's'} em ${env.name}: $titles.',
        );
      }
      _showSheet(_TriggerListSheet(environment: env));
    } else {
      // Ambiente não encontrado → seletor de ambiente; ao escolher → lista triggers
      await _speak('Pendências de qual ambiente?'); // FIX 4
      _showSheet(_EnvPickerSheet(
        title:    AppStrings.voiceEnvPickerAction,
        subtitle: '',
        onEnvSelected: (e) {
          if (mounted) _showSheet(_TriggerListSheet(environment: e));
        },
      ));
    }
  }

  // "cria o ambiente X e lembra de Y" → cria via GPS e salva triggers automaticamente.
  // Fallback: AddEnvironmentScreen + snackbar de lembrete se o GPS falhar.
  Future<void> _handleCreateEnvironmentWithTrigger(VoiceResult result) async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.processing);

    final name   = result.environmentName ?? '';
    final radius = result.environmentRadius ?? 100;
    final env    = await _createEnvironmentFromGps(name, radiusMeters: radius);
    if (!mounted) return;

    if (env != null) {
      // Salva cada trigger mencionado no comando de voz
      for (final title in result.triggerTitles) {
        if (title.trim().isEmpty) continue;
        await ref.read(triggerRepositoryProvider).save(TriggerEntity(
          id:            const Uuid().v4(),
          environmentId: env.id,
          title:         title,
          content:       '',
          isActive:      true,
          createdAt:     DateTime.now(),
        ));
      }
      if (!mounted) return;
      final msg = result.triggerTitles.isNotEmpty
          ? '${AppStrings.voiceEnvAndTriggerCreated}: ${env.name} ✓'
          : '${AppStrings.voiceEnvCreated}: ${env.name} ✓';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        // ignore: deprecated_member_use
        backgroundColor: AppColors.snackbarSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ));
      // FIX 4: TTS resume o que foi criado
      if (result.triggerTitles.isNotEmpty) {
        await _speak(
          'Pronto! Ambiente ${env.name} criado com '
          '${result.triggerTitles.length} lembrete${result.triggerTitles.length == 1 ? '' : 's'}.',
        );
      } else {
        await _speak('Pronto! Ambiente ${env.name} criado.');
      }
      await _setSuccess();
    } else {
      // GPS falhou → fallback para AddEnvironmentScreen + lembrete dos gatilhos
      setState(() => _fabState = _FabState.idle);
      // ignore: use_build_context_synchronously
      pushScreen(context, AddEnvironmentScreen(initialName: _capitalize(name)));
      if (mounted && result.triggerTitles.isNotEmpty) {
        final list = result.triggerTitles.join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppStrings.voicePendingTriggers} $list'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ));
      }
    }
  }

  // "muda o raio de X para 200" → atualiza diretamente se raio fornecido,
  // caso contrário abre AddEnvironmentScreen em modo edição.
  Future<void> _handleUpdateEnvironment(VoiceResult result) async {
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final env  = _matchEnv(envs, result.environmentName);
    if (!mounted) return;

    if (env != null && result.environmentRadius != null) {
      // Raio fornecido pelo Gemini → atualiza via upsert (mantém lat/lon/nome)
      final updated = EnvironmentEntity(
        id:           env.id,
        name:         env.name,
        latitude:     env.latitude,
        longitude:    env.longitude,
        radiusMeters: result.environmentRadius!.toDouble(),
        createdAt:    env.createdAt,
      );
      await ref.read(environmentRepositoryProvider).save(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${AppStrings.voiceEnvUpdated}: ${env.name} ✓'),
        // ignore: deprecated_member_use
        backgroundColor: AppColors.snackbarSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ));
      await _speak( // FIX 4
        'Feito! Raio de ${env.name} atualizado para ${result.environmentRadius} metros.',
      );
      await _setSuccess();
    } else if (env != null) {
      // Mudança não mapeada → abre tela de edição do ambiente
      setState(() => _fabState = _FabState.idle);
      // ignore: use_build_context_synchronously
      pushScreen(context, AddEnvironmentScreen(environment: env));
    } else {
      // Ambiente não encontrado → seletor de ambiente
      setState(() => _fabState = _FabState.idle);
      _showSheet(_EnvPickerSheet(
        title:    'Qual ambiente atualizar?',
        subtitle: result.transcript,
        onEnvSelected: (e) {
          if (mounted) pushScreen(context, AddEnvironmentScreen(environment: e));
        },
      ));
    }
  }

  // "quais são meus locais" → lista todos os ambientes num sheet inline.
  // FIX 4: fala o número de ambientes antes de abrir o sheet.
  Future<void> _handleListEnvironments() async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    if (envs.isEmpty) {
      await _speak('Você ainda não tem nenhum local cadastrado.');
    } else {
      final n = envs.length;
      await _speak('Você tem $n local${n == 1 ? '' : 'is'} cadastrado${n == 1 ? '' : 's'}.');
    }
    _showSheet(const _EnvsListSheet());
  }

  // Intenção não reconhecida → sheet com campo de texto editável.
  // FIX 4: orienta o usuário por voz antes de abrir o sheet.
  // Fase 1 — houve fala real, mas o Gemini não entendeu a intenção.
  // Novo comportamento: resposta natural por voz, SEM abrir _FallbackSheet.
  // (A guarda de transcrição vazia já tratou o caso "não ouvi nada" antes daqui.)
  Future<void> _handleFallback(VoiceResult result) async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);
    AppLogger.log('voice_intent_unknown',
        {'surface': 'home', 'transcript': result.transcript}); // BUG 9 — surface
    await _speak(AppStrings.voiceDidNotUnderstand);
  }

  // ── Handlers de exclusão por voz ──────────────────────────────────────────

  // "exclui o ambiente X" → Fase 1: confirmação por voz antes de excluir.
  // Fluxo: localiza o ambiente; se não existe, informa; se existe, pergunta
  // "Você deseja excluir o ambiente X?" e só remove após "sim".
  // O SnackBar "Desfazer" é mantido como segunda camada de segurança.
  Future<void> _handleDeleteEnvironment(VoiceResult result) async {
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final env  = _matchEnv(envs, result.environmentName);
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);

    if (env == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(AppStrings.voiceEnvNotFoundForDelete),
        behavior: SnackBarBehavior.floating,
      ));
      AppLogger.log('voice_delete', {
        'intent':        'delete_environment',
        'environment':   result.environmentName,
        'trigger_title': null,
        'sucesso':       false,
      });
      await _speak('Não encontrei o ambiente ${result.environmentName ?? ''}.');
      return;
    }

    // Confirmação por voz — só executa a exclusão após "sim".
    await _confirmByVoice(
      'Você deseja excluir o ambiente ${env.name}?',
      () => _reallyDeleteEnvironment(env),
    );
  }

  // Exclusão efetiva do ambiente (chamada apenas após confirmação por voz).
  // Mantém o comportamento anterior: salva os triggers antes, exclui em cascade
  // e oferece "Desfazer" por 5 s (restaura ambiente, triggers e geofence).
  Future<void> _reallyDeleteEnvironment(EnvironmentEntity env) async {
    if (!mounted) return;
    // Sai do estado "processing" da confirmação por voz antes de concluir
    setState(() => _fabState = _FabState.idle);
    // Salva todos os triggers ANTES do delete (cascade apaga junto)
    final savedTriggers = await ref
        .read(triggerRepositoryProvider)
        .getByEnvironment(env.id);

    // Exclui o ambiente (e todos os seus gatilhos por cascade)
    await ref.read(environmentRepositoryProvider).delete(env.id);
    AppLogger.log('voice_delete', {
      'intent':        'delete_environment',
      'environment':   env.name,
      'trigger_title': null,
      'sucesso':       true,
    });
    if (!mounted) return;

    // FIX 4: TTS imediato confirma a exclusão
    await _speak('Ambiente ${env.name} removido.');

    // SnackBar com "Desfazer" — 5 s para restaurar o ambiente e seus gatilhos
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${AppStrings.voiceEnvDeleted}: ${env.name}'),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      action: SnackBarAction(
        label: AppStrings.undo,
        onPressed: () async {
          // 1. Recria o ambiente com os mesmos dados
          await ref.read(environmentRepositoryProvider).save(env);
          // 2. Recria cada trigger salvo antes do delete
          for (final t in savedTriggers) {
            await ref.read(triggerRepositoryProvider).save(t);
          }
          // 3. Re-registra o geofence nativo para que o app morto volte a disparar
          await ref.read(nativeGeofenceServiceProvider).addGeofence(
            id:           env.id,
            lat:          env.latitude,
            lng:          env.longitude,
            radiusMeters: env.radiusMeters,
            name:         env.name,
          );
          AppLogger.log('voice_delete_undone', {'environment': env.name});
        },
      ),
    ));
  }

  // "remove o lembrete de Y" → busca trigger por título.
  // FIX 2: título nulo → roteia por nome do ambiente (sem busca por texto vazio).
  // 1 resultado → exclui diretamente.
  // >1 resultado → sheet com lista para escolher.
  // 0 resultados → snackbar de não encontrado.
  Future<void> _handleDeleteTrigger(VoiceResult result) async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);

    // FIX 2: título ausente → roteamento por ambiente, não busca textual
    if (result.triggerAction == null) {
      if (result.environmentName != null) {
        // Gemini indicou um ambiente — busca triggers ativos desse ambiente
        final envs = await ref.read(environmentRepositoryProvider).getAll();
        final env  = _matchEnv(envs, result.environmentName);
        if (!mounted) return;
        if (env == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(AppStrings.voiceTriggerDeleteNotFound),
            behavior: SnackBarBehavior.floating,
          ));
          await _speak('Não encontrei esse ambiente.'); // FIX 4
          return;
        }
        final triggers = await ref
            .read(triggerRepositoryProvider)
            .getActiveByEnvironment(env.id);
        if (!mounted) return;
        if (triggers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Nenhum lembrete em ${env.name}.'),
            behavior: SnackBarBehavior.floating,
          ));
          await _speak('Nenhum lembrete em ${env.name}.'); // FIX 4
        } else if (triggers.length == 1) {
          await _confirmDeleteTrigger(triggers.first); // Fase 1 — confirma por voz
        } else {
          await _speak('Qual lembrete você quer remover? Toque em um deles.'); // FIX 4
          _showSheet(_DeleteTriggerPickerSheet(
            triggers: triggers,
            onSelected: (t) async {
              Navigator.pop(context);
              await _deleteTriggerDirectly(t);
            },
          ));
        }
      } else {
        // Nem título nem ambiente → pede ambiente primeiro, depois trigger
        await _speak('De qual ambiente você quer remover um lembrete?'); // FIX 4
        _showSheet(_EnvPickerSheet(
          title:    AppStrings.voiceDeletePickerTitle,
          subtitle: '',
          onEnvSelected: (env) async {
            final triggers = await ref
                .read(triggerRepositoryProvider)
                .getActiveByEnvironment(env.id);
            if (!mounted) return;
            if (triggers.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Nenhum lembrete em ${env.name}.'),
                behavior: SnackBarBehavior.floating,
              ));
            } else if (triggers.length == 1) {
              await _deleteTriggerDirectly(triggers.first);
            } else {
              if (mounted) {
                _showSheet(_DeleteTriggerPickerSheet(
                  triggers: triggers,
                  onSelected: (t) async {
                    Navigator.pop(context);
                    await _deleteTriggerDirectly(t);
                  },
                ));
              }
            }
          },
        ));
      }
      return;
    }

    // Título fornecido → busca textual em todos os ambientes
    final query    = result.triggerAction!;
    final triggers = await _searchAllTriggers(query);
    if (!mounted) return;

    if (triggers.isEmpty) {
      AppLogger.log('voice_delete', {
        'intent':        'delete_trigger',
        'trigger_title': query,
        'environment':   result.environmentName,
        'sucesso':       false,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(AppStrings.voiceTriggerDeleteNotFound),
        behavior: SnackBarBehavior.floating,
      ));
      await _speak('Não encontrei esse lembrete.'); // FIX 4
    } else if (triggers.length == 1) {
      // Fase 1 — único match encontrado por voz → confirma por voz antes de excluir
      await _confirmDeleteTrigger(triggers.first);
    } else {
      // Múltiplos matches → lista para o usuário escolher qual remover
      await _speak('Qual lembrete você quer remover? Toque em um deles.'); // FIX 4
      _showSheet(_DeleteTriggerPickerSheet(
        triggers: triggers,
        onSelected: (t) async {
          Navigator.pop(context);
          await _deleteTriggerDirectly(t);
        },
      ));
    }
  }

  // "apaga todos os gatilhos de X" → exibe confirmação antes de excluir.
  Future<void> _handleDeleteAllTriggers(VoiceResult result) async {
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final env  = _matchEnv(envs, result.environmentName);
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);

    if (env == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(AppStrings.voiceEnvNotFoundForDelete),
        behavior: SnackBarBehavior.floating,
      ));
      AppLogger.log('voice_delete', {
        'intent':        'delete_all_triggers',
        'environment':   result.environmentName,
        'trigger_title': null,
        'sucesso':       false,
      });
      return;
    }

    // Fase 1 — confirmação por voz (substitui _DeleteAllTriggersConfirmSheet).
    await _confirmByVoice(
      'Você deseja remover todos os lembretes de ${env.name}?',
      () => _reallyDeleteAllTriggers(env),
    );
  }

  // Remoção efetiva de todos os gatilhos do ambiente (após "sim" por voz).
  Future<void> _reallyDeleteAllTriggers(EnvironmentEntity env) async {
    // Busca e remove todos os triggers (ativos e inativos) do ambiente
    final all = await ref
        .read(triggerRepositoryProvider)
        .getByEnvironment(env.id);
    for (final t in all) {
      await ref.read(triggerRepositoryProvider).delete(t.id);
    }
    AppLogger.log('voice_delete', {
      'intent':        'delete_all_triggers',
      'environment':   env.name,
      'trigger_title': null,
      'sucesso':       true,
    });
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${AppStrings.voiceAllTriggersDeleted}: ${env.name}'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ));
    await _speak('Todos os lembretes de ${env.name} removidos.'); // FIX 4
  }

  // Fase 1 — "apagar todos os ambientes" / "limpar ambientes" / "apagar tudo".
  // Operação global e irreversível: sempre confirmada por voz, informando a
  // quantidade de ambientes afetados. Após "sim", remove todos os ambientes
  // (cascade apaga os gatilhos) e limpa os geofences nativos.
  Future<void> _handleDeleteAllEnvironments(VoiceResult result) async {
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);

    if (envs.isEmpty) {
      await _speak(AppStrings.voiceNoEnvsToDelete);
      return;
    }

    // %d → quantidade de ambientes que serão removidos
    final question = AppStrings.voiceConfirmDeleteAllEnvs
        .replaceFirst('%d', envs.length.toString());
    await _confirmByVoice(question, () => _reallyDeleteAllEnvironments(envs));
  }

  // Remoção efetiva de todos os ambientes (após "sim" por voz).
  // Não há "Desfazer" aqui — a confirmação por voz é a barreira de segurança.
  Future<void> _reallyDeleteAllEnvironments(List<EnvironmentEntity> envs) async {
    for (final env in envs) {
      // delete no repositório apaga os gatilhos por cascade
      await ref.read(environmentRepositoryProvider).delete(env.id);
    }
    // Limpa todos os geofences nativos de uma vez (app morto não dispara mais)
    try {
      await ref.read(nativeGeofenceServiceProvider).clearGeofences();
    } catch (e) {
      debugPrint('[_VoiceFab] clearGeofences falhou: $e');
    }
    AppLogger.log('voice_delete', {
      'intent':        'delete_all_environments',
      'environment':   null,
      'trigger_title': null,
      'sucesso':       true,
      'count':         envs.length,
    });
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:  Text(AppStrings.voiceAllEnvsDeletedSnack),
      behavior: SnackBarBehavior.floating,
    ));
    await _speak(AppStrings.voiceAllEnvsDeleted);
  }

  // Busca triggers ativos em TODOS os ambientes por título ou conteúdo
  Future<List<TriggerEntity>> _searchAllTriggers(String query) async {
    if (query.isEmpty) return [];
    final envs  = await ref.read(environmentRepositoryProvider).getAll();
    final lower = query.toLowerCase();
    final results = <TriggerEntity>[];
    for (final env in envs) {
      final triggers =
          await ref.read(triggerRepositoryProvider).getByEnvironment(env.id);
      results.addAll(triggers.where((t) =>
          t.isActive &&
          (t.title.toLowerCase().contains(lower) ||
              t.content.toLowerCase().contains(lower))));
    }
    return results;
  }

  // Abre um bottom sheet com configuração visual padrão do Sopro
  void _showSheet(Widget sheet) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => sheet,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // AnimatedScale: press feedback 0.96 (revertido em 200 ms)
        AnimatedScale(
          scale: _isVisuallyPressed ? 0.96 : 1.0,
          duration: AppMotion.micro,
          curve: AppMotion.snap,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown:   (_) => _onPressStart(),
            onPointerUp:     (_) => _onPressEnd(),
            onPointerCancel: (_) => _onPressCancel(),
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                // Pulso visível apenas durante gravação
                final scale = _isRecording ? _pulseAnim.value : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: _buildButtonBody(),
            ),
          ),
        ),

        // Contador de segundos: visível somente durante gravação
        if (_isRecording) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatSeconds(_recordingSeconds),
            style: AppTypography.caption.copyWith(
              color: AppColors.danger,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }

  // Constrói o corpo do botão conforme o estado atual — Dark Glass 72×72
  Widget _buildButtonBody() {
    Widget fabChild;
    Color  borderColor;

    switch (_fabState) {
      case _FabState.idle:
        fabChild    = const Icon(Icons.mic_rounded, color: AppColors.textPrimary, size: 30);
        borderColor = const Color(0x33FFFFFF); // white 20% — borda sutil sobre pink

      case _FabState.recording:
        fabChild    = const Icon(Icons.mic_rounded, color: AppColors.danger, size: 30);
        borderColor = const Color(0x66FF5B5B); // danger 40%

      case _FabState.processing:
        fabChild = const SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2.0,
            strokeCap: StrokeCap.round,
          ),
        );
        borderColor = AppColors.borderHighlight;

      case _FabState.success:
        fabChild    = const Icon(Icons.check_rounded, color: AppColors.success, size: 32);
        borderColor = const Color(0x5932D296); // success 35%

      case _FabState.error:
        fabChild    = const Icon(Icons.mic_off_rounded, color: AppColors.danger, size: 30);
        borderColor = const Color(0x40FF5B5B); // danger 25%
    }

    return SizedBox(
      width:  72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camada de glow — fora do ClipOval para não ser cortado pelo clip
          Container(
            width:  72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _isRecording
                      ? AppColors.fabGlowRecording
                      : AppColors.fabGlowIdle,
                  blurRadius:   _isRecording
                      ? AppShadows.fabRecording.blurRadius
                      : AppShadows.fabIdle.blurRadius,
                  spreadRadius: _isRecording
                      ? AppShadows.fabRecording.spreadRadius
                      : AppShadows.fabIdle.spreadRadius,
                ),
              ],
            ),
          ),
          // Conteúdo: idle=gradiente pink-red sólido, outros=glass escuro
          ClipOval(
            child: _fabState == _FabState.idle
                ? Container(
                    width:  72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.fabPinkStart, AppColors.fabPinkEnd],
                      ),
                      border: Border.all(color: borderColor, width: 0.75),
                    ),
                    child: Center(child: fabChild),
                  )
                : BackdropFilter(
                    // Corpo glass do FAB (estados não-idle) — mesmo tom premium.
                    // Mantido inline: círculo + borda variável por estado.
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      width:  72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x38FFFFFF), // white 22% — especular superior
                            Color(0x0AFFFFFF), // white 4%
                            Color(0x08FFFFFF), // white 3%
                          ],
                          stops: [0.0, 0.25, 1.0],
                        ),
                        border: Border.all(color: borderColor, width: 0.75),
                      ),
                      child: Center(child: fabChild),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // Formata segundos como "0:05" ou "1:02"
  String _formatSeconds(int s) {
    final min = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}

// ── Sheet: ambiente não encontrado ────────────────────────────────────────────

// Exibido quando o Gemini identifica um ambiente por nome mas ele não existe no banco.
// Oferece duas saídas: criar o ambiente agora (via GPS) ou escolher um existente.
class _EnvNotFoundSheet extends StatelessWidget {
  // Nome retornado pelo Gemini — exibido na mensagem explicativa
  final String envName;
  // Título do trigger que aguarda um ambiente — exibido como contexto
  final String triggerTitle;
  // "Criar ambiente agora" → GPS + salvar trigger automaticamente
  final VoidCallback onCreateNow;
  // "Escolher outro" → abre o seletor de ambientes existentes
  final VoidCallback onChooseOther;

  const _EnvNotFoundSheet({
    required this.envName,
    required this.triggerTitle,
    required this.onCreateNow,
    required this.onChooseOther,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = envName.isEmpty ? '?' : '"$envName"';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Alça visual do sheet
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),

            // Ícone representando localização ausente
            const Icon(
              Icons.location_off_outlined,
              color: AppTheme.textSecondary,
              size: 40,
            ),
            const SizedBox(height: AppSpacing.sm),

            // Mensagem principal
            Text(
              '$displayName ${AppStrings.voiceEnvNotExists}.',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            // Contexto: título do trigger que precisa ser salvo
            if (triggerTitle.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.gap6),
              Text(
                '"$triggerTitle"',
                style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            // Botão primário: usa GPS atual para criar o ambiente agora
            SoproPrimaryButton(
              label: AppStrings.voiceCreateEnvNow,
              onPressed: onCreateNow,
              icon: const Icon(Icons.add_location_alt_outlined),
            ),
            const SizedBox(height: AppSpacing.xxs),

            // Botão secundário: seleciona entre ambientes já existentes
            TextButton(
              onPressed: onChooseOther,
              child: const Text(
                AppStrings.voiceChooseOther,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Seletor de ambiente ────────────────────────────────────────────────────────

// Exibido quando o Gemini reconhece uma intenção mas o ambiente não é encontrado
// por nome. O usuário toca num ambiente da lista para escolher o destino da ação.
class _EnvPickerSheet extends ConsumerWidget {
  // Pergunta exibida no topo (ex: "Em qual ambiente?")
  final String title;
  // Ação reconhecida mostrada abaixo do título como contexto
  final String subtitle;
  // Executado quando o usuário toca num ambiente
  final void Function(EnvironmentEntity) onEnvSelected;

  const _EnvPickerSheet({
    required this.title,
    required this.subtitle,
    required this.onEnvSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envsAsync = ref.watch(environmentsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alça visual do sheet
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppTheme.textDisabled,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),

            Text(
              title,
              style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary),
            ),

            // Trecho do comando reconhecido para dar contexto ao usuário
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.gap6),
              Text(
                '"$subtitle"',
                style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.md),

            // Lista de ambientes cadastrados
            envsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
              error: (_, __) => const Text(
                AppStrings.errorGeneric,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              data: (envs) => envs.isEmpty
                  ? const Text(
                      AppStrings.homeEmptyTitle,
                      style: TextStyle(color: AppTheme.textSecondary),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: envs.length,
                      itemBuilder: (_, i) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: AppTheme.accent.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: AppTheme.accent,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          envs[i].name,
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onEnvSelected(envs[i]);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lista inline de triggers do ambiente ──────────────────────────────────────

// Exibido pela intenção "listar_triggers" sem navegar para outra tela.
// Mostra apenas os triggers ATIVOS do ambiente escolhido.
class _TriggerListSheet extends ConsumerWidget {
  final EnvironmentEntity environment;

  const _TriggerListSheet({required this.environment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<TriggerEntity>>(
      future: ref
          .read(triggerRepositoryProvider)
          .getActiveByEnvironment(environment.id),
      builder: (context, snap) {
        final triggers = snap.data ?? [];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Alça visual
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppTheme.textDisabled,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                  ),
                ),

                Text(
                  '${AppStrings.voiceTriggerListTitle} — ${environment.name}',
                  style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: AppSpacing.md),

                if (!snap.hasData)
                  const Center(
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  )
                else if (triggers.isEmpty)
                  const Text(
                    AppStrings.voiceNoTriggersPending,
                    style: TextStyle(color: AppTheme.textSecondary),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: triggers.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: AppTheme.backgroundSurface,
                    ),
                    itemBuilder: (_, i) {
                      final t = triggers[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.bolt_outlined,
                          color: AppTheme.accent,
                        ),
                        title: Text(
                          t.title.isNotEmpty ? t.title : t.content,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: t.title.isNotEmpty
                            ? Text(
                                t.content,
                                style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Sheet de fallback (intenção não reconhecida) ──────────────────────────────

// Exibido quando o Gemini retorna "nao_entendido".
// O usuário pode editar o texto e re-analisar para corrigir erros de STT.
// Fase 1 — mantido no código para referência/rollback, mas NÃO é mais usado:
// o fluxo "não entendi" agora responde só por voz (ver _handleFallback).
// ignore: unused_element
class _FallbackSheet extends ConsumerStatefulWidget {
  // Transcrição retornada pelo Gemini (pode ser vazia se STT falhou)
  final String transcript;
  // Callback com o resultado re-analisado para execução
  final void Function(VoiceResult) onResult;

  const _FallbackSheet({
    required this.transcript,
    required this.onResult,
  });

  @override
  ConsumerState<_FallbackSheet> createState() => _FallbackSheetState();
}

class _FallbackSheetState extends ConsumerState<_FallbackSheet> {
  late final TextEditingController _ctrl;
  bool _reanalyzing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.transcript);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // CORRECAO 2: Envia o texto editado ao Gemini para nova tentativa de classificação,
  // passando a lista de ambientes existentes para o modelo retornar o nome exato.
  Future<void> _reanalyze() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _reanalyzing = true);
    try {
      final envs     = await ref.read(environmentRepositoryProvider).getAll();
      final envNames = envs.map((e) => e.name).toList();
      final result   = await ref.read(voiceServiceProvider).resolveIntentFromText(
        text,
        existingEnvironments: envNames,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onResult(result);
    } finally {
      if (mounted) setState(() => _reanalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 16, 20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Alça visual
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
          ),

          Text(
            AppStrings.voiceIntentFallback,
            style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: AppSpacing.gap6),
          // Exemplos de comandos para guiar o usuário na re-digitação
          const Text(
            AppStrings.voiceExamples,
            style: TextStyle(
              color: AppTheme.textDisabled,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Campo de texto editável com a transcrição do Gemini
          SoproTextField(
            controller: _ctrl,
            label: AppStrings.voiceTranscriptLabel,
            maxLines: 3,
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.md),

          // Botão de re-análise: chama Gemini com o texto corrigido
          SoproPrimaryButton(
            label: AppStrings.voiceReanalyze,
            onPressed: _reanalyzing ? null : _reanalyze,
            loading: _reanalyzing,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

// ── Lista inline de todos os ambientes ───────────────────────────────────────

// Exibido pela intenção "list_environments" sem navegar para outra tela.
// Mostra nome e raio de cada ambiente cadastrado.
class _EnvsListSheet extends ConsumerWidget {
  const _EnvsListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envsAsync = ref.watch(environmentsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppTheme.textDisabled,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),
            Text(
              AppStrings.voiceEnvListTitle,
              style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),

            envsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
              error: (_, __) => const Text(
                AppStrings.errorGeneric,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              data: (envs) => envs.isEmpty
                  ? const Text(
                      AppStrings.homeEmptyTitle,
                      style: TextStyle(color: AppTheme.textSecondary),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: envs.length,
                      itemBuilder: (_, i) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: AppTheme.accent.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: AppTheme.accent,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          envs[i].name,
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        subtitle: Text(
                          '${envs[i].radiusMeters.toInt()} m de raio',
                          style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet: confirmação de exclusão de ambiente ────────────────────────────────
//
// Unica ação de voz que exige confirmação — remoção de ambiente é irreversível
// (exclui o ambiente e todos os seus gatilhos em cascade).
// ── Sheet: picker de trigger para exclusão ────────────────────────────────────
//
// Exibido quando a busca por título retorna múltiplos triggers.
// O usuário toca no trigger que deseja remover.
class _DeleteTriggerPickerSheet extends StatelessWidget {
  final List<TriggerEntity> triggers;
  final void Function(TriggerEntity) onSelected;

  const _DeleteTriggerPickerSheet({
    required this.triggers,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alça do sheet
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppTheme.textDisabled,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),

            Text(
              AppStrings.voiceDeletePickerTitle,
              style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),

            // Lista de triggers correspondentes à busca
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: triggers.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1, color: AppTheme.backgroundSurface,
              ),
              itemBuilder: (_, i) {
                final t = triggers[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  // Ícone de lixeira para reforçar a ação
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppTheme.accent,
                  ),
                  title: Text(
                    t.title.isNotEmpty ? t.title : t.content,
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                  subtitle: t.title.isNotEmpty && t.content.isNotEmpty
                      ? Text(
                          t.content,
                          style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => onSelected(t),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet: confirmação de exclusão de todos os gatilhos ───────────────────────

// Fase 1 — substituído por confirmação de voz (ver _confirmByVoice). Mantido
// para referência/rollback; não é mais instanciado.
// ignore: unused_element
class _DeleteAllTriggersConfirmSheet extends StatelessWidget {
  final EnvironmentEntity environment;
  final VoidCallback onConfirm;

  const _DeleteAllTriggersConfirmSheet({
    required this.environment,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Alça do sheet
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),

            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.accent, size: 44),
            const SizedBox(height: AppSpacing.sm),

            Text(
              AppStrings.voiceDeleteAllTitle,
              style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),

            Text(
              'Todos os gatilhos de "${environment.name}" '
              'serão removidos. Esta ação não pode ser desfeita.',
              style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            SoproPrimaryButton(
              label: AppStrings.confirm,
              onPressed: onConfirm,
            ),
            const SizedBox(height: AppSpacing.xxs),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                AppStrings.cancel,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Estado vazio da lista de ambientes ───────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Anel externo: glow radial difuso
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring
                  Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0x1A4F8CFF), // accent 10%
                          Color(0x004F8CFF), // transparent
                        ],
                      ),
                    ),
                  ),
                  // Inner glass circle
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x14FFFFFF), // white 8% — glass tint
                      border: Border.fromBorderSide(
                        BorderSide(color: AppColors.border, width: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.air,
                      size: 36,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Text(
              AppStrings.homeEmptyTitle,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.homeEmptySubtitle,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textDisabled,
                height: 1.65,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

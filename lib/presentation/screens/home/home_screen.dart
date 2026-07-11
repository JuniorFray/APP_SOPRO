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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../domain/entities/trigger_entity.dart';
import '../../../infrastructure/logging/app_logger.dart';
import '../../../infrastructure/voice/voice_service.dart';
import '../../providers/database_provider.dart';
import '../../providers/environment_providers.dart';
import '../../providers/trigger_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/environment_card.dart';
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
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
      );
    }

    final environmentsAsync = ref.watch(environmentsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        // 0.04em de letter-spacing no título "Sopro" — identidade visual do app
        title: const Text(
          AppStrings.homeTitle,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: 0.8, // 0.04 × 20sp
          ),
        ),
        backgroundColor: AppTheme.backgroundSurface,
        actions: [
          // Abre a tela de BLE Social ("Pessoas Aqui")
          IconButton(
            onPressed: () => pushScreen(context, const PeopleNearbyScreen()),
            icon: const Icon(Icons.people_outline),
            tooltip: AppStrings.peopleNearby,
          ),
          // Abre a tela de perfil (ContextCard)
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.person_outline),
            tooltip: AppStrings.profileTooltip,
          ),
          // Abre a tela de configurações
          IconButton(
            onPressed: () => pushScreen(context, const SettingsScreen()),
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppStrings.settingsTooltip,
          ),
        ],
      ),
      body: environmentsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
        error: (e, _) => const Center(
          child: Text(
            AppStrings.errorGeneric,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        data: (environments) => environments.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
          // FAB de voz redesenhado — 64 dp, hold=gravar, arrastar=cancelar
          const _VoiceFab(),
          const SizedBox(height: AppSpacing.md),
          // FAB principal — cria novo ambiente
          FloatingActionButton.extended(
            onPressed: () => pushScreen(context, const AddEnvironmentScreen()),
            backgroundColor: AppTheme.accent,
            foregroundColor: AppColors.textPrimary,
            heroTag: 'add_env_fab',
            icon: const Icon(Icons.add),
            label: const Text(AppStrings.newEnvironment),
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
  // Segurança: FAB encerra após 30 s caso o VoiceService (10 s) não dispare
  static const _maxSeconds = 30;

  // Subscription ao stream de auto-stop do VoiceService (silêncio / max duration)
  StreamSubscription<void>? _autoStopSub;

  // Momento em que o dedo pressionou o botão — usado para verificar mínimo de 500 ms
  DateTime? _pressStartTime;

  // Canal de comunicação com o FloatingVoiceService (overlay nativo)
  static const _overlayChannel = MethodChannel('com.sopro.sopro/overlay');

  // FIX 4: quando true, a próxima gravação captura o nome do ambiente.
  // Ativado por _handleOpenEnvironment quando Gemini não retorna environmentName.
  bool _pendingEnvCreate = false;

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
    setState(() { _fabState = _FabState.recording; _recordingSeconds = 0; });
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
  void _onPressCancel() => _cancelRecording();

  // ── Ciclo de gravação ──────────────────────────────────────────────────────

  // Ativa o microfone nativo (async). Estado e timer já foram configurados
  // em _onLongPressStart — este método só precisa lidar com falha de init.
  Future<void> _startRecording() async {
    final service = ref.read(voiceServiceProvider);
    final ok      = await service.startRecording();
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

    try {
      // 300 ms de feedback visual antes de chamar o Gemini
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      // CORRECAO 2: busca nomes dos ambientes antes de chamar o Gemini
      // para que o modelo retorne o nome EXATO como está no banco
      final envs     = await ref.read(environmentRepositoryProvider).getAll();
      final envNames = envs.map((e) => e.name).toList();

      final result = await service.processAudio(
        filePath,
        existingEnvironments: envNames,
      );
      if (!mounted) return;

      // FIX 4: se estava aguardando nome de ambiente, trata o áudio como nome
      if (_pendingEnvCreate) {
        _pendingEnvCreate = false;
        // Gemini pode ter entendido create_environment com nome, ou retornado fallback
        // com o nome como transcript. Em ambos os casos extraímos o melhor nome disponível.
        final envName = (result.intent == VoiceIntent.createEnvironment &&
                (result.environmentName?.isNotEmpty ?? false))
            ? result.environmentName!
            : result.transcript.trim();
        if (envName.isNotEmpty) {
          await _handleOpenEnvironment(VoiceResult(
            intent:          VoiceIntent.createEnvironment,
            transcript:      result.transcript,
            environmentName: envName,
          ));
          return;
        }
        // Nome ainda vazio após segunda gravação → fallback normal
      }

      await _executeResult(result);
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

  // ── Auto-execução de intenções (zero confirmação) ─────────────────────────

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
      case VoiceIntent.fallback:
        await _handleFallback(result);
    }
  }

  // Busca ambiente por nome: case-insensitive, correspondência parcial (CONTAINS).
  // Tenta exact match primeiro para evitar ambiguidades em listas grandes.
  EnvironmentEntity? _matchEnv(List<EnvironmentEntity> envs, String? query) {
    if (query == null || query.trim().isEmpty) return null;
    final q = query.toLowerCase().trim();
    // 1. Correspondência exata (case-insensitive)
    final exact = envs.where((e) => e.name.toLowerCase() == q).firstOrNull;
    if (exact != null) return exact;
    // 2. Env name CONTAINS query ou vice-versa ("casa" → "Minha Casa")
    return envs
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            q.contains(e.name.toLowerCase()))
        .firstOrNull;
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
      final loc = await ref
          .read(nativeLocationServiceProvider)
          .getCurrentPosition();
      if (loc == null) return null;

      final env = EnvironmentEntity(
        id:           const Uuid().v4(),
        name:         _capitalize(name),
        latitude:     loc.latitude,
        longitude:    loc.longitude,
        radiusMeters: radiusMeters.toDouble(),
        createdAt:    DateTime.now(),
      );
      await ref.read(environmentRepositoryProvider).save(env);

      // Registra no GeofencingClient imediatamente e loga native_geofence_added
      await ref.read(nativeGeofenceServiceProvider).addSingleGeofence(env);

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
  Future<void> _handleFallback(VoiceResult result) async {
    if (!mounted) return;
    setState(() => _fabState = _FabState.idle);
    await _speak('Não entendi. Pode repetir ou digitar o que precisa?'); // FIX 4
    _showSheet(_FallbackSheet(
      transcript: result.transcript,
      // Re-executa a ação com a intenção re-analisada pelo usuário + Gemini
      onResult:   (newResult) => _executeResult(newResult),
    ));
  }

  // ── Handlers de exclusão por voz ──────────────────────────────────────────

  // "exclui o ambiente X" → deleta imediatamente + SnackBar "Desfazer" (5s).
  // FIX 1: sem confirmação — UX mais fluido, desfazer restaura tudo.
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
          await _deleteTriggerDirectly(triggers.first);
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
      // Único match → exclui sem pedir confirmação
      await _deleteTriggerDirectly(triggers.first);
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

    // Confirmação antes de remover todos os gatilhos
    _showSheet(_DeleteAllTriggersConfirmSheet(
      environment: env,
      onConfirm: () async {
        Navigator.pop(context);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppStrings.voiceAllTriggersDeleted}: ${env.name}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ));
        await _speak('Todos os lembretes de ${env.name} removidos.'); // FIX 4
      },
    ));
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
        // Listener usa PointerDown/PointerUp — eventos de baixo nível do SO,
        // sem threshold de tempo. Mais confiável que GestureDetector no Android.
        Listener(
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

        // Contador de segundos: visível somente durante gravação
        if (_isRecording) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatSeconds(_recordingSeconds),
            style: const TextStyle(
              color: AppColors.danger,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  // Constrói o corpo do botão conforme o estado atual
  Widget _buildButtonBody() {
    final Color  bgColor;
    final Widget child;

    switch (_fabState) {
      case _FabState.idle:
        bgColor = AppTheme.accent;
        child   = const Icon(Icons.mic_rounded, color: AppColors.textPrimary, size: 28);

      case _FabState.recording:
        bgColor = AppColors.danger; // vermelho durante gravação
        child   = const Icon(Icons.mic_rounded, color: AppColors.textPrimary, size: 28);

      case _FabState.processing:
        bgColor = AppTheme.accent;
        child   = const SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(
            color: AppColors.textPrimary, strokeWidth: 2.5,
          ),
        );

      case _FabState.success:
        bgColor = AppColors.fabSuccessDark; // verde escuro
        child   = const Icon(Icons.check_rounded, color: AppColors.textPrimary, size: 32);

      case _FabState.error:
        bgColor = AppColors.snackbarDanger;
        child   = const Icon(Icons.mic_off_rounded, color: AppColors.textPrimary, size: 28);
    }

    return Container(
      width:  64,
      height: 64,
      decoration: BoxDecoration(
        color:  bgColor,
        shape:  BoxShape.circle,
        boxShadow: [
          BoxShadow(
            // Glow suave: rgba(232,68,90,0.35) em idle, mais intenso ao gravar
            color: _isRecording
                ? AppColors.fabGlowRecording  // vermelho de gravação 55% opacity
                : AppColors.fabGlowIdle,      // accent 35% opacity — glow padrão
            blurRadius:   _isRecording ? 18 : 12,
            spreadRadius: _isRecording ? 3  : 1,
          ),
        ],
      ),
      child: Center(child: child),
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.air, size: 80, color: AppTheme.accent),
          SizedBox(height: AppSpacing.xl),
          Text(
            AppStrings.homeEmptyTitle,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.homeEmptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

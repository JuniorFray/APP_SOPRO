// HomeScreen — Tela principal do Sopro.
//
// Responsabilidades:
//   1. Verificar primeiro acesso via SharedPreferences ('onboarding_done'):
//      - false → pushReplacementNamed('/onboarding') — sem await, sem recursão
//      - true  → inicia geofences e exibe a tela normalmente
//   2. Listar ambientes cadastrados pelo usuário
//   3. Navegar para PeopleNearbyScreen e ProfileScreen
//   4. FAB secundário de voz: abre _VoiceBottomSheet para comandos por fala

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/trigger_entity.dart';
import '../../providers/database_provider.dart';
import '../../providers/environment_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/environment_card.dart';
import '../ble/people_nearby_screen.dart';
import '../environment/add_environment_screen.dart';
import '../environment/environment_detail_screen.dart';
import '../settings/settings_screen.dart';
import '../../../infrastructure/voice/voice_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // false enquanto verifica o flag de onboarding e inicia serviços
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Executa depois do primeiro frame para que o Navigator esteja disponível
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnboarding());
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

  // Abre o bottom sheet de interação por voz
  void _openVoiceSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _VoiceBottomSheet(onResult: _handleVoiceResult),
    );
  }

  // Executa a ação correspondente ao resultado de voz confirmado pelo usuário.
  // Navega para a tela adequada conforme a intenção detectada.
  Future<void> _handleVoiceResult(VoiceResult result) async {
    if (!mounted) return;

    switch (result.intent) {
      // Lembra de [ação] quando eu chegar em [ambiente]
      case VoiceIntent.createTrigger:
        final envs = await ref.read(environmentRepositoryProvider).getAll();
        final query = result.environmentName?.toLowerCase() ?? '';
        final env = envs
            .where((e) =>
                e.name.toLowerCase().contains(query) ||
                (query.isNotEmpty && query.contains(e.name.toLowerCase())))
            .firstOrNull;
        if (env != null && mounted) {
          pushScreen(context, EnvironmentDetailScreen(environment: env));
        } else if (mounted) {
          // Ambiente não encontrado: cria um novo
          pushScreen(
            context,
            AddEnvironmentScreen(
              initialName: _capitalize(result.environmentName ?? ''),
            ),
          );
        }

      // Salva esse lugar como [nome] / Cria um ambiente aqui chamado [nome]
      case VoiceIntent.openEnvironment:
        if (mounted) {
          pushScreen(
            context,
            AddEnvironmentScreen(
              initialName: result.environmentName ?? '',
            ),
          );
        }

      // Resolvi [título] / Pode apagar [título]
      case VoiceIntent.resolveTrigger:
        final triggers = await _searchAllTriggers(result.triggerAction ?? '');
        if (triggers.isNotEmpty && mounted) {
          final first = triggers.first;
          await ref
              .read(triggerRepositoryProvider)
              .setActive(first.id, active: false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Gatilho "${first.title.isNotEmpty ? first.title : first.content}" desativado',
                ),
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gatilho "${result.triggerAction}" não encontrado',
              ),
            ),
          );
        }

      // O que tenho pendente em [ambiente]?
      case VoiceIntent.listTriggers:
        final envs = await ref.read(environmentRepositoryProvider).getAll();
        final query = result.environmentName?.toLowerCase() ?? '';
        final env = envs
            .where((e) =>
                e.name.toLowerCase().contains(query) ||
                (query.isNotEmpty && query.contains(e.name.toLowerCase())))
            .firstOrNull;
        if (env != null && mounted) {
          pushScreen(context, EnvironmentDetailScreen(environment: env));
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Ambiente "${result.environmentName}" não encontrado',
              ),
            ),
          );
        }

      // Texto livre não classificado
      case VoiceIntent.fallback:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:  Text('Selecione um ambiente para: "${result.transcript}"'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
    }
  }

  // Busca triggers em todos os ambientes cujo título ou conteúdo contenha [query].
  Future<List<TriggerEntity>> _searchAllTriggers(String query) async {
    if (query.isEmpty) return [];
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final lower = query.toLowerCase();
    final results = <TriggerEntity>[];
    for (final env in envs) {
      final triggers =
          await ref.read(triggerRepositoryProvider).getByEnvironment(env.id);
      results.addAll(triggers.where((t) =>
          t.title.toLowerCase().contains(lower) ||
          t.content.toLowerCase().contains(lower)));
    }
    return results;
  }

  // Capitaliza a primeira letra da string
  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
        title: const Text(AppStrings.homeTitle),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: environments.length,
                itemBuilder: (_, i) =>
                    EnvironmentCard(environment: environments[i]),
              ),
      ),
      // FABs empilhados: microfone secundário acima do botão principal
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // FAB secundário — abre interação por voz
          FloatingActionButton.small(
            onPressed: _openVoiceSheet,
            backgroundColor: AppTheme.backgroundSurface,
            foregroundColor: AppTheme.accent,
            heroTag: 'voice_fab',
            tooltip: AppStrings.voiceMicTooltip,
            child: const Icon(Icons.mic_outlined),
          ),
          const SizedBox(height: 12),
          // FAB principal — cria novo ambiente
          FloatingActionButton.extended(
            onPressed: () => pushScreen(context, const AddEnvironmentScreen()),
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            heroTag: 'add_env_fab',
            icon: const Icon(Icons.add),
            label: const Text(AppStrings.newEnvironment),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet de interação por voz ─────────────────────────────────────────

// Exibe animação de ondas sonoras enquanto escuta, mostra a transcrição em
// tempo real e, ao finalizar, apresenta a intenção reconhecida para confirmação.
class _VoiceBottomSheet extends ConsumerStatefulWidget {
  // Callback chamado quando o usuário confirma a ação reconhecida
  final void Function(VoiceResult) onResult;

  const _VoiceBottomSheet({required this.onResult});

  @override
  ConsumerState<_VoiceBottomSheet> createState() => _VoiceBottomSheetState();
}

class _VoiceBottomSheetState extends ConsumerState<_VoiceBottomSheet> {
  // true enquanto o AudioRecorder está gravando ativamente
  bool _isRecording = false;
  // true enquanto o Gemini processa o áudio enviado (spinner)
  bool _processing  = false;
  // true após Gemini retornar resultado e bottom sheet mostrar ação
  bool _processed   = false;
  // true se permissão de microfone foi negada
  bool _unavailable = false;
  // Resultado final com intenção detectada e transcrição do Gemini
  VoiceResult? _result;
  // Segundos gravados — mostrado no contador durante gravação
  int _recordingSeconds = 0;
  // Timer que incrementa _recordingSeconds a cada segundo
  Timer? _recordingTimer;
  // Limite de gravação automático (30 s) para evitar arquivos gigantes
  static const _maxRecordingSeconds = 30;
  // Controller do campo editável de transcrição no estado de resultado.
  // Permite corrigir a transcrição do Gemini e re-analisar.
  final _transcriptController = TextEditingController();

  @override
  void dispose() {
    // Para gravação se o sheet for fechado durante gravação
    _recordingTimer?.cancel();
    ref.read(voiceServiceProvider).cancelRecording();
    _transcriptController.dispose();
    super.dispose();
  }

  // Inicia gravação ao pressionar o botão (onPointerDown).
  Future<void> _startRecording() async {
    if (_isRecording || _processing) return;
    final service = ref.read(voiceServiceProvider);
    final ok      = await service.startRecording();
    if (!mounted) return;
    if (!ok) {
      // Permissão negada ou microfone indisponível
      setState(() => _unavailable = true);
      return;
    }
    setState(() {
      _isRecording      = true;
      _recordingSeconds = 0;
    });
    // Conta os segundos e aplica limite máximo de 30 s
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= _maxRecordingSeconds) {
        t.cancel();
        // Tempo máximo atingido — processa automaticamente
        _stopAndProcess();
      }
    });
  }

  // Para gravação ao soltar o botão (onPointerUp) e envia ao Gemini.
  Future<void> _stopAndProcess() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() {
      _isRecording = false;
      _processing  = true;
    });
    // Para gravação e obtém o caminho do arquivo
    final service  = ref.read(voiceServiceProvider);
    final filePath = await service.stopRecording();
    if (!mounted) return;

    if (filePath == null) {
      setState(() { _processing = false; _processed = true; });
      return;
    }

    // Envia áudio ao Gemini Audio API
    try {
      final result = await service.processAudio(filePath);
      if (!mounted) return;
      // Preenche o campo editável com a transcrição do Gemini
      _transcriptController.text = result.transcript;
      setState(() {
        _result     = result;
        _processing = false;
        _processed  = true;
      });
      // TTS: fala a confirmação se o toggle estiver ativo
      final audioOn    = ref.read(voiceAudioResponseProvider);
      final speechRate = ref.read(voiceSpeechRateProvider);
      if (audioOn && result.intent != VoiceIntent.fallback) {
        service.speak(_intentLabel(result), rate: speechRate);
      }
    } catch (e) {
      debugPrint('[VoiceBottomSheet] Erro ao processar áudio: $e');
      if (mounted) setState(() { _processing = false; _processed = true; });
    }
  }

  // Cancela gravação sem processar (ex.: sheet fechado com PointerCancel).
  void _cancelRecording() {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    ref.read(voiceServiceProvider).cancelRecording();
    if (mounted) setState(() { _isRecording = false; });
  }

  // Reinicia o sheet para o estado inicial (botão "Tentar novamente").
  void _reset() {
    _transcriptController.clear();
    setState(() {
      _isRecording      = false;
      _processing       = false;
      _processed        = false;
      _unavailable      = false;
      _result           = null;
      _recordingSeconds = 0;
    });
  }

  // Re-analisa o texto editado manualmente no campo de transcrição.
  // Usa Gemini Text API com fallback regex — sem nova gravação.
  Future<void> _reanalyze() async {
    final text = _transcriptController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _processing = true;
      _processed  = false;
      _result     = null;
    });
    try {
      final service = ref.read(voiceServiceProvider);
      final result  = await service.resolveIntentFromText(text);
      if (!mounted) return;
      setState(() {
        _result     = result;
        _processing = false;
        _processed  = true;
      });
      final audioOn = ref.read(voiceAudioResponseProvider);
      if (audioOn && result.intent != VoiceIntent.fallback) {
        service.speak(_intentLabel(result),
            rate: ref.read(voiceSpeechRateProvider));
      }
    } catch (e) {
      if (mounted) setState(() { _processing = false; _processed = true; });
    }
  }

  // Confirma a ação detectada e fecha o sheet
  void _confirm() {
    final result = _result;
    if (result == null) return;
    Navigator.pop(context);
    widget.onResult(result);
  }

  // Label curto falado/exibido ao reconhecer a intenção
  String _intentLabel(VoiceResult r) {
    switch (r.intent) {
      case VoiceIntent.createTrigger:
        return r.environmentName != null
            ? 'Criar gatilho para ${r.environmentName}'
            : AppStrings.voiceIntentCreate;
      case VoiceIntent.openEnvironment:
        return r.environmentName != null
            ? 'Criar ambiente ${r.environmentName}'
            : AppStrings.voiceIntentEnv;
      case VoiceIntent.resolveTrigger:
        return r.triggerAction != null
            ? 'Desativar ${r.triggerAction}'
            : AppStrings.voiceIntentResolve;
      case VoiceIntent.listTriggers:
        return r.environmentName != null
            ? 'Pendências em ${r.environmentName}'
            : AppStrings.voiceIntentList;
      case VoiceIntent.fallback:
        return AppStrings.voiceIntentFallback;
    }
  }

  // Ícone representativo de cada intenção
  IconData _intentIcon(VoiceIntent intent) {
    switch (intent) {
      case VoiceIntent.createTrigger:   return Icons.bolt_outlined;
      case VoiceIntent.openEnvironment: return Icons.add_location_outlined;
      case VoiceIntent.resolveTrigger:  return Icons.check_circle_outlined;
      case VoiceIntent.listTriggers:    return Icons.list_outlined;
      case VoiceIntent.fallback:        return Icons.edit_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 20, 20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Alça visual do sheet
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppTheme.textDisabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          if (_unavailable) ...[
            // ── Erro: microfone indisponível ─────────────────────────────
            const Icon(Icons.mic_off_outlined, color: AppTheme.accent, size: 48),
            const SizedBox(height: 12),
            const Text(
              AppStrings.voiceNotAvailable,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.accent),
                ),
                child: const Text(AppStrings.voiceClose),
              ),
            ),

          ] else if (_processing) ...[
            // ── Processando: aguarda Gemini Audio ─────────────────────────
            const Text(
              AppStrings.voiceProcessing,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 16),
            Text(
              'Analisando ${_recordingSeconds}s de áudio...',
              style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),

          ] else if (_processed) ...[
            // ── Resultado: transcrição + intenção ─────────────────────────
            const Text(
              AppStrings.voiceResultTitle,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Campo editável com a transcrição do Gemini.
            // O usuário pode corrigir e tocar ↺ para re-analisar.
            TextField(
              controller: _transcriptController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText:  AppStrings.voiceTranscriptLabel,
                labelStyle: const TextStyle(color: AppTheme.textSecondary),
                filled:     true,
                fillColor:  AppTheme.backgroundSurface,
                border:     OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                // Botão de re-análise: processa o texto editado
                suffixIcon: IconButton(
                  icon:    const Icon(Icons.refresh, size: 20),
                  color:   AppTheme.accent,
                  tooltip: AppStrings.voiceReanalyze,
                  onPressed: _reanalyze,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Card com a ação reconhecida
            if (_result != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _intentIcon(_result!.intent),
                        color: AppTheme.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _intentLabel(_result!),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Botões: Tentar novamente | Confirmar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.backgroundElevated),
                    ),
                    child: const Text(AppStrings.voiceRetry),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _result != null ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      AppStrings.voiceConfirm,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),

          ] else ...[
            // ── Idle: botão de gravação (segure para gravar) ─────────────
            const Text(
              AppStrings.voiceHoldToSpeak,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              // Mostra "Gravando... Xs" quando _isRecording, senão dica de exemplos
              _isRecording
                  ? AppStrings.voiceListeningHint  // "Solte para processar"
                  : AppStrings.voiceExamples,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isRecording ? AppTheme.accent : AppTheme.textDisabled,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Botão de gravação: segure para gravar, solte para processar.
            // Listener captura pointer events antes do GestureDetector do sheet.
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _startRecording(),
              onPointerUp:   (_) => _stopAndProcess(),
              onPointerCancel: (_) => _cancelRecording(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  88,
                height: 88,
                decoration: BoxDecoration(
                  // Vermelho quando gravando, accent quando idle
                  color: _isRecording
                      ? const Color(0xFFE53935)
                      : AppTheme.accent,
                  shape: BoxShape.circle,
                  boxShadow: _isRecording
                      ? [BoxShadow(
                          color: const Color(0xFFE53935).withOpacity(0.5),
                          blurRadius: 20, spreadRadius: 4,
                        )]
                      : [],
                ),
                child: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size:  40,
                ),
              ),
            ),

            // Contador de segundos durante gravação
            if (_isRecording) ...[
              const SizedBox(height: 12),
              Text(
                '$_recordingSeconds s',
                style: const TextStyle(
                  color: Color(0xFFE53935),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.air, size: 80, color: AppTheme.accent),
          SizedBox(height: 24),
          Text(
            AppStrings.homeEmptyTitle,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
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

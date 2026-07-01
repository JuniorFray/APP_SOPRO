// HomeScreen — Tela principal do Sopro.
//
// Responsabilidades:
//   1. Verificar primeiro acesso via SharedPreferences ('onboarding_done'):
//      - false → pushReplacementNamed('/onboarding') — sem await, sem recursão
//      - true  → inicia geofences e exibe a tela normalmente
//   2. Listar ambientes cadastrados pelo usuário
//   3. Navegar para PeopleNearbyScreen e ProfileScreen
//   4. FAB secundário de voz: abre _VoiceBottomSheet para comandos por fala

import 'dart:math';

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
  // Texto transcrito pelo STT (parcial durante escuta, final ao terminar)
  String _transcript = '';
  // true enquanto o engine STT está escutando ativamente
  bool _listening = false;
  // true após STT devolver resultado final E Gemini/regex terminarem
  bool _processed = false;
  // true enquanto Gemini (ou regex) processa a transcrição (spinner)
  bool _processing = false;
  // true se o STT não estiver disponível no dispositivo
  bool _unavailable = false;
  // Resultado final com intenção detectada
  VoiceResult? _result;
  // Nível de som atual para animação de ondas (0.0 – 1.0+)
  double _soundLevel = 0;

  @override
  void initState() {
    super.initState();
    // Inicia escuta imediatamente ao abrir o sheet
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    ref.read(voiceServiceProvider).stopListening();
    super.dispose();
  }

  Future<void> _startListening() async {
    // Reseta todos os estados antes de iniciar nova escuta
    setState(() {
      _transcript = '';
      _listening  = false;
      _processed  = false;
      _processing = false;
      _result     = null;
      _soundLevel = 0;
    });

    final service = ref.read(voiceServiceProvider);
    final ok = await service.startListening(
      onPartial:    (t) => setState(() => _transcript = t),
      onFinal:      _onFinal,
      onSoundLevel: (l) => setState(() => _soundLevel = l),
    );

    if (ok) {
      setState(() => _listening = true);
    } else {
      // STT não disponível no dispositivo
      setState(() => _unavailable = true);
    }
  }

  // Chamado quando o STT entrega o resultado final (sem mais parciais).
  // Inicia o processamento assíncrono de intenção (Gemini ou regex).
  void _onFinal(String transcript) {
    setState(() {
      _listening   = false;
      _transcript  = transcript;
      // Mostra spinner enquanto Gemini/regex processa
      _processing  = true;
    });
    // Despacha resolução assíncrona — não bloqueia a UI
    _resolveIntent(transcript);
  }

  // Processa a intenção via Gemini (com fallback para regex).
  // Atualiza _result e libera o spinner ao terminar.
  Future<void> _resolveIntent(String transcript) async {
    if (transcript.trim().isEmpty) {
      // Nada a processar — fecha spinner sem resultado
      if (mounted) setState(() { _processing = false; _processed = true; });
      return;
    }
    try {
      final service = ref.read(voiceServiceProvider);
      // resolveIntent: tenta Gemini primeiro, fallback regex
      final result  = await service.resolveIntent(transcript);
      if (!mounted) return;
      setState(() {
        _result     = result;
        _processing = false;
        _processed  = true;
      });
      // TTS: fala a confirmação se o toggle estiver ativo
      final audioOn    = ref.read(voiceAudioResponseProvider);
      final speechRate = ref.read(voiceSpeechRateProvider);
      if (audioOn) service.speak(_intentLabel(result), rate: speechRate);
    } catch (e) {
      // Erro inesperado — fecha spinner sem travar a UI
      debugPrint('[VoiceBottomSheet] Erro ao resolver intenção: $e');
      if (mounted) setState(() { _processing = false; _processed = true; });
    }
  }

  // Confirma a ação e fecha o sheet
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
    final textOn = ref.watch(voiceTextResponseProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 20, 20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Alça visual
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppTheme.textDisabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          if (_unavailable) ...[
            // STT não disponível no dispositivo
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
            // Estado: processando com Gemini ou regex (spinner)
            const Text(
              AppStrings.voiceProcessing,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Spinner circular enquanto aguarda resposta da API
            const CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 24),
            // Mostra o que foi ouvido para o usuário confirmar visualmente
            if (_transcript.isNotEmpty)
              Text(
                '"$_transcript"',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            const SizedBox(height: 8),
          ] else if (!_processed) ...[
            // Estado: escutando
            const Text(
              AppStrings.voiceListeningTitle,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              AppStrings.voiceListeningHint,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // Animação de ondas sonoras
            _SoundWave(active: _listening, soundLevel: _soundLevel),
            const SizedBox(height: 24),

            // Transcrição parcial em tempo real
            AnimatedOpacity(
              opacity: _transcript.isNotEmpty ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: Text(
                _transcript.isNotEmpty ? _transcript : AppStrings.voiceExamples,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _transcript.isNotEmpty
                      ? AppTheme.textPrimary
                      : AppTheme.textDisabled,
                  fontSize: _transcript.isNotEmpty ? 15 : 12,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botão para parar a escuta manualmente e iniciar processamento
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(voiceServiceProvider).stopListening();
                if (_transcript.isNotEmpty) {
                  // _onFinal inicia o spinner e chama _resolveIntent assíncrono
                  _onFinal(_transcript);
                } else {
                  // Nada foi ouvido → volta ao estado de escuta
                  setState(() => _listening = false);
                }
              },
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('Parar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.accent),
              ),
            ),
          ] else ...[
            // Estado: resultado processado
            const Text(
              AppStrings.voiceResultTitle,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Card mostrando a intenção detectada
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
                      width: 44,
                      height: 44,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _intentLabel(_result!),
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (textOn && _transcript.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '"$_transcript"',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _startListening,
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
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Animação de ondas sonoras ─────────────────────────────────────────────────

// Cinco barras verticais com animação senoidal desfasada que pulsam
// enquanto o microfone está ativo. A altura é modulada pelo nível de som.
class _SoundWave extends StatefulWidget {
  final bool active;
  // Nível de som em dB do STT, tipicamente de -2.0 a 10.0+
  final double soundLevel;

  const _SoundWave({required this.active, required this.soundLevel});

  @override
  State<_SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<_SoundWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          // Amplitude relativa baseada no nível de som (0.2 a 1.0)
          final amplitude = widget.active
              ? 0.2 + ((widget.soundLevel.clamp(-2.0, 10.0) + 2) / 12).clamp(0.0, 0.8)
              : 0.1;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(5, (i) {
              // Cada barra tem uma fase diferente para criar o efeito de onda
              final phase = (_ctrl.value + i * 0.2) % 1.0;
              final sineVal = (sin(phase * 2 * pi) + 1) / 2; // 0 a 1
              final height = 10.0 + sineVal * 40.0 * amplitude;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 6,
                height: height,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(
                    widget.active ? (0.5 + sineVal * 0.5) : 0.3,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          );
        },
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

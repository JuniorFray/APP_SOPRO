// HomeComposerBar — barra fixa estilo composer de chat (referência: Toki).
//
// Substitui os dois FABs flutuantes antigos (voz + "+") da aba Início E o campo
// de texto do topo da aba Lembretes, unificando tudo em um só componente. Vive
// no rodapé do MainShellScreen (acima da bottom nav), visível apenas nas abas
// Início e Lembretes.
//
// Layout (Row, altura fixa ~72dp):
//   [ + ]  [ campo de texto pill (Expanded) ]  [ 🎤 mic com ênfase 56dp ]
//
// - "+"  : abre o bottom sheet de criação (Novo Ambiente / Novo Lembrete).
// - campo: cria lembrete/ambiente por texto via o MESMO pipeline do assistente
//          (processTextAsPlan → ExecutionPlan → buildActionHandlers).
// - mic  : reaproveita o VoiceFab original (lógica de gravação intacta), só
//          reposicionado e compacto (56dp), com destaque visual coral.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../infrastructure/voice/action_handlers_builder.dart';
import '../../../infrastructure/voice/execution_plan.dart';
import '../../../infrastructure/voice/voice_action_executor.dart';
import '../../providers/database_provider.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_text_field.dart';
import '../environment/add_environment_screen.dart';
import 'home_tab_content.dart';

class HomeComposerBar extends ConsumerStatefulWidget {
  const HomeComposerBar({super.key});

  @override
  ConsumerState<HomeComposerBar> createState() => _HomeComposerBarState();
}

class _HomeComposerBarState extends ConsumerState<HomeComposerBar> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  // Aviso PROATIVO de "sem internet": banner discreto que aparece perto do
  // composer e some sozinho após alguns segundos (STT agora é só nuvem).
  bool _showOfflineHint = false;
  Timer? _offlineHintTimer;

  @override
  void initState() {
    super.initState();
    // Check de conectividade best-effort na montagem (app aberto em modo avião
    // cai aqui). O aviso REATIVO no FAB cobre a queda de rede durante o uso.
    _checkConnectivity();
  }

  @override
  void dispose() {
    _offlineHintTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // Probe de conectividade compartilhado: lookup rápido de DNS. true = offline.
  // Sem pacote extra (dart:io) — check simples, não precisa ser preciso.
  Future<bool> _isOffline() async {
    try {
      final res = await InternetAddress.lookup('api.groq.com')
          .timeout(const Duration(seconds: 2));
      return res.isEmpty || res.first.rawAddress.isEmpty;
    } catch (_) {
      return true; // SocketException / TimeoutException = offline
    }
  }

  // Check proativo na montagem (modo avião ao abrir o app cai aqui).
  Future<void> _checkConnectivity() async {
    if (await _isOffline()) _flashOfflineHint();
  }

  // Mostra o banner e o esconde após 5s (temporário, não fica na tela).
  void _flashOfflineHint() {
    if (!mounted) return;
    setState(() => _showOfflineHint = true);
    _offlineHintTimer?.cancel();
    _offlineHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showOfflineHint = false);
    });
  }

  // Estrutura o comando via Gemini (processTextAsPlan) e o executa
  // (buildActionHandlers). Checa o ExecutionSummary REAL antes do feedback:
  // só mostra sucesso quando nenhuma ação falhou; senão mostra erro amigável
  // (mapeado do reason do handler), nunca a "reply" otimista do Gemini.
  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      // Ambientes existentes (nome + ID) para o Gemini reutilizar vs criar.
      final envs = await ref.read(environmentRepositoryProvider).getAll();
      final planRes = await ref.read(voiceServiceProvider).processTextAsPlan(
            text,
            existingEnvironments: envs.map((e) => e.name).toList(),
            existingEnvironmentIds: envs.map((e) => e.id).toList(),
          );
      if (!mounted) return;

      // Texto entra no MESMO fluxo interativo de update de endereço que a voz: se
      // o comando pede trocar o endereço de um ambiente existente, delega ao handler
      // registrado pelo VoiceFab (geocoding + confirmação). Sem isso a ação cairia
      // no executor, onde a UpdateEnvironmentSkill ignora o address de propósito.
      final addrUpdate = findAddressUpdate(planRes.plan, envs);
      final addrHandler = ref.read(voiceAddressUpdateHandlerProvider);
      if (addrUpdate != null && addrHandler != null) {
        _ctrl.clear();
        await addrHandler(addrUpdate.env, addrUpdate.address);
        return; // finally reseta _sending; feedback vem pelo fluxo (TTS/popup)
      }

      ExecutionSummary? summary;
      if (planRes.plan.isNotEmpty) {
        summary = await VoiceActionExecutor(
                buildActionHandlers(ref, context, transcript: text))
            .run(planRes.plan);
      }
      if (!mounted) return;

      final String msg;
      if (summary != null && summary.failed > 0) {
        // Alguma ação falhou: mensagem de ERRO pelo reason da 1ª falha.
        final reason = summary.plan.actions
            .firstWhere((a) => a.status == ActionStatus.failed)
            .error;
        msg = AppStrings.composerError(reason);
      } else if (summary != null && summary.ok > 0) {
        // Tudo certo: usa a "reply" natural do Gemini (fallback "Feito!").
        final reply = planRes.reply.trim();
        msg = reply.isNotEmpty ? reply : AppStrings.remindersCommandSuccess;
      } else {
        // Plano vazio (0 ações). Se veio vazio por FALTA DE REDE (processTextAsPlan
        // devolve empty silenciosamente quando a 1ª chamada Gemini falha), mostra o
        // MESMO aviso reativo do caminho de voz; senão é follow-up/"não entendi".
        final reply = planRes.reply.trim();
        final offline = reply.isEmpty && await _isOffline();
        if (!mounted) return;
        if (offline) {
          _flashOfflineHint();
          msg = AppStrings.voiceNoInternet;
        } else {
          msg = reply.isNotEmpty ? reply : AppStrings.remindersCommandError;
        }
      }

      // Só limpa o campo quando algo foi de fato concluído — em falha, preserva
      // o texto para o usuário corrigir/tentar de novo.
      if (summary == null || summary.failed == 0) _ctrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Enquanto o mic grava (hold-to-talk no VoiceFab), troca o campo de texto
    // ocioso pela onda + segundos. Volta ao campo ao soltar/cancelar.
    final recording = ref.watch(recordingActiveProvider);
    // Coluna: banner proativo (quando offline) ACIMA da barra do composer.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _offlineHint(),
        // GlassSurface com borda superior sutil separa a barra do conteúdo acima.
        GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.top,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _plusButton(),
                  const SizedBox(width: AppSpacing.sm),
                  // Gravando → onda + segundos; ocioso → campo de texto normal.
                  Expanded(
                    child: recording
                        ? const _RecordingIndicator()
                        : _textField(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Mic com ênfase: reaproveita o VoiceFab (gravação intacta),
                  // compacto (56dp) e sem o contador que empurraria a altura fixa.
                  const VoiceFab(size: 56, showSeconds: false),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Banner âmbar discreto e temporário (aparece/some via AnimatedSize+Opacity).
  // Colapsa para altura zero quando escondido — não empurra o layout fixo.
  Widget _offlineHint() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: !_showOfflineHint
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              color: AppColors.warning.withOpacity(0.14),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded,
                      size: 16, color: AppColors.warning),
                  SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      AppStrings.voiceOfflineHint,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // "+" — círculo neutro 40dp que abre o menu de criação.
  Widget _plusButton() {
    return GestureDetector(
      onTap: () => _showCreateMenu(context),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.backgroundInput,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: const Icon(Icons.add, size: 24, color: AppColors.accent),
      ),
    );
  }

  // Campo pill compacto, sem label (hint sempre visível). Enter/envio dispara.
  Widget _textField() {
    return SoproTextField(
      controller: _ctrl,
      hint: AppStrings.homeComposerHint,
      enabled: !_sending,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _submit(),
      // Ícone de enviar só aparece quando há texto digitado (fade suave).
      suffixIcon: _sending
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
            )
          : ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, value, __) {
                final hasText = value.text.trim().isNotEmpty;
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: hasText ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !hasText,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: AppColors.accent),
                      onPressed: _submit,
                    ),
                  ),
                );
              },
            ),
    );
  }

  // Menu de criação: Novo Ambiente (ação direta) ou Novo Lembrete (em breve).
  void _showCreateMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.backgroundSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Alça visual do bottom sheet
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppStrings.createMenuTitle,
                  style: TextStyle(
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined,
                  color: AppColors.accent),
              title: const Text(
                AppStrings.newEnvironment,
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                pushScreen(context, const AddEnvironmentScreen());
              },
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

// Indicador de gravação exibido no LUGAR do campo de texto enquanto o mic grava:
// ponto REC + barras verticais pulsando em onda (animação local, NÃO ligada à
// amplitude real — decisão de escopo) + contador de segundos. Montado/desmontado
// pelo recordingActiveProvider; timers/controller vivem só durante a gravação.
class _RecordingIndicator extends StatefulWidget {
  const _RecordingIndicator();

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  static const _barCount = 5;
  late final AnimationController _ctrl;
  final _sw = Stopwatch();
  Timer? _secTimer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _sw.start();
    // Loop contínuo (900ms) que anima as barras da onda.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    // Atualiza o contador de segundos 1x/s a partir do Stopwatch real.
    _secTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds = _sw.elapsed.inSeconds);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _secTimer?.cancel();
    super.dispose();
  }

  // m:ss (ex.: 0:03) — mesmo formato do contador interno do VoiceFab.
  String get _label {
    final m = _seconds ~/ 60;
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Ponto vermelho "REC".
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Onda: cada barra é uma senoide defasada (padrão de onda em loop).
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_barCount, (i) {
                final phase = i / _barCount;
                final t = (_ctrl.value + phase) * 2 * math.pi;
                final h = 6 + (math.sin(t) + 1) / 2 * 16; // 6..22 dp
                return Container(
                  width: 3,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            );
          },
        ),
        const Spacer(),
        // Duração da gravação.
        Text(
          _label,
          style: const TextStyle(
            color: AppColors.danger,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

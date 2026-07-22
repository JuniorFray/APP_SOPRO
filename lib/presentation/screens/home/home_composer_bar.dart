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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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

      ExecutionSummary? summary;
      if (planRes.plan.isNotEmpty) {
        summary = await VoiceActionExecutor(buildActionHandlers(ref, context))
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
        // Plano vazio (0 ações): follow-up do Gemini ou "não entendi".
        final reply = planRes.reply.trim();
        msg = reply.isNotEmpty ? reply : AppStrings.remindersCommandError;
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
    // GlassSurface com borda superior sutil separa a barra do conteúdo acima.
    return GlassSurface(
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
              Expanded(child: _textField()),
              const SizedBox(width: AppSpacing.sm),
              // Mic com ênfase: reaproveita o VoiceFab (gravação intacta),
              // compacto (56dp) e sem o contador que empurraria a altura fixa.
              const VoiceFab(size: 56, showSeconds: false),
            ],
          ),
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
          : IconButton(
              icon: const Icon(Icons.send_rounded, color: AppColors.accent),
              onPressed: _submit,
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
            ListTile(
              leading: const Icon(Icons.notification_add_outlined,
                  color: AppColors.accent),
              title: const Text(
                AppStrings.newReminder,
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: navegar para tela de criação manual de lembrete quando existir
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(AppStrings.newReminderSoon),
                  behavior: SnackBarBehavior.floating,
                ));
              },
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

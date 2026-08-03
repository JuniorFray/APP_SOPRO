import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../infrastructure/feedback/feedback_service.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_card.dart';

// Tela de Comentários (card "Suporte" das Configurações).
// Campo de texto multi-linha + botão enviar. Sem anexos, e-mail ou redes sociais.
// Envia para a tabela `feedback` do Supabase via FeedbackService (reaproveita a
// infraestrutura HTTP do AppLogger — nenhum client novo).
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _controller = TextEditingController();
  bool _sending = false; // evita envio duplo enquanto o POST está em voo

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Envio permitido só com texto não vazio e sem outro envio em andamento.
  bool get _canSend => _controller.text.trim().isNotEmpty && !_sending;

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return; // guarda extra além do botão desabilitado
    setState(() => _sending = true);

    await FeedbackService.send(message);

    if (!mounted) return;
    // Envio é fire-and-forget: confirma de forma otimista, limpa e volta.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.feedbackSuccess),
        duration: Duration(seconds: 3),
      ),
    );
    _controller.clear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.feedbackTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Liquid Glass no topo — mesma receita das outras telas.
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho amistoso.
              Text(
                AppStrings.feedbackHeadline,
                style: AppTypography.titleLarge
                    .copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Campo multi-linha dentro de um cartão de vidro (ocupa o espaço livre).
              Expanded(
                child: SoproCard(
                  glass: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TextField(
                    controller: _controller,
                    // Reavalia o estado do botão a cada tecla.
                    onChanged: (_) => setState(() {}),
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    cursorColor: AppColors.accent,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: AppStrings.feedbackHint,
                      hintStyle: TextStyle(color: AppColors.textDisabled),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Botão enviar (seta). Desabilitado enquanto vazio ou enviando.
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canSend ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: AppColors.backgroundElevated,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : const Icon(LucideIcons.arrowRight,
                          color: AppColors.textPrimary, size: 18),
                  label: Text(
                    AppStrings.feedbackSend,
                    style: AppTypography.titleSmall
                        .copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

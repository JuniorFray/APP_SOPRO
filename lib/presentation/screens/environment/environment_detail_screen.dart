import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/environment_icon_mapper.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../domain/entities/trigger_entity.dart';
import '../../../infrastructure/logging/app_logger.dart';
import '../../providers/database_provider.dart';
import '../../providers/environment_providers.dart';
import '../../providers/trigger_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_card.dart';
import '../../widgets/sopro_primary_button.dart';
import '../../widgets/sopro_text_field.dart';
import 'add_environment_screen.dart';

// Tela de detalhe de um Environment.
// Exibe as informações do ambiente e a lista de Triggers associados.
// Permite adicionar, editar, ativar/desativar e excluir triggers inline.
// O ambiente é observado via stream (environmentByIdProvider) para refletir
// edições feitas na AddEnvironmentScreen sem necessidade de recarregar.
class EnvironmentDetailScreen extends ConsumerWidget {
  final EnvironmentEntity environment;

  const EnvironmentDetailScreen({super.key, required this.environment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final triggersAsync =
        ref.watch(triggersByEnvironmentProvider(environment.id));

    // Observa o ambiente em tempo real; se editado, reflete o novo nome e raio
    final envLive = ref.watch(environmentByIdProvider(environment.id));
    final currentEnv = envLive.valueOrNull ?? environment;

    // TEMP: remover após auditoria da resolução de localização
    AppLogger.log('map_open_coordinates', {
      'environment': currentEnv.name,
      'latitude':    currentEnv.latitude,
      'longitude':   currentEnv.longitude,
    });

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: Text(currentEnv.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Liquid Glass — delega ao primitivo central GlassSurface.
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
        actions: [
          // Botão para editar o ambiente (nome, raio, localização)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: AppStrings.editTooltip,
            onPressed: () => pushScreen(
              context,
              AddEnvironmentScreen(environment: currentEnv),
            ),
          ),
          // Botão para adicionar novo trigger
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: AppStrings.addTrigger,
            onPressed: () => _showTriggerSheet(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card com informações geográficas do ambiente
          _EnvironmentInfoCard(environment: currentEnv),

          // Cabeçalho da seção de triggers com contagem dinâmica
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xxs),
            child: triggersAsync.maybeWhen(
              data: (triggers) => Text(
                '${AppStrings.triggersSection} (${triggers.length})',
                style: AppTypography.labelLarge.copyWith(color: AppTheme.textPrimary),
              ),
              orElse: () => const Text(
                AppStrings.triggersSection,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          // Lista de triggers ou estado vazio
          Expanded(
            child: triggersAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
              error: (_, __) => const Center(
                child: Text(
                  AppStrings.errorGeneric,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              data: (triggers) => triggers.isEmpty
                  ? const _EmptyTriggersState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      itemCount: triggers.length,
                      itemBuilder: (_, i) => _TriggerTile(
                        trigger: triggers[i],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Abre o bottom sheet para criação de um novo trigger (sem trigger existente)
  // ou para edição de um trigger já existente (passando [existingTrigger]).
  void _showTriggerSheet(BuildContext context, {TriggerEntity? existingTrigger}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.button)),
      ),
      builder: (_) => _TriggerSheet(
        environmentId: environment.id,
        existingTrigger: existingTrigger,
      ),
    );
  }
}

// Card compacto com lat/lng e raio do ambiente
class _EnvironmentInfoCard extends StatelessWidget {
  final EnvironmentEntity environment;

  const _EnvironmentInfoCard({required this.environment});

  @override
  Widget build(BuildContext context) {
    final visual = EnvironmentIconMapper.getVisual(environment.name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SoproCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            // Emoji ilustrativo do ambiente com cor do mapper
            Text(visual.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: AppSpacing.gap10),
            Expanded(
              child: Text(
                '${environment.latitude.toStringAsFixed(5)}, '
                '${environment.longitude.toStringAsFixed(5)}',
                style: AppTypography.monospace.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Badge de raio do geofence
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: AppTheme.backgroundElevated,
                borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
                border: Border.all(color: AppTheme.borderColor, width: 0.5),
              ),
              child: Text(
                '${environment.radiusMeters.toStringAsFixed(0)} m',
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Tile de um trigger com switch de ativo/inativo, botão de edição e swipe para excluir.
// Toque no botão de lápis abre o sheet de edição do trigger.
// Feedback háptico ao ativar/desativar o trigger.
class _TriggerTile extends ConsumerWidget {
  final TriggerEntity trigger;

  const _TriggerTile({required this.trigger});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(trigger.id),
      direction: DismissDirection.endToStart,
      // Confirmação antes de excluir para evitar exclusão acidental
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) =>
          ref.read(triggerRepositoryProvider).delete(trigger.id),
      background: _DeleteBackground(),
      child: Card(
        color: AppTheme.backgroundSurface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusIcon),
          side: const BorderSide(color: AppTheme.borderColor, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.gap10, AppSpacing.xxs, AppSpacing.gap10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Conteúdo textual do trigger
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trigger.title,
                      style: AppTypography.titleSmall.copyWith(
                        color: trigger.isActive ? AppTheme.textPrimary : AppTheme.textDisabled,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trigger.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: trigger.isActive ? AppTheme.textSecondary : AppTheme.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),

              // Botão de edição: abre o sheet pré-preenchido com os dados do trigger
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: AppTheme.textDisabled,
                tooltip: AppStrings.editTooltip,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => _showEditSheet(context),
              ),

              // Switch de ativo/inativo com feedback háptico
              Switch(
                value: trigger.isActive,
                onChanged: (active) {
                  // Vibração sutil ao resolver ou suspender um trigger
                  HapticFeedback.mediumImpact();
                  ref
                      .read(triggerRepositoryProvider)
                      .setActive(trigger.id, active: active);
                },
                activeColor: AppTheme.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Abre o sheet de edição do trigger pré-preenchido com os dados atuais
  void _showEditSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.button)),
      ),
      builder: (_) => _TriggerSheet(
        environmentId: trigger.environmentId,
        existingTrigger: trigger,
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundElevated,
        title: const Text(
          AppStrings.delete,
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          AppStrings.triggerDeleteConfirm,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              AppStrings.delete,
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}

// Background vermelho ao arrastar trigger para excluir
class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.lg),
      child: const Icon(Icons.delete_outline, color: AppColors.textPrimary, size: 26),
    );
  }
}

// Estado vazio exibido quando o ambiente não tem triggers
class _EmptyTriggersState extends StatelessWidget {
  const _EmptyTriggersState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_outlined, size: 60, color: AppTheme.accent),
          SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.noTriggersYet,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSpacing.gap6),
          Text(
            AppStrings.noTriggersHint,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// Bottom sheet para criação OU edição de um trigger.
//
// Modo criação: [existingTrigger] == null — campos em branco, título "Novo Gatilho".
// Modo edição:  [existingTrigger] != null — campos pré-preenchidos, título "Editar Gatilho",
//   submit faz upsert com o mesmo ID (atualização do trigger existente).
class _TriggerSheet extends ConsumerStatefulWidget {
  final String environmentId;
  // null = criação de novo trigger; não-null = edição de trigger existente
  final TriggerEntity? existingTrigger;

  const _TriggerSheet({
    required this.environmentId,
    this.existingTrigger,
  });

  @override
  ConsumerState<_TriggerSheet> createState() => _TriggerSheetState();
}

class _TriggerSheetState extends ConsumerState<_TriggerSheet> {
  final _formKey     = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  bool _isSaving        = false;
  // Flags de gravação ativa por campo para animação de loading no ícone
  bool _recordingTitle   = false;
  bool _recordingContent = false;
  // Timer de auto-stop da gravação por campo (8 s máximo)
  Timer? _fieldRecordTimer;

  bool get _isEditing => widget.existingTrigger != null;

  @override
  void initState() {
    super.initState();
    // Pré-preenche com os dados do trigger existente ao editar; vazio ao criar
    _titleCtrl   = TextEditingController(text: widget.existingTrigger?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.existingTrigger?.content ?? '');
  }

  @override
  void dispose() {
    _fieldRecordTimer?.cancel();
    ref.read(voiceServiceProvider).cancelRecording();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Garante que o sheet sobe quando o teclado aparece
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alça visual do bottom sheet
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppTheme.textDisabled,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),

            // Título diferente conforme o modo de uso
            Text(
              _isEditing ? AppStrings.editTriggerTitle : AppStrings.addTrigger,
              style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),

            // Campo título — opcional; botão de microfone preenche por voz
            SoproTextField(
              controller: _titleCtrl,
              label: AppStrings.triggerTitleLabel,
              hint: _recordingTitle
                  ? AppStrings.voiceFillHint
                  : AppStrings.triggerTitleHint,
              textCapitalization: TextCapitalization.sentences,
              suffixIcon: _recordingTitle
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.mic_outlined,
                          color: AppTheme.accent, size: 20),
                      tooltip: AppStrings.voiceMicTooltip,
                      onPressed: () => _recordForField(
                        _titleCtrl,
                        (v) => setState(() => _recordingTitle = v),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Campo conteúdo (multi-linha) com botão de microfone para ditar
            SoproTextField(
              controller: _contentCtrl,
              label: AppStrings.triggerContentLabel,
              hint: _recordingContent
                  ? AppStrings.voiceFillHint
                  : AppStrings.triggerContentHint,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? AppStrings.triggerContentRequired
                      : null,
              suffixIcon: _recordingContent
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.mic_outlined,
                          color: AppTheme.accent, size: 20),
                      tooltip: AppStrings.voiceMicTooltip,
                      onPressed: () => _recordForField(
                        _contentCtrl,
                        (v) => setState(() => _recordingContent = v),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Botão salvar
            SoproPrimaryButton(
              label: AppStrings.save,
              onPressed: _isSaving ? null : _submit,
              loading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }

  // Grava 8 s de áudio e usa Gemini para transcrever o campo [ctrl].
  // [setRecording] atualiza o flag do campo para animar o ícone.
  // Toque no mic inicia; toque novamente cancela antes dos 8 s.
  Future<void> _recordForField(
    TextEditingController ctrl,
    void Function(bool) setRecording,
  ) async {
    // Segundo toque: cancela gravação em andamento
    final isAlreadyRecording =
        (_recordingTitle || _recordingContent) && !ctrl.text.endsWith('...');
    if (isAlreadyRecording) {
      _fieldRecordTimer?.cancel();
      ref.read(voiceServiceProvider).cancelRecording();
      setRecording(false);
      return;
    }

    final service = ref.read(voiceServiceProvider);
    final ok = await service.startRecording();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.voiceNotAvailable)),
      );
      return;
    }
    setRecording(true);

    // Para automaticamente após 8 s e transcreve via Gemini
    _fieldRecordTimer = Timer(const Duration(seconds: 8), () async {
      final path = await service.stopRecording();
      if (!mounted) return;
      setRecording(false);
      if (path == null) return;
      // HOTFIX 1 — sem fala detectada, não chama o Gemini (evita transcrição vazia)
      if (!service.speechDetected) return;
      final transcript = await service.transcribeAudio(path);
      if (!mounted || transcript == null || transcript.isEmpty) return;
      setState(() {
        ctrl.text = transcript[0].toUpperCase() + transcript.substring(1);
      });
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final entity = TriggerEntity(
      // Ao editar: mantém o ID original para fazer upsert (atualização)
      // Ao criar: string vazia → repositório gera UUID novo
      id: widget.existingTrigger?.id ?? '',
      environmentId: widget.environmentId,
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      // Ao editar: preserva o estado ativo original
      isActive: widget.existingTrigger?.isActive ?? true,
      // Ao editar: preserva a data de criação original
      createdAt: widget.existingTrigger?.createdAt ?? DateTime.now(),
    );

    await ref.read(triggerRepositoryProvider).save(entity);

    if (mounted) Navigator.pop(context);
  }

}

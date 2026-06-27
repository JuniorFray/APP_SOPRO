import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../domain/entities/trigger_entity.dart';
import '../../providers/database_provider.dart';
import '../../providers/trigger_providers.dart';

// Tela de detalhe de um Environment.
// Exibe as informações do ambiente e a lista de Triggers associados.
// Permite adicionar, ativar/desativar e excluir triggers inline.
class EnvironmentDetailScreen extends ConsumerWidget {
  final EnvironmentEntity environment;

  const EnvironmentDetailScreen({super.key, required this.environment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final triggersAsync =
        ref.watch(triggersByEnvironmentProvider(environment.id));

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: Text(environment.name),
        actions: [
          // Botão para adicionar novo trigger
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: AppStrings.addTrigger,
            onPressed: () => _showAddSheet(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card com informações geográficas do ambiente
          _EnvironmentInfoCard(environment: environment),

          // Cabeçalho da seção de triggers com contagem dinâmica
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: triggersAsync.maybeWhen(
              data: (triggers) => Text(
                '${AppStrings.triggersSection} (${triggers.length})',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
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
                      padding: const EdgeInsets.symmetric(vertical: 4),
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

  // Abre o bottom sheet para criação de um novo trigger
  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTriggerSheet(environmentId: environment.id),
    );
  }
}

// Card compacto com lat/lng e raio do ambiente
class _EnvironmentInfoCard extends StatelessWidget {
  final EnvironmentEntity environment;

  const _EnvironmentInfoCard({required this.environment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, color: AppTheme.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${environment.latitude.toStringAsFixed(5)}, '
                '${environment.longitude.toStringAsFixed(5)}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Raio do geofence
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.backgroundElevated,
                borderRadius: BorderRadius.circular(8),
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

// Tile de um trigger com switch de ativo/inativo e swipe para excluir
class _TriggerTile extends ConsumerWidget {
  final TriggerEntity trigger;

  const _TriggerTile({required this.trigger});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(trigger.id),
      direction: DismissDirection.endToStart,
      // Confirmação antes de excluir
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) =>
          ref.read(triggerRepositoryProvider).delete(trigger.id),
      background: _DeleteBackground(),
      child: Card(
        color: AppTheme.backgroundSurface,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Conteúdo textual do trigger
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trigger.title,
                      style: TextStyle(
                        color: trigger.isActive
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trigger.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: trigger.isActive
                            ? AppTheme.textSecondary
                            : AppTheme.textDisabled,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Switch de ativo/inativo
              Switch(
                value: trigger.isActive,
                onChanged: (active) => ref
                    .read(triggerRepositoryProvider)
                    .setActive(trigger.id, active: active),
                activeColor: AppTheme.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
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
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
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
          SizedBox(height: 16),
          Text(
            AppStrings.noTriggersYet,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            AppStrings.noTriggersHint,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// Bottom sheet para criação de um novo trigger
class _AddTriggerSheet extends ConsumerStatefulWidget {
  final String environmentId;

  const _AddTriggerSheet({required this.environmentId});

  @override
  ConsumerState<_AddTriggerSheet> createState() => _AddTriggerSheetState();
}

class _AddTriggerSheetState extends ConsumerState<_AddTriggerSheet> {
  final _formKey        = GlobalKey<FormState>();
  final _titleCtrl      = TextEditingController();
  final _contentCtrl    = TextEditingController();
  bool  _isSaving       = false;

  @override
  void dispose() {
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
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const Text(
              AppStrings.addTrigger,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Campo título
            TextFormField(
              controller: _titleCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? AppStrings.triggerTitleRequired
                      : null,
              decoration: _fieldDecoration(
                label: AppStrings.triggerTitleLabel,
                hint: AppStrings.triggerTitleHint,
              ),
            ),
            const SizedBox(height: 12),

            // Campo conteúdo (multi-linha)
            TextFormField(
              controller: _contentCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? AppStrings.triggerContentRequired
                      : null,
              decoration: _fieldDecoration(
                label: AppStrings.triggerContentLabel,
                hint: AppStrings.triggerContentHint,
              ),
            ),
            const SizedBox(height: 20),

            // Botão salvar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        AppStrings.save,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final entity = TriggerEntity(
      id: '',    // repositório gera o UUID
      environmentId: widget.environmentId,
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      isActive: true,
      createdAt: DateTime.now(),
    );

    await ref.read(triggerRepositoryProvider).save(entity);

    if (mounted) Navigator.pop(context);
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppTheme.textSecondary),
      hintStyle: const TextStyle(color: AppTheme.textDisabled, fontSize: 12),
      filled: true,
      fillColor: AppTheme.backgroundSurface,
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppTheme.backgroundPrimary),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppTheme.accent),
      ),
      errorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red),
      ),
    );
  }
}

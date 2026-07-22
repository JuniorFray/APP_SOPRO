// RemindersTabContent — conteúdo da aba "Lembretes" do bottom nav.
//
// Lista os lembretes ativos (allActiveRemindersProvider) em cards de vidro. Cada
// item pode ser removido por swipe (com confirmação). A criação por texto/voz
// vem da HomeComposerBar compartilhada (fixa no rodapé do shell), não daqui.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/scheduled_reminder_entity.dart';
import '../../providers/database_provider.dart';
import '../../providers/scheduled_reminder_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_card.dart';

class RemindersTabContent extends ConsumerWidget {
  const RemindersTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(allActiveRemindersProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
        title: const Text(
          AppStrings.remindersTitle,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.8,
          ),
        ),
      ),
      // Lista simples: a criação por texto/voz agora vem 100% da HomeComposerBar
      // compartilhada (fixa no rodapé do shell), não há mais campo aqui.
      body: remindersAsync.when(
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
        data: (reminders) => reminders.isEmpty
            ? const _RemindersEmpty()
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 24),
                itemCount: reminders.length,
                itemBuilder: (_, i) => _ReminderTile(reminder: reminders[i]),
              ),
      ),
    );
  }
}

// Card de um lembrete: título + data/hora + conteúdo. Swipe endToStart remove
// (com confirmação) via scheduledReminderRepository.delete → cancela o alarme.
class _ReminderTile extends ConsumerWidget {
  final ScheduledReminderEntity reminder;
  const _ReminderTile({required this.reminder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(reminder.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        ref.read(scheduledReminderRepositoryProvider).delete(reminder.id);
      },
      background: const _DeleteBackground(),
      child: SoproCard(
        glass: true,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reminder.title,
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _formatDateTime(reminder.scheduledAt),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (reminder.content.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                reminder.content,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // Dois toggles independentes: sino (notification) + alarme (alarm).
            // Combinação dos dois = both. Não pode desligar os dois.
            _alertToggles(context, ref),
          ],
        ),
      ),
    );
  }

  // Sino e alarme como toggles independentes. Deriva os dois estados do
  // alertMode atual e recalcula o modo ao tocar.
  Widget _alertToggles(BuildContext context, WidgetRef ref) {
    final notifOn = reminder.alertMode == ReminderAlertMode.notification ||
        reminder.alertMode == ReminderAlertMode.both;
    final alarmOn = reminder.alertMode == ReminderAlertMode.alarm ||
        reminder.alertMode == ReminderAlertMode.both;
    return Row(
      children: [
        _toggleChip(Icons.notifications_outlined, notifOn,
            () => _apply(context, ref, notif: !notifOn, alarm: alarmOn)),
        const SizedBox(width: 8),
        _toggleChip(Icons.alarm, alarmOn,
            () => _apply(context, ref, notif: notifOn, alarm: !alarmOn)),
      ],
    );
  }

  // Calcula o novo alertMode a partir dos dois flags. Bloqueia (SnackBar) se o
  // usuário tentar deixar ambos desligados.
  void _apply(BuildContext context, WidgetRef ref,
      {required bool notif, required bool alarm}) {
    if (!notif && !alarm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(AppStrings.reminderAlertMinOne),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final mode = (notif && alarm)
        ? ReminderAlertMode.both
        : (alarm ? ReminderAlertMode.alarm : ReminderAlertMode.notification);
    ref.read(scheduledReminderRepositoryProvider).updateAlertMode(reminder.id, mode);
  }

  // Ícone toggle: accent quando ativo, borda/ícone neutro quando inativo.
  Widget _toggleChip(IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.textDisabled,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? AppColors.accent : AppColors.textSecondary,
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundElevated,
        title: const Text(
          AppStrings.delete,
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          AppStrings.reminderDeleteConfirm,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              AppStrings.delete,
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  // Formata "dd/MM · HH:mm" sem depender de intl.
  String _formatDateTime(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}/${p(dt.month)} · ${p(dt.hour)}:${p(dt.minute)}';
  }
}

// Background de exclusão (swipe endToStart) — ícone de lixeira sobre fundo danger.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }
}

// Estado vazio da aba de lembretes.
class _RemindersEmpty extends StatelessWidget {
  const _RemindersEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none,
                size: 48, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.remindersEmpty,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

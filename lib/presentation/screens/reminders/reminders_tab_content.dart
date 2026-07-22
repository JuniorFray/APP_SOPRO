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
import '../../widgets/sopro_primary_button.dart';
import '../../widgets/sopro_text_field.dart';

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
// Toque no card (fora dos toggles/swipe) abre o sheet de edição.
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
        // GestureDetector opaco: tap na área do card abre edição; os InkWells
        // internos (toggles de alerta) vencem o gesto na sua própria área.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openEdit(context),
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
      ),
    );
  }

  // Abre o bottom sheet de edição do lembrete.
  void _openEdit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => _EditReminderSheet(reminder: reminder),
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

// Bottom sheet de EDIÇÃO de um lembrete. Reaproveita o padrão visual do
// _TriggerSheet (SoproTextField + SoproPrimaryButton) e adiciona seletores
// nativos de data/hora + repetição. Ao salvar, upsert() com o MESMO id
// atualiza o registro e reagenda o alarme nativo (requestCode determinístico
// + FLAG_UPDATE_CURRENT sobrescrevem o PendingIntent antigo, sem duplicar).
class _EditReminderSheet extends ConsumerStatefulWidget {
  final ScheduledReminderEntity reminder;
  const _EditReminderSheet({required this.reminder});

  @override
  ConsumerState<_EditReminderSheet> createState() => _EditReminderSheetState();
}

class _EditReminderSheetState extends ConsumerState<_EditReminderSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late DateTime _scheduledAt;
  late ReminderRepeatRule _rule;
  late Set<int> _days; // ISO 1=Seg..7=Dom, só usado em weekly
  bool _saving = false;

  // Rótulos ISO dos dias da semana (1=segunda ... 7=domingo).
  static const _weekdayLabels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    _titleCtrl = TextEditingController(text: r.title);
    _contentCtrl = TextEditingController(text: r.content);
    _scheduledAt = r.scheduledAt;
    _rule = r.repeatRule;
    _days = {...r.repeatDaysOfWeek};
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _scheduledAt = DateTime(picked.year, picked.month,
          picked.day, _scheduledAt.hour, _scheduledAt.minute));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (picked != null) {
      setState(() => _scheduledAt = DateTime(_scheduledAt.year,
          _scheduledAt.month, _scheduledAt.day, picked.hour, picked.minute));
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(AppStrings.composerErrorEmptyTitle),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    final r = widget.reminder;
    // weekly sem dia marcado degrada para "none" (evita um weekly órfão).
    final days = _rule == ReminderRepeatRule.weekly
        ? (_days.toList()..sort())
        : <int>[];
    final rule = (_rule == ReminderRepeatRule.weekly && days.isEmpty)
        ? ReminderRepeatRule.none
        : _rule;
    await ref.read(scheduledReminderRepositoryProvider).upsert(
          ScheduledReminderEntity(
            id: r.id, // mesmo id => update + reagenda
            title: title,
            content: _contentCtrl.text.trim(),
            scheduledAt: _scheduledAt,
            repeatRule: rule,
            repeatDaysOfWeek: days,
            isActive: r.isActive,
            alertMode: r.alertMode,
            createdAt: r.createdAt,
          ),
        );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(AppStrings.reminderUpdated),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alça visual do sheet
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),
            Text(
              AppStrings.reminderEditTitle,
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            SoproTextField(
              controller: _titleCtrl,
              label: AppStrings.reminderTitleLabel,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.sm),
            SoproTextField(
              controller: _contentCtrl,
              label: AppStrings.reminderContentLabel,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _pickerTile(
                    icon: Icons.calendar_today_outlined,
                    label: AppStrings.reminderDateLabel,
                    value: _formatDate(_scheduledAt),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _pickerTile(
                    icon: Icons.schedule_outlined,
                    label: AppStrings.reminderTimeLabel,
                    value: _formatTime(_scheduledAt),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.reminderRepeatLabel,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            _repeatSelector(),
            if (_rule == ReminderRepeatRule.weekly) ...[
              const SizedBox(height: AppSpacing.sm),
              _weekdayChips(),
            ],
            const SizedBox(height: AppSpacing.lg),
            SoproPrimaryButton(
              label: AppStrings.save,
              onPressed: _saving ? null : _save,
              loading: _saving,
            ),
          ],
        ),
      ),
    );
  }

  // Botão de data/hora: rótulo pequeno + valor, abre o picker nativo ao tocar.
  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.input),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundInput,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Três opções de repetição (pílulas). Só uma ativa por vez.
  Widget _repeatSelector() {
    Widget pill(ReminderRepeatRule rule, String text) {
      final active = _rule == rule;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => setState(() => _rule = rule),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: active ? AppColors.accent : AppColors.textDisabled,
                width: 1,
              ),
            ),
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: active ? AppColors.accent : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(ReminderRepeatRule.none, AppStrings.reminderRepeatNone),
        const SizedBox(width: 6),
        pill(ReminderRepeatRule.daily, AppStrings.reminderRepeatDaily),
        const SizedBox(width: 6),
        pill(ReminderRepeatRule.weekly, AppStrings.reminderRepeatWeekly),
      ],
    );
  }

  // Seleção múltipla dos dias da semana (weekly). ISO 1..7.
  Widget _weekdayChips() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final iso = i + 1;
        final active = _days.contains(iso);
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() {
            active ? _days.remove(iso) : _days.add(iso);
          }),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withOpacity(0.15)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? AppColors.accent : AppColors.textDisabled,
                width: 1,
              ),
            ),
            child: Text(
              _weekdayLabels[i],
              style: AppTypography.caption.copyWith(
                color: active ? AppColors.accent : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }),
    );
  }

  String _formatDate(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}/${p(dt.month)}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.hour)}:${p(dt.minute)}';
  }
}

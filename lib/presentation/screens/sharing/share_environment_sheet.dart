import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../infrastructure/sharing/shares_service.dart';
import '../../providers/auth_providers.dart';
import '../../providers/sharing_providers.dart';
import '../../widgets/sopro_primary_button.dart';
import '../../widgets/sopro_text_field.dart';
import '../auth/account_screen.dart';

// Abre o bottom-sheet de compartilhar um ambiente. Sem conta → mostra CTA de
// criar conta em vez de erro (decisão de produto). Com conta → convidar por
// e-mail + toggle de gatilhos + lista de quem tem acesso (revogar).
Future<void> showShareEnvironmentSheet(
  BuildContext context,
  EnvironmentEntity environment,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.backgroundElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.button)),
    ),
    builder: (_) => _ShareEnvironmentSheet(environment: environment),
  );
}

class _ShareEnvironmentSheet extends ConsumerStatefulWidget {
  final EnvironmentEntity environment;
  const _ShareEnvironmentSheet({required this.environment});

  @override
  ConsumerState<_ShareEnvironmentSheet> createState() =>
      _ShareEnvironmentSheetState();
}

class _ShareEnvironmentSheetState
    extends ConsumerState<_ShareEnvironmentSheet> {
  final _emailCtrl = TextEditingController();
  bool _includeTriggers = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final session = ref.watch(authSessionProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _handle(),
          // Sem conta: mostra CTA de criar conta em vez de bloquear com erro.
          if (session == null)
            _needsAccount(context)
          else
            ..._shareForm(context, session.email),
        ],
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppTheme.textDisabled,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
      );

  // ── Sem conta: CTA de criar conta ──────────────────────────────────────────
  Widget _needsAccount(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.sharingNeedsAccountTitle,
            style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text(AppStrings.sharingNeedsAccountBody,
            style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary)),
        const SizedBox(height: AppSpacing.lg),
        SoproPrimaryButton(
          label: AppStrings.sharingCreateAccountCta,
          onPressed: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            );
          },
        ),
      ],
    );
  }

  // ── Com conta: formulário de convite + lista de acesso ─────────────────────
  List<Widget> _shareForm(BuildContext context, String myEmail) {
    final sharesAsync =
        ref.watch(sharesByEnvironmentProvider(widget.environment.id));

    return [
      Text(AppStrings.sharingSheetTitle,
          style: AppTypography.titleMedium.copyWith(color: AppTheme.textPrimary)),
      const SizedBox(height: AppSpacing.md),

      SoproTextField(
        controller: _emailCtrl,
        label: AppStrings.sharingEmailLabel,
        hint: AppStrings.sharingEmailHint,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: AppSpacing.xs),

      // Toggle "compartilhar gatilhos também".
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _includeTriggers,
        onChanged: _busy ? null : (v) => setState(() => _includeTriggers = v),
        activeColor: AppTheme.accent,
        title: Text(AppStrings.sharingIncludeTriggers,
            style: AppTypography.bodyMedium.copyWith(color: AppTheme.textPrimary)),
        subtitle: Text(AppStrings.sharingIncludeTriggersDesc,
            style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary)),
      ),
      const SizedBox(height: AppSpacing.sm),

      SoproPrimaryButton(
        label: AppStrings.sharingInviteCta,
        onPressed: _busy ? null : () => _invite(context, myEmail),
        loading: _busy,
      ),
      const SizedBox(height: AppSpacing.lg),

      Text(AppStrings.sharingWhoHasAccess,
          style: AppTypography.labelLarge.copyWith(color: AppTheme.textPrimary)),
      const SizedBox(height: AppSpacing.xs),

      // Lista de quem já tem acesso (best-effort; offline mostra vazio).
      sharesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(
              child: CircularProgressIndicator(color: AppTheme.accent)),
        ),
        error: (_, __) => Text(AppStrings.sharingNoOneYet,
            style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary)),
        data: (shares) => shares.isEmpty
            ? Text(AppStrings.sharingNoOneYet,
                style: AppTypography.bodySmall
                    .copyWith(color: AppTheme.textSecondary))
            : Column(
                children: [
                  for (final s in shares) _accessRow(context, s),
                ],
              ),
      ),
    ];
  }

  Widget _accessRow(BuildContext context, EnvironmentShare s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          const Icon(LucideIcons.userCheck,
              size: 18, color: AppColors.iconTileTint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(s.sharedWithEmail,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppTheme.textPrimary)),
          ),
          TextButton(
            onPressed: _busy ? null : () => _revoke(context, s),
            child: Text(AppStrings.sharingRevoke,
                style: AppTypography.bodySmall.copyWith(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  // ── Ações ──────────────────────────────────────────────────────────────────

  Future<void> _invite(BuildContext context, String myEmail) async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack(AppStrings.authEmailInvalid);
      return;
    }
    if (email.toLowerCase() == myEmail.toLowerCase()) {
      _snack(AppStrings.sharingSelfInvite);
      return;
    }
    setState(() => _busy = true);
    try {
      // Só permite convidar conta EXISTENTE (RPC resolve_user_by_email).
      final profile = await ref.read(authServiceProvider).resolveUserByEmail(email);
      if (!context.mounted) return;
      if (profile == null) {
        _snack(AppStrings.sharingNoAccountForEmail);
        return;
      }
      // Aviso de transparência ANTES de efetivar.
      final ok = await _confirmDialog(
        context,
        title: AppStrings.sharingConfirmTitle,
        body: AppStrings.sharingTransparencyBody(profile.email),
        confirmLabel: AppStrings.sharingConfirmCta,
      );
      if (ok != true || !mounted) return;

      final created = await ref.read(sharesServiceProvider).create(
            environmentId: widget.environment.id,
            sharedWithId: profile.id,
            sharedWithEmail: profile.email,
            includeTriggers: _includeTriggers,
          );
      if (!mounted) return;
      if (created) {
        _emailCtrl.clear();
        ref.invalidate(sharesByEnvironmentProvider(widget.environment.id));
        ref.invalidate(outgoingSharesProvider);
        _snack(AppStrings.sharingInviteSentSnack);
      } else {
        _snack(AppStrings.sharingInviteFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(BuildContext context, EnvironmentShare s) async {
    final ok = await _confirmDialog(
      context,
      title: AppStrings.sharingRevokeTitle,
      body: AppStrings.sharingRevokeBody(s.sharedWithEmail),
      confirmLabel: AppStrings.sharingRevoke,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final done = await ref.read(sharesServiceProvider).revoke(s.id);
      if (!mounted) return;
      if (done) {
        ref.invalidate(sharesByEnvironmentProvider(widget.environment.id));
        ref.invalidate(outgoingSharesProvider);
      } else {
        _snack(AppStrings.sharingInviteFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDialog(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundElevated,
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(body, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel,
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: const TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

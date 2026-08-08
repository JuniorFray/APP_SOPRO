import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../infrastructure/sharing/shares_service.dart';
import '../../providers/environment_providers.dart';
import '../../providers/sharing_providers.dart';
import '../../widgets/glass_surface.dart';

// Tela "Compartilhamentos" — duas seções:
//  • Compartilhei: ambientes que EU compartilhei (revogar).
//  • Compartilharam comigo: ambientes recebidos (sair sozinho — decisão #5).
class SharesListScreen extends ConsumerWidget {
  const SharesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(outgoingSharesProvider);
    final incoming = ref.watch(incomingSharesProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.sharesListTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async {
          ref.invalidate(outgoingSharesProvider);
          ref.invalidate(incomingSharesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: [
            _header(AppStrings.sharesSectionMine),
            _sharesSection(
              context,
              ref,
              async: mine,
              empty: AppStrings.sharesEmptyMine,
              isIncoming: false,
            ),
            _header(AppStrings.sharesSectionIncoming),
            _sharesSection(
              context,
              ref,
              async: incoming,
              empty: AppStrings.sharesEmptyIncoming,
              isIncoming: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textDisabled,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _sharesSection(
    BuildContext context,
    WidgetRef ref, {
    required AsyncValue<List<EnvironmentShare>> async,
    required String empty,
    required bool isIncoming,
  }) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      ),
      error: (_, __) => _emptyText(empty),
      data: (shares) => shares.isEmpty
          ? _emptyText(empty)
          : Column(
              children: [
                for (final s in shares)
                  _ShareRow(share: s, isIncoming: isIncoming),
              ],
            ),
    );
  }

  Widget _emptyText(String text) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Text(text,
            style: AppTypography.bodySmall
                .copyWith(color: AppTheme.textSecondary)),
      );
}

// Linha de um compartilhamento. Observa o ambiente local para exibir o nome.
class _ShareRow extends ConsumerWidget {
  final EnvironmentShare share;
  final bool isIncoming;

  const _ShareRow({required this.share, required this.isIncoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envAsync = ref.watch(environmentByIdProvider(share.environmentId));
    final envName = envAsync.valueOrNull?.name ?? AppStrings.sharesSharedFallback;
    // Compartilhei → mostra com quem; recebido → "compartilhado com você".
    final subtitle =
        isIncoming ? AppStrings.sharesSharedWithYou : share.sharedWithEmail;

    return ListTile(
      leading: Icon(
        isIncoming ? LucideIcons.download : LucideIcons.share2,
        size: 20,
        color: AppColors.iconTileTint,
      ),
      title: Text(envName,
          style: AppTypography.titleSmall.copyWith(color: AppTheme.textPrimary)),
      subtitle: Text(subtitle,
          style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary)),
      trailing: TextButton(
        onPressed: () => _confirm(context, ref),
        child: Text(
          isIncoming ? AppStrings.sharesLeave : AppStrings.sharingRevoke,
          style: AppTypography.bodySmall.copyWith(color: AppTheme.accent),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundElevated,
        title: Text(
          isIncoming ? AppStrings.sharesLeaveTitle : AppStrings.sharingRevokeTitle,
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          isIncoming
              ? AppStrings.sharesLeaveBody
              : AppStrings.sharingRevokeBody(share.sharedWithEmail),
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel,
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isIncoming ? AppStrings.sharesLeave : AppStrings.sharingRevoke,
              style: const TextStyle(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final service = ref.read(sharesServiceProvider);
    // Convidado sai (leave) OU dono revoga — ambos viram status='revoked'.
    final done =
        isIncoming ? await service.leave(share.id) : await service.revoke(share.id);
    if (done) {
      ref.invalidate(outgoingSharesProvider);
      ref.invalidate(incomingSharesProvider);
    }
  }
}

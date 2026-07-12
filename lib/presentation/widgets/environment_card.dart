import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/strings.dart';
import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/environment_icon_mapper.dart';
import '../../domain/entities/environment_entity.dart';
import '../providers/database_provider.dart';
import '../providers/trigger_providers.dart';
import '../screens/environment/environment_detail_screen.dart';
import 'sopro_card.dart';

/// Card de ambiente na lista da Home — V2 Premium.
/// Layout Row customizado (substituindo ListTile) para controle total
/// de hierarquia, espaçamento e badge de triggers.
class EnvironmentCard extends ConsumerWidget {
  final EnvironmentEntity environment;

  const EnvironmentCard({super.key, required this.environment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final triggersAsync =
        ref.watch(triggersByEnvironmentProvider(environment.id));
    final visual = EnvironmentIconMapper.getVisual(environment.name);

    return Dismissible(
      key: ValueKey(environment.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        ref.read(environmentRepositoryProvider).delete(environment.id);
      },
      background: _DeleteBackground(),
      child: SoproCard(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.gap6,
        ),
        child: InkWell(
          onTap: () => pushScreen(
            context,
            EnvironmentDetailScreen(environment: environment),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14,
            ),
            child: Row(
              children: [
                // Ícone: squircle estilo Apple app icon, cor semântica do mapper
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: visual.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    visual.emoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
                const SizedBox(width: 14),

                // Nome + raio
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        environment.name,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.radio_button_unchecked,
                            size: 10,
                            color: AppColors.textDisabled,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${environment.radiusMeters.toInt()} m de raio',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Badge de contagem de triggers
                triggersAsync.when(
                  data: (triggers) =>
                      _TriggerCountBadge(count: triggers.length),
                  loading: () => const SizedBox(width: 44, height: 44),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
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
          AppStrings.environmentDeleteConfirm,
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
}

/// Badge de contagem de triggers com ícone bolt e hierarquia clara.
class _TriggerCountBadge extends StatelessWidget {
  final int count;

  const _TriggerCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '—',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textDisabled,
            ),
          ),
          Text(
            AppStrings.triggers,
            style: AppTypography.caption.copyWith(
              color: AppColors.textDisabled,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 14, color: AppColors.accent),
            const SizedBox(width: 2),
            Text(
              '$count',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Text(
          count == 1 ? 'gatilho' : AppStrings.triggers,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Background de exclusão (swipe endToStart) — usa danger, não primary.
class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.gap6,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.lg),
      child: const Icon(
        Icons.delete_outline,
        color: AppColors.textPrimary,
        size: 26,
      ),
    );
  }
}

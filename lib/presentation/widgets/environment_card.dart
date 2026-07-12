import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/strings.dart';
import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/environment_icon_mapper.dart';
import '../../domain/entities/environment_entity.dart';
import '../providers/database_provider.dart';
import '../providers/trigger_providers.dart';
import '../screens/environment/environment_detail_screen.dart';
import 'sopro_card.dart';

/// Card de ambiente — Dark Glass Dashboard.
/// Layout customizado: ícone 64×64, nome, separador, raio + badge de triggers.
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
        glass: true,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          onTap: () => pushScreen(
            context,
            EnvironmentDetailScreen(environment: environment),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Ícone: 64×64 squircle, cor semântica do mapper
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: visual.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      // ignore: deprecated_member_use
                      color: visual.color.withOpacity(0.20),
                      width: 0.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    visual.emoji,
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
                const SizedBox(width: 16),

                // Conteúdo: nome + separador + metadados
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nome + seta
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              environment.name,
                              style: AppTypography.titleSmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.textDisabled,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Separador glass
                      Container(
                        height: 0.5,
                        color: AppColors.border,
                      ),
                      const SizedBox(height: 10),

                      // Raio + badge de triggers
                      Row(
                        children: [
                          const Icon(
                            Icons.my_location,
                            size: 11,
                            color: AppColors.textDisabled,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${environment.radiusMeters.toInt()} m',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textDisabled,
                            ),
                          ),
                          const Spacer(),
                          triggersAsync.when(
                            data: (triggers) =>
                                _TriggerCountBadge(count: triggers.length),
                            loading: () => const SizedBox(width: 56, height: 14),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ],
                  ),
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

/// Badge inline de contagem de triggers.
class _TriggerCountBadge extends StatelessWidget {
  final int count;

  const _TriggerCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text(
        'Nenhum gatilho',
        style: AppTypography.caption.copyWith(color: AppColors.textDisabled),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bolt, size: 12, color: AppColors.accent),
        const SizedBox(width: 3),
        Text(
          '$count ${count == 1 ? 'gatilho' : AppStrings.triggers}',
          style: AppTypography.caption.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Background de exclusão (swipe endToStart) — gradiente danger direcionado.
class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0x33FF5B5B), // danger 20%
            Color(0xD9FF5B5B), // danger 85%
          ],
        ),
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0x4DFF5B5B), width: 0.5), // danger 30%
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(
        Icons.delete_outline,
        color: AppColors.textPrimary,
        size: 26,
      ),
    );
  }
}

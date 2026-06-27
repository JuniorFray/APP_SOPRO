import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/environment_entity.dart';
import '../providers/database_provider.dart';
import '../providers/trigger_providers.dart';
import '../screens/environment/environment_detail_screen.dart';

// Card que representa um Environment na lista da Home.
// Exibe nome, raio e contagem de triggers. Permite excluir via swipe.
class EnvironmentCard extends ConsumerWidget {
  final EnvironmentEntity environment;

  const EnvironmentCard({super.key, required this.environment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observa os triggers para exibir a contagem no card
    final triggersAsync =
        ref.watch(triggersByEnvironmentProvider(environment.id));

    return Dismissible(
      key: ValueKey(environment.id),
      direction: DismissDirection.endToStart,
      // Confirmação antes de excluir para evitar exclusão acidental
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        ref.read(environmentRepositoryProvider).delete(environment.id);
      },
      background: _DeleteBackground(),
      child: Card(
        color: AppTheme.backgroundSurface,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.backgroundElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.place_outlined, color: AppTheme.accent),
          ),
          title: Text(
            environment.name,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${environment.radiusMeters.toStringAsFixed(0)}m de raio',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          // Navega para a tela de detalhe com a lista de triggers
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  EnvironmentDetailScreen(environment: environment),
            ),
          ),
          trailing: triggersAsync.when(
            data: (triggers) => _TriggerCountBadge(count: triggers.length),
            loading: () => const SizedBox(width: 32, height: 32),
            error: (_, __) => const SizedBox.shrink(),
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
          AppStrings.environmentDeleteConfirm,
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

// Badge com contagem de triggers no canto direito do card
class _TriggerCountBadge extends StatelessWidget {
  final int count;

  const _TriggerCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$count',
          style: const TextStyle(
            color: AppTheme.accent,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Text(
          count == 1 ? 'gatilho' : AppStrings.triggers,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

// Background vermelho exibido ao arrastar para excluir
class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
    );
  }
}

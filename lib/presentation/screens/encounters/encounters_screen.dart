// EncountersScreen — Histórico de encontros BLE.
//
// Lista os ContextCards de outros usuários Sopro com quem o usuário já
// trocou cartões via GATT. Cada registro exibe:
//   - Avatar com inicial do nome
//   - Nome + linha de ocupação (cargo · empresa)
//   - Data do último encontro
//   - Botão de remoção individual
//
// Funcionalidades:
//   - Swipe-to-delete ou botão de lixeira para remover um encontro
//   - Botão "Limpar histórico" no AppBar para apagar tudo (privacidade)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/ble_encounter_entity.dart';
import '../../providers/database_provider.dart';
import '../../providers/encounter_providers.dart';

class EncountersScreen extends ConsumerWidget {
  const EncountersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final encountersAsync = ref.watch(encountersStreamProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.encountersTitle),
        backgroundColor: AppTheme.backgroundSurface,
        actions: [
          // Botão de limpar histórico — só aparece quando há encontros
          encountersAsync.whenData((list) => list).valueOrNull?.isNotEmpty == true
              ? IconButton(
                  onPressed: () => _confirmClearAll(context, ref),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: AppStrings.encounterClearAll,
                )
              : const SizedBox.shrink(),
        ],
      ),
      body: encountersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
        error: (_, __) => const Center(
          child: Text(
            AppStrings.errorGeneric,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        data: (encounters) => encounters.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: encounters.length,
                itemBuilder: (_, i) => _EncounterTile(
                  encounter: encounters[i],
                  onDelete: () => ref
                      .read(bleEncounterRepositoryProvider)
                      .delete(encounters[i].deviceId),
                ),
              ),
      ),
    );
  }

  // Dialog de confirmação antes de limpar tudo
  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundSurface,
        title: const Text(
          AppStrings.encounterClearAll,
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          AppStrings.encounterClearConfirm,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
            child: const Text(AppStrings.encounterClearAll),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(bleEncounterRepositoryProvider).deleteAll();
    }
  }
}

// Tile de um único encontro com swipe para deletar
class _EncounterTile extends StatelessWidget {
  final BleEncounterEntity encounter;
  final VoidCallback onDelete;

  const _EncounterTile({required this.encounter, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(encounter.deviceId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade800,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 24,
          // ignore: deprecated_member_use
          backgroundColor: AppTheme.accent.withOpacity(0.15),
          child: Text(
            encounter.initial,
            style: const TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        title: Text(
          encounter.displayName.isNotEmpty
              ? encounter.displayName
              : encounter.deviceId,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (encounter.occupationLine.isNotEmpty)
              Text(
                encounter.occupationLine,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            Text(
              _formatDate(encounter.encounteredAt),
              style: const TextStyle(
                color: AppTheme.textDisabled,
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: AppTheme.textDisabled),
          tooltip: AppStrings.encounterDeleteBtn,
          onPressed: onDelete,
        ),
      ),
    );
  }

  // Formata a data como "hoje", "ontem" ou "dd/MM/yy"
  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);

    if (day == today) return 'Hoje';
    if (today.difference(day).inDays == 1) return 'Ontem';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${(dt.year % 100).toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppTheme.textDisabled),
          SizedBox(height: 20),
          Text(
            AppStrings.encountersEmpty,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              AppStrings.encountersEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

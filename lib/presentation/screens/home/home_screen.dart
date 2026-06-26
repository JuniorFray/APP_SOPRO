// Tela principal do Sopro — lista de ambientes cadastrados pelo usuário.
// Sprint 2: consome dados reais do banco via Riverpod + Drift.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/environment_providers.dart';
import '../../widgets/environment_card.dart';
import 'add_environment_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observa a lista de environments em tempo real
    final environmentsAsync = ref.watch(environmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.homeTitle),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.person_outline),
            tooltip: AppStrings.profileTooltip,
          ),
        ],
      ),
      body: environmentsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
        error: (e, _) => const Center(
          child: Text(
            AppStrings.errorGeneric,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        data: (environments) => environments.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: environments.length,
                itemBuilder: (_, i) =>
                    EnvironmentCard(environment: environments[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const AddEnvironmentDialog(),
        ),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.newEnvironment),
      ),
    );
  }
}

// Estado vazio — exibido quando não há nenhum ambiente cadastrado
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.air, size: 80, color: AppTheme.accent),
          SizedBox(height: 24),
          Text(
            AppStrings.homeEmptyTitle,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            AppStrings.homeEmptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

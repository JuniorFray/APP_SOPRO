// EnvironmentsTabContent — conteúdo da aba "Ambientes" do bottom nav.
//
// Reaproveita a MESMA lista de EnvironmentCard da Home (environmentsProvider),
// com AppBar próprio "Ambientes". A criação de ambiente também fica aqui: botão
// (+) na AppBar reusa a MESMA navegação da composer bar da Home.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../providers/environment_providers.dart';
import '../../widgets/environment_card.dart';
import '../../widgets/glass_surface.dart';
import 'add_environment_screen.dart';
import 'environments_map_screen.dart';

// Card de privacidade — controle de exibição em duas camadas:
// - sessão: "OK" esconde o card mas ele reaparece numa NOVA sessão do app
//   (só RAM, StateProvider — não persiste).
// - permanente: "Não avisar mais" grava em SharedPreferences e nunca mais mostra.
final _privacyCardSessionDismissedProvider = StateProvider<bool>((_) => false);

const _privacyCardForeverKey = 'privacy_card_dismissed_forever';

final _privacyCardForeverProvider = FutureProvider<bool>((_) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_privacyCardForeverKey) ?? false;
});

class EnvironmentsTabContent extends ConsumerWidget {
  const EnvironmentsTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environmentsAsync = ref.watch(environmentsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Liquid Glass — mesma identidade das demais telas.
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
        title: const Text(
          AppStrings.environmentsTabTitle,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          // Cria ambiente — mesma navegação usada pelo (+) da composer bar da Home.
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textPrimary),
            tooltip: AppStrings.environmentsAddTooltip,
            onPressed: () =>
                pushScreen(context, const AddEnvironmentScreen()),
          ),
          // Abre a tela de mapa em tela cheia com todos os ambientes.
          IconButton(
            icon: const Icon(Icons.map_outlined, color: AppColors.textPrimary),
            tooltip: AppStrings.environmentsMapTooltip,
            onPressed: () =>
                pushScreen(context, const EnvironmentsMapScreen()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Aviso de privacidade no topo (decide sozinho se aparece).
          const _PrivacyNoticeCard(),
          Expanded(
            child: environmentsAsync.when(
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
              data: (environments) => environments.isEmpty
                  ? _EnvironmentsEmpty()
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, 24),
                      itemCount: environments.length,
                      itemBuilder: (_, i) =>
                          EnvironmentCard(environment: environments[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// Card âmbar dispensável reforçando que a localização é on-device.
// Só é montado se NÃO foi dispensado para sempre (checado antes de tudo) e
// NÃO foi fechado nesta sessão.
class _PrivacyNoticeCard extends ConsumerWidget {
  const _PrivacyNoticeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // valueOrNull == null enquanto a prefs carrega → oculta (evita flash).
    final dismissedForever =
        ref.watch(_privacyCardForeverProvider).valueOrNull ?? true;
    final dismissedSession = ref.watch(_privacyCardSessionDismissedProvider);
    if (dismissedForever || dismissedSession) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline,
                  size: 20, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppStrings.privacyCardMessage,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Nunca mais: persiste em SharedPreferences e re-lê o provider.
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_privacyCardForeverKey, true);
                  ref.invalidate(_privacyCardForeverProvider);
                },
                child: const Text(
                  AppStrings.privacyCardNeverAgain,
                  style: TextStyle(color: AppColors.textDisabled),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // OK: some só nesta sessão (RAM) — volta numa sessão nova.
              TextButton(
                onPressed: () => ref
                    .read(_privacyCardSessionDismissedProvider.notifier)
                    .state = true,
                child: const Text(
                  AppStrings.privacyCardOk,
                  style: TextStyle(color: AppColors.warning),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Estado vazio simples — reusa as strings da Home.
class _EnvironmentsEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_outlined,
                size: 48, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.homeEmptyTitle,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.homeEmptySubtitle,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textDisabled,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

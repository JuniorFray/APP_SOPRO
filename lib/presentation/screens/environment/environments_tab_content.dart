// EnvironmentsTabContent — conteúdo da aba "Ambientes" do bottom nav.
//
// Reaproveita a MESMA lista de EnvironmentCard da Home (environmentsProvider),
// com AppBar próprio "Ambientes". Sem FABs — a criação continua pela Home/voz.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../providers/environment_providers.dart';
import '../../widgets/environment_card.dart';
import '../../widgets/glass_surface.dart';

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
      ),
      body: environmentsAsync.when(
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

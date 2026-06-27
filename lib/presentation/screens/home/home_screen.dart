// HomeScreen — Tela principal do Sopro.
//
// Responsabilidades:
//   1. Verificar primeiro acesso: se não há ContextCard no banco → onboarding
//   2. Iniciar geofences após confirmar que o perfil existe
//   3. Listar ambientes cadastrados pelo usuário
//   4. Navegar para PeopleNearbyScreen e ProfileScreen

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/database_provider.dart';
import '../../providers/environment_providers.dart';
import '../../providers/location_providers.dart';
import '../../widgets/environment_card.dart';
import '../ble/people_nearby_screen.dart';
import '../environment/add_environment_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // false enquanto verifica se o onboarding já foi concluído
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Executa depois do primeiro frame para que o Navigator já esteja disponível
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnboarding());
  }

  // Verifica se o usuário já criou um ContextCard (= onboarding concluído).
  // Se não → redireciona para onboarding.
  // Se sim → inicia geofences e mostra a tela normalmente.
  Future<void> _checkOnboarding() async {
    final card = await ref.read(contextCardRepositoryProvider).getActive();
    if (!mounted) return;

    if (card == null) {
      // Primeiro acesso: vai para o onboarding e aguarda a conclusão.
      // O onboarding termina com pushNamedAndRemoveUntil('/home'), criando
      // um novo HomeScreen que já encontrará o card e seguirá o caminho normal.
      await Navigator.pushNamed(context, '/onboarding');
      // Se o usuário saiu do onboarding sem criar perfil (back), tenta de novo
      if (mounted) _checkOnboarding();
      return;
    }

    // Perfil existe: inicia o monitoramento de geofences com permissões já concedidas
    await ref.read(geofenceManagerProvider).start();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // Exibe loading enquanto verifica o estado de onboarding
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
      );
    }

    final environmentsAsync = ref.watch(environmentsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.homeTitle),
        backgroundColor: AppTheme.backgroundSurface,
        actions: [
          // Abre a tela de BLE Social ("Pessoas Aqui")
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PeopleNearbyScreen()),
            ),
            icon: const Icon(Icons.people_outline),
            tooltip: AppStrings.peopleNearby,
          ),
          // Abre a tela de perfil (ContextCard)
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/profile'),
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
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEnvironmentScreen()),
        ),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.newEnvironment),
      ),
    );
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

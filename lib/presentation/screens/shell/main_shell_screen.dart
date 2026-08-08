// MainShellScreen — raiz do app após o entry point.
//
// Responsabilidades (herdadas do antigo HomeScreen):
//   1. Verificar primeiro acesso via SharedPreferences ('onboarding_done'):
//      - false → pushReplacementNamed('/onboarding')
//      - true  → checa requisitos do dispositivo e inicia geofences/serviços
//   2. Ciclo de vida: onResume/cold-start invalidam providers e tratam o
//      "pending de localização" deixado pelo FloatingVoiceService.
//   3. Bottom navigation de 4 abas (Início / Lembretes / Ambientes / Perfil),
//      com IndexedStack preservando o estado de cada aba.
//
// O conteúdo visual da Home vive em HomeTabContent — este widget é a casca de
// navegação + inicialização, não renderiza a lista de ambientes diretamente.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/environment_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/scheduled_reminder_providers.dart';
import '../../providers/shopping_list_providers.dart';
import '../../providers/trigger_providers.dart';
import '../../widgets/device_requirements_guard.dart';
import '../../widgets/glass_surface.dart';
import '../environment/add_environment_screen.dart';
import '../environment/environments_tab_content.dart';
import '../home/home_composer_bar.dart';
import '../home/home_tab_content.dart';
import '../profile/profile_screen.dart';
import '../reminders/reminders_tab_content.dart';
import '../agenda/agenda_screen.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  // false enquanto verifica o flag de onboarding e inicia serviços
  bool _ready = false;

  // Aba selecionada no bottom nav (0 = Início)
  int _currentTabIndex = 0;

  late final AppLifecycleListener _lifecycleListener;

  // Canal push nativo→Flutter (mesmo nome do lado MainActivity). O
  // FloatingVoiceService avisa "dataChanged" quando muda dados com o app já vivo.
  static const _overlaySyncChannel = MethodChannel('com.sopro.sopro/overlay_sync');

  @override
  void initState() {
    super.initState();
    // 3 gatilhos para a MESMA reconciliação (_syncFromNative): retorno ao
    // foreground (onResume), push do canal (app já vivo sob o overlay) e cold start.
    _lifecycleListener = AppLifecycleListener(onResume: _syncFromNative);
    _overlaySyncChannel.setMethodCallHandler((call) async {
      if (call.method == 'dataChanged') await _syncFromNative();
    });

    // Executa depois do primeiro frame para que o Navigator esteja disponível
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnboarding());
    // Cold start: reflete o que o FloatingVoiceService escreveu com o app fechado.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromNative());
  }

  // Reconcilia a UI com mudanças feitas fora da árvore Flutter — o
  // FloatingVoiceService grava SQLite direto (ambiente sem coords, wipe total) e
  // avisa via prefs/push. Fonte ÚNICA usada pelos 3 gatilhos do initState.
  Future<void> _syncFromNative() async {
    final prefs = await SharedPreferences.getInstance();
    // needs_refresh é consumido; a invalidação abaixo roda sempre (flag informativa).
    if (prefs.getBool('needs_refresh') ?? false) {
      await prefs.setBool('needs_refresh', false);
    }
    if (!mounted) return;
    ref.invalidate(environmentsProvider);
    ref.invalidate(triggersByEnvironmentProvider);
    // Lembretes por tempo e lista de compras também são gravados pelo overlay via
    // SQL raw (fora do stream do Drift, que não detecta gravação externa): invalida
    // para refletir na tela sem precisar fechar/reabrir o app.
    ref.invalidate(allActiveRemindersProvider);
    ref.invalidate(nextReminderProvider);
    ref.invalidate(shoppingListByEnvironmentProvider);

    // Ambiente criado por voz sem coords → abre a AddEnvironmentScreen em modo
    // só-localização. Limpa o pending antes de navegar (não reabre no próximo sync).
    final pendingEnvId = prefs.getString('pending_location_env_id');
    if (pendingEnvId != null) {
      final pendingEnvName = prefs.getString('pending_location_env_name');
      await prefs.remove('pending_location_env_id');
      await prefs.remove('pending_location_env_name');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          pushScreen(
            context,
            AddEnvironmentScreen(
              pendingEnvironmentId: pendingEnvId,
              pendingEnvironmentName: pendingEnvName,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _overlaySyncChannel.setMethodCallHandler(null);
    _lifecycleListener.dispose();
    super.dispose();
  }

  // Verifica se o onboarding já foi concluído pelo usuário.
  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;

    if (!onboardingDone) {
      // Substitui o shell pelo onboarding no primeiro acesso
      Navigator.pushReplacementNamed(context, '/onboarding');
      return;
    }

    // Verifica requisitos do dispositivo antes de iniciar funcionalidades
    if (mounted) await DeviceRequirementsGuard.check(context, ref);
    if (!mounted) return;

    // Onboarding concluído: inicia geofences com permissões já concedidas
    await ref.read(geofenceManagerProvider).start();
    if (mounted) setState(() => _ready = true);
  }

  // Descrição de uma aba do bottom nav (ícone normal + preenchido + rótulo)
  static const _tabs = <({IconData icon, IconData active, String label})>[
    (icon: Icons.home_outlined,          active: Icons.home,          label: AppStrings.navHome),
    (icon: Icons.notifications_outlined, active: Icons.notifications, label: AppStrings.navReminders),
    (icon: Icons.calendar_today_outlined,active: Icons.calendar_today,label: 'Agenda'),
    (icon: Icons.location_on_outlined,   active: Icons.location_on,   label: AppStrings.navEnvironments),
    (icon: Icons.person_outline,         active: Icons.person,        label: AppStrings.navProfile),
  ];

  @override
  Widget build(BuildContext context) {
    // Exibe loading enquanto verifica SharedPreferences / inicia geofences
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2.5,
            strokeCap: StrokeCap.round,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      // IndexedStack mantém as 4 abas montadas — preserva scroll ao trocar de aba.
      // Perfil dentro da aba: sem seta de voltar (não há "voltar" de uma aba).
      // A HomeComposerBar fica FIXA abaixo do stack (acima da bottom nav) e só
      // aparece nas abas Início (0) e Lembretes (1).
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentTabIndex,
              children: [
                // Início pode pedir troca de aba (ex.: "Ver todos" → Ambientes).
                HomeTabContent(
                  onNavigateToTab: (i) => setState(() => _currentTabIndex = i),
                ),
                const RemindersTabContent(),
                const AgendaScreen(),
                const EnvironmentsTabContent(),
                const ProfileScreen(showBackButton: false),
              ],
            ),
          ),
          if (_currentTabIndex == 0 || _currentTabIndex == 1)
            const HomeComposerBar(),
        ],
      ),
      // Liquid Glass no topo do nav — mesma identidade do resto do app.
      bottomNavigationBar: GlassSurface(
        borderRadius: BorderRadius.zero,
        edges: GlassEdges.top,
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentTabIndex,
          onTap: (i) => setState(() => _currentTabIndex = i),
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.textSecondary,
          showUnselectedLabels: true,
          items: [
            for (var i = 0; i < _tabs.length; i++)
              BottomNavigationBarItem(
                icon: Icon(
                  _currentTabIndex == i ? _tabs[i].active : _tabs[i].icon,
                ),
                label: _tabs[i].label,
              ),
          ],
        ),
      ),
    );
  }
}

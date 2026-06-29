import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/ble_providers.dart';
import '../../providers/settings_providers.dart';
import '../encounters/encounters_screen.dart';

// Tela de Configurações do Sopro.
// Agrupa preferências de privacidade, notificações e dados.
// Usa Riverpod para leitura/escrita em memória e SharedPreferences para persistência.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lê todos os toggles de configuração
    final bleVisible    = ref.watch(bleVisibleProvider);
    final notifEnabled  = ref.watch(notificationsEnabledProvider);
    final notifSound    = ref.watch(notificationSoundProvider);
    final notifCooldown = ref.watch(notificationCooldownMinutesProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.settingsTitle),
        backgroundColor: AppTheme.backgroundSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ─── Seção: Bluetooth Social ───────────────────────────────────────
          const _SectionHeader(label: AppStrings.settingsBleSection),

          _SwitchTile(
            icon: Icons.bluetooth,
            title: AppStrings.settingsBleVisible,
            subtitle: AppStrings.settingsBleVisibleDesc,
            value: bleVisible,
            onChanged: (v) {
              // Altera o estado em memória; PeopleNearbyScreen o lê antes
              // de iniciar advertising. Não precisa de persistência extra
              // porque o advertising é iniciado manualmente pelo usuário.
              ref.read(bleVisibleProvider.notifier).state = v;
            },
          ),

          const _Divider(),

          // ─── Seção: Notificações ───────────────────────────────────────────
          const _SectionHeader(label: AppStrings.settingsNotifSection),

          _SwitchTile(
            icon: Icons.notifications_outlined,
            title: AppStrings.settingsNotifEnabled,
            subtitle: AppStrings.settingsNotifEnabledDesc,
            value: notifEnabled,
            onChanged: (v) async {
              // Atualiza em memória imediatamente (FireTriggersUseCase lê via callback)
              ref.read(notificationsEnabledProvider.notifier).state = v;
              // Persiste a preferência para sobreviver ao reinício do app
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('notifications_enabled', v);
            },
          ),

          // Toggle de som — ativo mesmo quando notificações estão desabilitadas
          // para que o usuário pré-configure antes de reativar
          _SwitchTile(
            icon: Icons.volume_up_outlined,
            title: AppStrings.settingsNotifSound,
            subtitle: AppStrings.settingsNotifSoundDesc,
            value: notifSound,
            onChanged: (v) async {
              ref.read(notificationSoundProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('notification_sound_enabled', v);
            },
          ),

          // Seletor de frequência mínima entre notificações
          _CooldownTile(
            value: notifCooldown,
            onChanged: (v) async {
              ref.read(notificationCooldownMinutesProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('notification_cooldown_minutes', v);
            },
          ),

          const _Divider(),

          // ─── Seção: Dados ──────────────────────────────────────────────────
          const _SectionHeader(label: AppStrings.settingsDataSection),

          _NavTile(
            icon: Icons.person_outline,
            title: AppStrings.settingsMyProfile,
            onTap: () => Navigator.pushNamed(context, '/profile'),
          ),

          _NavTile(
            icon: Icons.people_outline,
            title: AppStrings.settingsMyEncounters,
            onTap: () => pushScreen(context, const EncountersScreen()),
          ),

          const _Divider(),

          // ─── Seção: Sobre ──────────────────────────────────────────────────
          const _SectionHeader(label: AppStrings.settingsAboutSection),

          // Descrição do app
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              AppStrings.settingsAppDesc,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),

          // Versão do app
          const _InfoTile(
            icon: Icons.info_outline,
            title: AppStrings.settingsVersion,
            value: AppStrings.settingsAppVersion,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Widgets internos ─────────────────────────────────────────────────────────

// Cabeçalho de seção com texto em maiúsculas
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// Linha de configuração com ícone, título, subtítulo e Switch
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.accent, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.accent,
      ),
    );
  }
}

// Seletor de frequência de notificação com DropdownButton
class _CooldownTile extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _CooldownTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.timer_outlined, color: AppTheme.accent, size: 20),
      ),
      title: const Text(
        AppStrings.settingsNotifCooldown,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: const Text(
        AppStrings.settingsNotifCooldownDesc,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      // DropdownButton integrado ao trailing do ListTile
      trailing: DropdownButton<int>(
        value: value,
        dropdownColor: AppTheme.backgroundElevated,
        underline: const SizedBox.shrink(),
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        items: const [
          DropdownMenuItem(value: 0,  child: Text('Sempre')),
          DropdownMenuItem(value: 5,  child: Text('5 min')),
          DropdownMenuItem(value: 15, child: Text('15 min')),
          DropdownMenuItem(value: 30, child: Text('30 min')),
          DropdownMenuItem(value: 60, child: Text('1 hora')),
        ],
        onChanged: (v) => onChanged(v!),
      ),
    );
  }
}

// Linha de navegação com ícone e seta
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.textSecondary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppTheme.textDisabled,
      ),
      onTap: onTap,
    );
  }
}

// Linha informativa com ícone, título e valor
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.textSecondary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      trailing: Text(
        value,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }
}

// Linha divisória sutil entre seções
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      color: AppTheme.backgroundElevated,
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }
}

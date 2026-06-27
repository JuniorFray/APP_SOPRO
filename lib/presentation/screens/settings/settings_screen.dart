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
// Agrupa preferências de privacidade, conectividade e informações do app.
// Usa Riverpod para leitura/escrita em memória e SharedPreferences para persistência.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lê os toggles de visibilidade BLE e notificações
    final bleVisible    = ref.watch(bleVisibleProvider);
    final notifEnabled  = ref.watch(notificationsEnabledProvider);

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

          const _Divider(),

          // ─── Seção: Dados ──────────────────────────────────────────────────
          const _SectionHeader(label: AppStrings.settingsDataSection),

          _NavTile(
            icon: Icons.person_outline,
            title: AppStrings.settingsMyProfile,
            onTap: () => Navigator.pushNamed(context, '/profile'),
          ),

          _NavTile(
            icon: Icons.history,
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

          // Link para código-fonte (copiável)
          _InfoTile(
            icon: Icons.code,
            title: AppStrings.settingsSourceCode,
            value: '',
            onTap: () => _showSourceInfo(context),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Exibe o URL do repositório em um bottom sheet copiável
  void _showSourceInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alça visual do bottom sheet
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Código-fonte',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // URL do repositório em fonte monospace para destaque visual
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.backgroundSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SelectableText(
                'https://${AppStrings.settingsSourceCode}',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecione e copie o link acima para abrir no navegador.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
          ],
        ),
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
  final VoidCallback? onTap;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
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
      trailing: value.isNotEmpty
          ? Text(
              value,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            )
          : onTap != null
              ? const Icon(Icons.chevron_right, color: AppTheme.textDisabled)
              : null,
      onTap: onTap,
    );
  }
}

// Separador visual entre seções
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

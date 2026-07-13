import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../providers/ble_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/glass_surface.dart';
import '../encounters/encounters_screen.dart';
import '../../../infrastructure/overlay/floating_voice_service_manager.dart';

// Canal nativo para o FloatingVoiceService (botão flutuante de voz)
const _overlayChannel = MethodChannel('com.sopro.sopro/overlay');

// Tela de Configurações do Sopro.
// Agrupa preferências de privacidade, notificações e dados.
// Usa Riverpod para leitura/escrita em memória e SharedPreferences para persistência.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lê todos os toggles de configuração
    final bleVisible    = ref.watch(bleVisibleProvider);
    final bleTxPower    = ref.watch(bleTxPowerProvider);
    final notifEnabled  = ref.watch(notificationsEnabledProvider);
    final notifSound    = ref.watch(notificationSoundProvider);
    final notifCooldown = ref.watch(notificationCooldownMinutesProvider);
    final voiceAudio        = ref.watch(voiceAudioResponseProvider);
    final voiceText         = ref.watch(voiceTextResponseProvider);
    final voiceRate         = ref.watch(voiceSpeechRateProvider);
    final floatingVoice     = ref.watch(floatingVoiceEnabledProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.settingsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Liquid Glass — delega ao primitivo central GlassSurface.
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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

          // Seletor de potência BLE — afeta alcance de detecção por outros
          _BlePowerTile(
            value: bleTxPower,
            onChanged: (v) async {
              ref.read(bleTxPowerProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('ble_tx_power', v);
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

          // ─── Seção: Interação por voz ──────────────────────────────────────
          const _SectionHeader(label: AppStrings.voiceSection),

          _SwitchTile(
            icon: Icons.record_voice_over_outlined,
            title: AppStrings.voiceAudioResponse,
            subtitle: AppStrings.voiceAudioResponseDesc,
            value: voiceAudio,
            onChanged: (v) async {
              ref.read(voiceAudioResponseProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('voice_audio_response', v);
            },
          ),

          _SwitchTile(
            icon: Icons.subtitles_outlined,
            title: AppStrings.voiceTextResponse,
            subtitle: AppStrings.voiceTextResponseDesc,
            value: voiceText,
            onChanged: (v) async {
              ref.read(voiceTextResponseProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('voice_text_response', v);
            },
          ),

          // Seletor de velocidade de fala com DropdownButton
          _VoiceRateTile(
            value: voiceRate,
            onChanged: (v) async {
              ref.read(voiceSpeechRateProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('voice_speech_rate', v);
            },
          ),

          const _Divider(),

          // ─── Seção: Acesso rápido (botão flutuante de voz) ────────────────
          const _SectionHeader(label: AppStrings.settingsOverlaySection),

          _OverlayToggleTile(
            value: floatingVoice,
            onChanged: (v) async {
              if (v) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('floating_voice_enabled', true);
                ref.read(floatingVoiceEnabledProvider.notifier).state = true;
                try {
                  final String? failure =
                      await FloatingVoiceServiceManager.tryStart(
                          requestPermissionsIfNeeded: true);
                  if (failure == 'overlay_denied') {
                    // Redireciona para conceder SYSTEM_ALERT_WINDOW — toggle fica desligado
                    await _overlayChannel.invokeMethod<void>(
                        'openOverlayPermissionSettings');
                    await prefs.setBool('floating_voice_enabled', false);
                    ref.read(floatingVoiceEnabledProvider.notifier).state =
                        false;
                  } else if (failure != null) {
                    await prefs.setBool('floating_voice_enabled', false);
                    ref.read(floatingVoiceEnabledProvider.notifier).state =
                        false;
                  }
                } catch (_) {
                  await prefs.setBool('floating_voice_enabled', false);
                  ref.read(floatingVoiceEnabledProvider.notifier).state = false;
                }
              } else {
                await FloatingVoiceServiceManager.stop();
                ref.read(floatingVoiceEnabledProvider.notifier).state = false;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('floating_voice_enabled', false);
              }
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
            padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xxs, AppSpacing.md, AppSpacing.sm),
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

          const SizedBox(height: AppSpacing.xxl),
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.gap6),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelMedium.copyWith(color: AppTheme.accent),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Icon(icon, color: AppTheme.accent, size: 20),
      ),
      title: Text(
        title,
        style: AppTypography.titleSmall.copyWith(color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.accent,
      ),
    );
  }
}

// Seletor de potência de transmissão BLE com DropdownButton.
// 0=ULTRA_LOW (~2m), 1=LOW (~5m), 2=MEDIUM (~10m), 3=HIGH (~20m+)
class _BlePowerTile extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _BlePowerTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.settings_input_antenna, color: AppTheme.accent, size: 20),
      ),
      title: Text(
        AppStrings.settingsBleTxPower,
        style: AppTypography.titleSmall.copyWith(color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        AppStrings.settingsBleTxPowerDesc,
        style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      trailing: DropdownButton<int>(
        value: value,
        dropdownColor: AppTheme.backgroundElevated,
        underline: const SizedBox.shrink(),
        style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
        items: const [
          DropdownMenuItem(value: 0, child: Text(AppStrings.bleTxPowerMin)),
          DropdownMenuItem(value: 1, child: Text(AppStrings.bleTxPowerLow)),
          DropdownMenuItem(value: 2, child: Text(AppStrings.bleTxPowerMed)),
          DropdownMenuItem(value: 3, child: Text(AppStrings.bleTxPowerHigh)),
        ],
        onChanged: (v) => onChanged(v!),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.timer_outlined, color: AppTheme.accent, size: 20),
      ),
      title: Text(
        AppStrings.settingsNotifCooldown,
        style: AppTypography.titleSmall.copyWith(color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        AppStrings.settingsNotifCooldownDesc,
        style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      // DropdownButton integrado ao trailing do ListTile
      trailing: DropdownButton<int>(
        value: value,
        dropdownColor: AppTheme.backgroundElevated,
        underline: const SizedBox.shrink(),
        style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
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

// Seletor de velocidade de síntese de voz (TTS): Lenta / Normal / Rápida
class _VoiceRateTile extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _VoiceRateTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.speed_outlined, color: AppTheme.accent, size: 20),
      ),
      title: Text(
        AppStrings.voiceSpeechRate,
        style: AppTypography.titleSmall.copyWith(color: AppTheme.textPrimary),
      ),
      trailing: DropdownButton<double>(
        value: value,
        dropdownColor: AppTheme.backgroundElevated,
        underline: const SizedBox.shrink(),
        style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
        items: const [
          DropdownMenuItem(value: 0.3, child: Text(AppStrings.voiceRateSlow)),
          DropdownMenuItem(value: 0.5, child: Text(AppStrings.voiceRateNormal)),
          DropdownMenuItem(value: 0.7, child: Text(AppStrings.voiceRateFast)),
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
        style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }
}

// Toggle do botão flutuante de voz.
// Verifica permissão SYSTEM_ALERT_WINDOW antes de ativar o serviço overlay.
// Se a permissão não foi concedida, abre as configurações do sistema para o usuário.
class _OverlayToggleTile extends StatelessWidget {
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _OverlayToggleTile({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.mic_external_on_outlined,
            color: AppTheme.accent, size: 20),
      ),
      title: Text(
        AppStrings.settingsOverlayEnabled,
        style: AppTypography.titleSmall.copyWith(color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        AppStrings.settingsOverlayEnabledDesc,
        style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      trailing: Switch(
        value: value,
        onChanged: (v) => onChanged(v),
        activeColor: AppTheme.accent,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../providers/ble_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_card.dart';
import '../../../infrastructure/overlay/floating_voice_service_manager.dart';

// Canal nativo para o FloatingVoiceService (botão flutuante de voz)
const _overlayChannel = MethodChannel('com.sopro.sopro/overlay');

// Canal nativo dos lembretes/alarmes — reaproveitado para a notificação diária
// de clima (scheduleWeatherNotification / cancelWeatherNotification).
const _remindersChannel = MethodChannel('com.sopro.sopro/reminders');

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
          _SectionCard(
            children: [
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
              const _ItemDivider(),
              // Seletor de potência BLE — afeta alcance de detecção por outros
              _BlePowerTile(
                value: bleTxPower,
                onChanged: (v) async {
                  ref.read(bleTxPowerProvider.notifier).state = v;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('ble_tx_power', v);
                },
              ),
            ],
          ),

          // ─── Seção: Notificações ───────────────────────────────────────────
          const _SectionHeader(label: AppStrings.settingsNotifSection),
          _SectionCard(
            children: [
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
              const _ItemDivider(),
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
              const _ItemDivider(),
              // Seletor de frequência mínima entre notificações
              _CooldownTile(
                value: notifCooldown,
                onChanged: (v) async {
                  ref.read(notificationCooldownMinutesProvider.notifier).state = v;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('notification_cooldown_minutes', v);
                },
              ),
              const _ItemDivider(),
              // Notificação diária de clima (switch + horário) — self-contained.
              const _WeatherNotifTile(),
            ],
          ),

          // ─── Seção: Interação por voz ──────────────────────────────────────
          const _SectionHeader(label: AppStrings.voiceSection),
          _SectionCard(
            children: [
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
              const _ItemDivider(),
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
              const _ItemDivider(),
              // Seletor de velocidade de fala com DropdownButton
              _VoiceRateTile(
                value: voiceRate,
                onChanged: (v) async {
                  ref.read(voiceSpeechRateProvider.notifier).state = v;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setDouble('voice_speech_rate', v);
                },
              ),
            ],
          ),

          // ─── Seção: Acesso rápido (botão flutuante de voz) ────────────────
          const _SectionHeader(label: AppStrings.settingsOverlaySection),
          _SectionCard(
            children: [
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
            ],
          ),

          // ─── Seção: Acesso rápido (atalhos Privacidade / Suporte) ─────────
          const _SectionHeader(label: AppStrings.settingsShortcutsSection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: _ShortcutBlock(
                    icon: Icons.shield_rounded,
                    label: AppStrings.settingsShortcutPrivacy,
                    // TODO: navegar para tela de Privacidade quando existir
                    onTap: () => _comingSoon(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _ShortcutBlock(
                    icon: Icons.support_agent_rounded,
                    label: AppStrings.settingsShortcutSupport,
                    // TODO: navegar para tela de Suporte quando existir
                    onTap: () => _comingSoon(context),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // Placeholder até as telas de Privacidade/Suporte existirem.
  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.settingsComingSoon),
        duration: Duration(seconds: 2),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
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

// Notificação diária de clima: switch + (quando ativo) seletor de horário.
// Self-contained: lê/grava SharedPreferences e chama o canal nativo direto —
// o WeatherNotificationReceiver dispara sem depender do Flutter Engine.
class _WeatherNotifTile extends StatefulWidget {
  const _WeatherNotifTile();

  @override
  State<_WeatherNotifTile> createState() => _WeatherNotifTileState();
}

class _WeatherNotifTileState extends State<_WeatherNotifTile> {
  bool _enabled = false;
  int _hour = 8;
  int _minute = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.getBool('weather_notification_enabled') ?? false;
      _hour = prefs.getInt('weather_notification_hour') ?? 8;
      _minute = prefs.getInt('weather_notification_minute') ?? 0;
    });
  }

  Future<void> _onToggle(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_notification_enabled', v);
    if (mounted) setState(() => _enabled = v);
    try {
      if (v) {
        await _remindersChannel.invokeMethod('scheduleWeatherNotification',
            {'hour': _hour, 'minute': _minute});
      } else {
        await _remindersChannel.invokeMethod('cancelWeatherNotification');
      }
    } catch (_) {/* canal indisponível — prefs já persistidas */}
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('weather_notification_hour', picked.hour);
    await prefs.setInt('weather_notification_minute', picked.minute);
    if (mounted) {
      setState(() {
        _hour = picked.hour;
        _minute = picked.minute;
      });
    }
    // Reagenda no novo horário se estiver ativo.
    if (_enabled) {
      try {
        await _remindersChannel.invokeMethod('scheduleWeatherNotification',
            {'hour': _hour, 'minute': _minute});
      } catch (_) {}
    }
  }

  String get _timeLabel =>
      '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SwitchTile(
          icon: Icons.wb_sunny_outlined,
          title: AppStrings.settingsWeatherNotif,
          subtitle: AppStrings.settingsWeatherNotifDesc,
          value: _enabled,
          onChanged: _onToggle,
        ),
        if (_enabled)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.backgroundElevated,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(Icons.schedule, color: AppTheme.accent, size: 20),
            ),
            title: Text(
              AppStrings.settingsWeatherNotifTime,
              style: AppTypography.titleSmall.copyWith(color: AppTheme.textPrimary),
            ),
            trailing: TextButton(
              onPressed: _pickTime,
              child: Text(
                _timeLabel,
                style: AppTypography.titleSmall.copyWith(color: AppTheme.accent),
              ),
            ),
          ),
      ],
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
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

// Card de vidro que agrupa os itens de uma seção (delega ao primitivo central).
class _SectionCard extends StatelessWidget {
  final List<Widget> children;

  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return SoproCard(
      glass: true,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(children: children),
    );
  }
}

// Divisória fina e discreta ENTRE itens de um mesmo card.
class _ItemDivider extends StatelessWidget {
  const _ItemDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      color: AppTheme.borderColor,
      height: 1,
      thickness: 1,
      indent: AppSpacing.md,
      endIndent: AppSpacing.md,
    );
  }
}

// Bloco quadrado de atalho (Privacidade / Suporte): ícone + label centralizados.
class _ShortcutBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShortcutBlock({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: SoproCard(
        glass: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // SizedBox.expand: preenche o quadrado (o GlassSurface entrega o
          // conteúdo com constraints frouxas, então sem isso o Column encolhe
          // e gruda no canto superior esquerdo). Com altura/largura cheias, o
          // mainAxis/crossAxis center realmente centraliza ícone + label.
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: AppTheme.accent, size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  style: AppTypography.titleSmall
                      .copyWith(color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
        ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
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

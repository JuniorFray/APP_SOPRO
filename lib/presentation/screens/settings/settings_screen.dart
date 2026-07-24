import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
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

// ── Métricas visuais compartilhadas (densidade iOS Settings) ────────────────
const double _leadingSize = 36;          // lado do tile de ícone neutro
const double _rowPadH     = AppSpacing.sm; // padding horizontal das linhas
const double _rowPadV     = AppSpacing.sm; // padding vertical das linhas (~12px)
// Divisor começa alinhado ao título (após o tile de ícone + gap).
const double _dividerIndent = _rowPadH + _leadingSize + AppSpacing.sm;

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
                icon: LucideIcons.bluetooth,
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
                icon: LucideIcons.bell,
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
                icon: LucideIcons.volume2,
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
                icon: LucideIcons.mic,
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
                icon: LucideIcons.messageSquare,
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
                    icon: LucideIcons.shield,
                    label: AppStrings.settingsShortcutPrivacy,
                    // TODO: navegar para tela de Privacidade quando existir
                    onTap: () => _comingSoon(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _ShortcutBlock(
                    icon: LucideIcons.lifeBuoy,
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

// ─── Componentes base (linguagem iOS Settings) ─────────────────────────────────

// Cabeçalho de seção — cinza ~60%, UPPERCASE 12px tracking 1.2 (igual à Home).
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.titleGap),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textDisabled,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// Tile neutro atrás do ícone: fundo branco ~6% + tinta única (nunca coral).
class _LeadingIcon extends StatelessWidget {
  final IconData icon;
  const _LeadingIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _leadingSize,
      height: _leadingSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.iconTileBg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Icon(icon, color: AppColors.iconTileTint, size: 18),
    );
  }
}

// Estilo unificado dos subtítulos: 12.5px, cinza ~50%, altura consistente.
const TextStyle _subtitleStyle = TextStyle(
  color: AppColors.textDisabled,
  fontSize: 12.5,
  height: 1.35,
);

// Linha genérica de configuração: ícone neutro + título/subtítulo + trailing.
// Compacta (padding vertical ~12px, gap título→descrição de 2px).
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: _rowPadH, vertical: _rowPadV),
      child: Row(
        children: [
          _LeadingIcon(icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.titleSmall
                      .copyWith(color: AppColors.textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: _subtitleStyle),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

// Switch com contraste ON/OFF explícito: ligado coral, desligado neutro
// (trilho cinza-escuro + thumb cinza), sem outline residual.
class _SettingSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.textPrimary,
      activeTrackColor: AppColors.accent,
      inactiveThumbColor: AppColors.textDisabled,
      inactiveTrackColor: AppColors.backgroundElevated,
      trackOutlineColor:
          const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

// Dropdown padronizado: valor cinza-claro (~70%) + chevron discreto.
class _SettingDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  const _SettingDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      items: items,
      onChanged: (v) => onChanged(v as T),
      dropdownColor: AppTheme.backgroundElevated,
      underline: const SizedBox.shrink(),
      isDense: true,
      borderRadius: BorderRadius.circular(AppRadius.card),
      // Chevron cinza no lugar da seta padrão do Material.
      icon: const Padding(
        padding: EdgeInsets.only(left: 2),
        child: Icon(LucideIcons.chevronDown,
            size: 16, color: AppColors.textDisabled),
      ),
      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
    );
  }
}

// Valor clicável (ex.: horário) — cinza-claro + chevronRight discreto.
class _ValueChevron extends StatelessWidget {
  final String label;
  const _ValueChevron(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style:
              AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(width: 2),
        const Icon(LucideIcons.chevronRight,
            size: 16, color: AppColors.textDisabled),
      ],
    );
  }
}

// ─── Tiles concretos ───────────────────────────────────────────────────────────

// Linha de configuração com Switch.
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
    return _SettingRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: _SettingSwitch(value: value, onChanged: onChanged),
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
          icon: LucideIcons.sun,
          title: AppStrings.settingsWeatherNotif,
          subtitle: AppStrings.settingsWeatherNotifDesc,
          value: _enabled,
          onChanged: _onToggle,
        ),
        // Horário desaparece quando a previsão diária está desligada.
        if (_enabled) ...[
          const _ItemDivider(),
          _SettingRow(
            icon: LucideIcons.clock,
            title: AppStrings.settingsWeatherNotifTime,
            onTap: _pickTime,
            trailing: _ValueChevron(_timeLabel),
          ),
        ],
      ],
    );
  }
}

// Seletor de potência de transmissão BLE (alcance de detecção).
// 0=ULTRA_LOW (~2m), 1=LOW (~5m), 2=MEDIUM (~10m), 3=HIGH (~20m+)
class _BlePowerTile extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _BlePowerTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: LucideIcons.radar,
      title: AppStrings.settingsBleTxPower,
      subtitle: AppStrings.settingsBleTxPowerDesc,
      trailing: _SettingDropdown<int>(
        value: value,
        onChanged: onChanged,
        items: const [
          DropdownMenuItem(value: 0, child: Text(AppStrings.bleTxPowerMin)),
          DropdownMenuItem(value: 1, child: Text(AppStrings.bleTxPowerLow)),
          DropdownMenuItem(value: 2, child: Text(AppStrings.bleTxPowerMed)),
          DropdownMenuItem(value: 3, child: Text(AppStrings.bleTxPowerHigh)),
        ],
      ),
    );
  }
}

// Seletor de frequência mínima entre notificações.
class _CooldownTile extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _CooldownTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: LucideIcons.timer,
      title: AppStrings.settingsNotifCooldown,
      subtitle: AppStrings.settingsNotifCooldownDesc,
      trailing: _SettingDropdown<int>(
        value: value,
        onChanged: onChanged,
        items: const [
          DropdownMenuItem(value: 0,  child: Text('Sempre')),
          DropdownMenuItem(value: 5,  child: Text('5 min')),
          DropdownMenuItem(value: 15, child: Text('15 min')),
          DropdownMenuItem(value: 30, child: Text('30 min')),
          DropdownMenuItem(value: 60, child: Text('1 hora')),
        ],
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
    return _SettingRow(
      icon: LucideIcons.gauge,
      title: AppStrings.voiceSpeechRate,
      trailing: _SettingDropdown<double>(
        value: value,
        onChanged: onChanged,
        items: const [
          DropdownMenuItem(value: 0.3, child: Text(AppStrings.voiceRateSlow)),
          DropdownMenuItem(value: 0.5, child: Text(AppStrings.voiceRateNormal)),
          DropdownMenuItem(value: 0.7, child: Text(AppStrings.voiceRateFast)),
        ],
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

// Divisória fina entre itens: branco 8%, alinhada ao título (indent à esquerda,
// sem indent à direita).
class _ItemDivider extends StatelessWidget {
  const _ItemDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      color: AppColors.border,
      height: 1,
      thickness: 1,
      indent: _dividerIndent,
      endIndent: 0,
    );
  }
}

// Bloco quadrado de atalho (Privacidade / Suporte): ícone neutro + label.
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
                Icon(icon, color: AppColors.iconTileTint, size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  style: AppTypography.titleSmall
                      .copyWith(color: AppColors.textPrimary),
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
    return _SettingRow(
      icon: LucideIcons.messageCircle,
      title: AppStrings.settingsOverlayEnabled,
      subtitle: AppStrings.settingsOverlayEnabledDesc,
      trailing: _SettingSwitch(value: value, onChanged: (v) => onChanged(v)),
    );
  }
}

import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/strings.dart';
import '../../infrastructure/logging/core/logger.dart';
import '../../infrastructure/reminders/reminder_scheduler.dart';
import '../providers/ble_providers.dart';
import '../providers/database_provider.dart';
import '../providers/location_providers.dart';

// Único ponto de verificação de requisitos do dispositivo.
//
// Executado no início de cada sessão (após onboarding confirmado), antes de
// iniciar geofences ou qualquer funcionalidade que dependa de hardware.
//
// Sequência obrigatória — um requisito por vez, nunca em paralelo:
//   1. Permissão ACCESS_FINE_LOCATION
//   2. GPS habilitado (isLocationEnabled)
//   3. Permissões Bluetooth (BLE_SCAN, BLE_CONNECT, BLE_ADVERTISE)
//   4. Bluetooth habilitado (isBluetoothEnabled)
//   5. Overlay (somente se floating_voice_enabled == true)
//
// Cada falha exibe AlertDialog com Cancelar / Abrir Configurações.
// O usuário pode cancelar — o guard não é bloqueante.
class DeviceRequirementsGuard {
  DeviceRequirementsGuard._();

  static const _overlayChannel = MethodChannel('com.sopro.sopro/overlay');

  static Future<void> check(BuildContext context, WidgetRef ref) async {
    Logger.info('device_requirements_started',
        feature: 'device_guard', action: 'check');

    final locService = ref.read(nativeLocationServiceProvider);
    final bleService = ref.read(bleServiceProvider);

    // ── 1. Permissão de localização ────────────────────────────────────────
    bool hasLocation = await locService.checkPermission();
    if (!hasLocation) hasLocation = await locService.requestPermission();
    if (!hasLocation && context.mounted) {
      await _showDialog(
        context,
        title: AppStrings.reqPermLocationTitle,
        body: AppStrings.reqPermLocationBody,
        onOpenSettings: locService.openAppSettings,
      );
    }

    // ── 2. GPS habilitado ──────────────────────────────────────────────────
    bool gpsOk = false;
    if (context.mounted) {
      gpsOk = await locService.isLocationEnabled();
      if (!gpsOk && context.mounted) {
        Logger.debug('gps_disabled', feature: 'device_guard', action: 'check');
        await _showDialog(
          context,
          title: AppStrings.gpsDisabledTitle,
          body: AppStrings.gpsDisabledBody,
          onOpenSettings: locService.openLocationSettings,
        );
      } else {
        Logger.debug('gps_enabled', feature: 'device_guard', action: 'check');
      }
    }

    // ── 3. Permissões Bluetooth ────────────────────────────────────────────
    bool hasBle = false;
    if (context.mounted) {
      hasBle = await bleService.checkPermissions();
      if (!hasBle) hasBle = await bleService.requestPermissions();
      if (!hasBle && context.mounted) {
        await _showDialog(
          context,
          title: AppStrings.reqPermBleTitle,
          body: AppStrings.reqPermBleBody,
          onOpenSettings: locService.openAppSettings,
        );
      }
    }

    // ── 4. Bluetooth habilitado ────────────────────────────────────────────
    // Mesmo padrão do autostart: só avisa se desligado E ainda não avisamos
    // antes. Concedido = resolvido (o check de estado já barra o diálogo).
    // Se cancelar o diálogo, marca a flag e não repete a cada cold start.
    bool btOk = false;
    if (context.mounted) {
      btOk = await bleService.isBluetoothEnabled();
      final prefs = await SharedPreferences.getInstance();
      var btWarned = prefs.getBool('bluetooth_warning_shown') ?? false;
      // Desligado agora mas já avisado antes: no caminho ficou concedido e
      // voltou a desligar. Reseta a flag para o aviso reaparecer.
      if (!btOk && btWarned) {
        await prefs.setBool('bluetooth_warning_shown', false);
        btWarned = false;
      }
      if (!btOk && !btWarned && context.mounted) {
        Logger.debug('bluetooth_disabled', feature: 'device_guard', action: 'check');
        final opened = await _showDialog(
          context,
          title: AppStrings.btDisabledTitle,
          body: AppStrings.btDisabledBody,
          onOpenSettings: bleService.openBluetoothSettings,
        );
        // Cancelou (não foi às configurações): não incomodar de novo.
        if (!opened) await prefs.setBool('bluetooth_warning_shown', true);
      } else if (btOk) {
        Logger.debug('bluetooth_enabled', feature: 'device_guard', action: 'check');
      }
    }

    // ── 5. Overlay (somente se botão flutuante habilitado) ─────────────────
    bool overlayOk = true;
    if (context.mounted) {
      final prefs = await SharedPreferences.getInstance();
      final floatingEnabled = prefs.getBool('floating_voice_enabled') ?? false;
      if (floatingEnabled) {
        overlayOk =
            await _overlayChannel.invokeMethod<bool>('hasOverlayPermission') ??
                false;
        if (!overlayOk && context.mounted) {
          Logger.debug('overlay_disabled',
              feature: 'device_guard', action: 'check');
          await _showDialog(
            context,
            title: AppStrings.reqOverlayTitle,
            body: AppStrings.reqOverlayBody,
            onOpenSettings: _openOverlaySettings,
          );
        } else if (overlayOk) {
          Logger.debug('overlay_enabled',
              feature: 'device_guard', action: 'check');
        }
      }
    }

    // ── 6. Alarme exato (Android 12+) — só se houver lembrete ativo ─────────
    // Não incomoda quem não usa a feature: só verifica se existe ≥1 lembrete
    // ativo no banco.
    bool exactAlarmOk = true;
    if (context.mounted) {
      final activeReminders = await ref
          .read(scheduledReminderRepositoryProvider)
          .watchAllActive()
          .first;
      if (activeReminders.isNotEmpty) {
        final scheduler = ReminderScheduler();
        exactAlarmOk = await scheduler.hasExactAlarmPermission();
        if (!exactAlarmOk && context.mounted) {
          Logger.debug('exact_alarm_disabled',
              feature: 'device_guard', action: 'check');
          await _showDialog(
            context,
            title: AppStrings.reqExactAlarmTitle,
            body: AppStrings.reqExactAlarmBody,
            onOpenSettings: scheduler.openExactAlarmSettings,
          );
        } else if (exactAlarmOk) {
          Logger.debug('exact_alarm_enabled',
              feature: 'device_guard', action: 'check');
        }
      }
    }

    // ── 7. Tela cheia (Android 14+) — sempre ───────────────────────────────
    // A permissão USE_FULL_SCREEN_INTENT precisa ser concedida em runtime no
    // Android 14+; sem ela o alarme não abre sozinho sobre a tela bloqueada.
    // Roda no fluxo padrão como os demais itens (não depende de já existir
    // lembrete configurado). No-op (sempre concedida) em Android < 14.
    bool fsIntentOk = true;
    if (context.mounted) {
      final scheduler = ReminderScheduler();
      fsIntentOk = await scheduler.hasFullScreenIntentPermission();
      final prefs = await SharedPreferences.getInstance();
      var fsWarned = prefs.getBool('fullscreen_warning_shown') ?? false;
      // Desligado agora mas já avisado antes: ficou concedido e voltou a
      // desligar. Reseta a flag para o aviso reaparecer.
      if (!fsIntentOk && fsWarned) {
        await prefs.setBool('fullscreen_warning_shown', false);
        fsWarned = false;
      }
      // Exceção ao "avisar só uma vez": o botão flutuante depende da tela-cheia
      // para o alarme abrir sobre a tela bloqueada. Se ele está ligado, reavisa
      // sempre que faltar a permissão — é o recurso que precisa dela agora.
      final floatingEnabled = prefs.getBool('floating_voice_enabled') ?? false;
      if (!fsIntentOk && (!fsWarned || floatingEnabled) && context.mounted) {
        Logger.debug('fullscreen_intent_disabled',
            feature: 'device_guard', action: 'check');
        final opened = await _showDialog(
          context,
          title: AppStrings.reqFullScreenIntentTitle,
          body: AppStrings.reqFullScreenIntentBody,
          onOpenSettings: scheduler.openFullScreenIntentSettings,
        );
        // Cancelou sem o botão flutuante ligado: não repetir no app_start geral.
        if (!opened) await prefs.setBool('fullscreen_warning_shown', true);
      } else if (fsIntentOk) {
        Logger.debug('fullscreen_intent_enabled',
            feature: 'device_guard', action: 'check');
      }
    }

    // ── 8. Autostart / bateria do fabricante — HEURÍSTICO (melhor esforço) ──
    // Xiaomi "Autostart", Samsung "Apps em hibernação", etc. NÃO têm API
    // oficial: não dá pra checar se está concedido, só abrir a tela e pedir
    // pro usuário verificar manualmente. Por isso este passo:
    //   - só mostra um AVISO (nunca marca como "concedido" — não há como);
    //   - persiste 'autostart_warning_shown' pra não repetir a cada abertura;
    //   - é 100% pulável, nunca bloqueia o app.
    // Cobertura depende do pacote auto_start_flutter (nem todo fabricante é
    // reconhecido) — em Android stock/Pixel isAutoStartAvailable é false e o
    // passo é pulado em silêncio.
    if (context.mounted) {
      final prefs = await SharedPreferences.getInstance();
      final alreadyWarned = prefs.getBool('autostart_warning_shown') ?? false;
      final available = (await isAutoStartAvailable) ?? false;
      if (available && !alreadyWarned) {
        final manufacturer =
            (await getDeviceManufacturer())?.toLowerCase() ?? '';
        final isSamsung = manufacturer.contains('samsung');
        final body = AppStrings.reqAutoStartBody +
            (isSamsung ? AppStrings.reqAutoStartBodySamsung : '');
        Logger.debug('autostart_warning_shown',
            feature: 'device_guard', action: 'check',
            payload: {'manufacturer': manufacturer});
        if (context.mounted) {
          final check = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text(AppStrings.reqAutoStartTitle),
              content: Text(body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(AppStrings.reqAutoStartSkip),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(AppStrings.reqAutoStartCheck),
                ),
              ],
            ),
          );
          // Marca como avisado só depois de exibir — NÃO significa "concedido".
          await prefs.setBool('autostart_warning_shown', true);
          if (check == true) await getAutoStartPermission();
        }
      }
    }

    // ── Log resultado ──────────────────────────────────────────────────────
    final allOk = hasLocation && gpsOk && hasBle && btOk && overlayOk;
    final event =
        allOk ? 'device_requirements_completed' : 'device_requirements_failed';
    final logFn = allOk ? Logger.info : Logger.warn;
    logFn(
      event,
      feature: 'device_guard',
      action: 'check',
      payload: {
        'gps': gpsOk.toString(),
        'bluetooth': btOk.toString(),
        'overlay': overlayOk.toString(),
        'exact_alarm': exactAlarmOk.toString(),
        'fullscreen_intent': fsIntentOk.toString(),
        'location_permission': hasLocation.toString(),
        'ble_permission': hasBle.toString(),
      },
    );
  }

  // Exibe diálogo de requisito. Abre configurações se usuário aceitar.
  // Retorna true se o usuário foi abrir as configurações; false se cancelou —
  // o chamador usa isso para marcar a flag "já avisado" só quando cancelam.
  static Future<bool> _showDialog(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onOpenSettings,
  }) async {
    if (!context.mounted) return false;
    final openSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.reqDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.reqDialogOpenSettings),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await onOpenSettings();
      return true;
    }
    return false;
  }

  static Future<void> _openOverlaySettings() async {
    await _overlayChannel.invokeMethod<void>('openOverlayPermissionSettings');
  }
}

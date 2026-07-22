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
    bool btOk = false;
    if (context.mounted) {
      btOk = await bleService.isBluetoothEnabled();
      if (!btOk && context.mounted) {
        Logger.debug('bluetooth_disabled', feature: 'device_guard', action: 'check');
        await _showDialog(
          context,
          title: AppStrings.btDisabledTitle,
          body: AppStrings.btDisabledBody,
          onOpenSettings: bleService.openBluetoothSettings,
        );
      } else {
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
        'location_permission': hasLocation.toString(),
        'ble_permission': hasBle.toString(),
      },
    );
  }

  // Exibe diálogo de requisito. Abre configurações se usuário aceitar.
  static Future<void> _showDialog(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onOpenSettings,
  }) async {
    if (!context.mounted) return;
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
    if (openSettings == true) await onOpenSettings();
  }

  static Future<void> _openOverlaySettings() async {
    await _overlayChannel.invokeMethod<void>('openOverlayPermissionSettings');
  }
}

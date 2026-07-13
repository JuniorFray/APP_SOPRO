import 'package:flutter/material.dart';

import '../../core/constants/strings.dart';
import 'native_location_service.dart';

// Ponto central de validação GPS antes de qualquer chamada de localização.
//
// Sequência obrigatória:
//   1. Verifica isLocationEnabled()
//   2. Se desligado → exibe diálogo → abre configurações se usuário aceitar → retorna null
//   3. Se ligado → chama getCurrentPosition()
//
// A verificação de permissão ACCESS_FINE_LOCATION é responsabilidade do chamador
// (feita antes de invocar esta função, como já ocorre nos fluxos existentes).
Future<({double latitude, double longitude, double accuracy})?> getLocationWithGpsCheck(
  BuildContext context,
  NativeLocationService service,
) async {
  final enabled = await service.isLocationEnabled();
  if (!enabled) {
    if (context.mounted) {
      final openSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text(AppStrings.gpsDisabledTitle),
          content: const Text(AppStrings.gpsDisabledBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(AppStrings.gpsDisabledCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(AppStrings.gpsDisabledOpenSettings),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        await service.openLocationSettings();
      }
    }
    return null;
  }
  return service.getCurrentPosition();
}

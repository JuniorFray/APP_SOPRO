import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/repositories/i_environment_repository.dart';
import '../../domain/usecases/fire_triggers_use_case.dart';
import '../location/native_location_service.dart';

// Monitora a posição do usuário e dispara triggers quando ele entra num ambiente.
//
// Lógica ENTER/EXIT:
// - _insideEnvironments rastreia quais ambientes o usuário já está dentro.
// - A cada posição recebida, a distância até cada ambiente é calculada com
//   latlong2.Distance (haversine) e comparada com o raio do ambiente.
// - ENTER: distância <= raio && não estava dentro → dispara FireTriggersUseCase + adiciona ao Set
// - EXIT:  distância >  raio && estava dentro  → remove do Set (sem notificação por enquanto)
//
// GPS via MethodChannel nativo (MainActivity.kt / FusedLocationProviderClient).
// Não depende de nenhum pacote pub.dev de localização.
class GeofenceManager {
  final IEnvironmentRepository _envRepo;
  final FireTriggersUseCase _fireTriggers;
  final NativeLocationService _locationService;

  StreamSubscription<({double latitude, double longitude})>? _sub;

  // IDs dos ambientes que o usuário está dentro no momento atual
  final _inside = <String>{};

  // Reutilizado a cada cálculo para evitar instâncias desnecessárias
  static const _dist = Distance();

  bool _running = false;

  GeofenceManager(this._envRepo, this._fireTriggers, this._locationService);

  /// Verifica/solicita permissão e assina o stream de posição.
  Future<void> start() async {
    bool ok = await _locationService.checkPermission();
    if (!ok) ok = await _locationService.requestPermission();

    if (!ok) {
      debugPrint('[GeofenceManager] Permissão de localização não concedida — monitoramento não iniciado.');
      return;
    }

    _sub = _locationService.getPositionStream().listen(
      _onPosition,
      onError: (Object e) => debugPrint('[GeofenceManager] Erro no stream: $e'),
    );

    _running = true;
    debugPrint('[GeofenceManager] Monitoramento de geofences iniciado.');
  }

  /// Para o monitoramento e limpa o estado interno.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _inside.clear();
    _running = false;
    debugPrint('[GeofenceManager] Monitoramento parado.');
  }

  bool get isRunning => _running;

  // Callback do EventChannel — avaliado para cada posição recebida.
  Future<void> _onPosition(({double latitude, double longitude}) pos) async {
    final envs = await _envRepo.getAll();
    final current = LatLng(pos.latitude, pos.longitude);

    for (final env in envs) {
      final meters = _dist.as(
        LengthUnit.Meter,
        current,
        LatLng(env.latitude, env.longitude),
      );

      final wasInside = _inside.contains(env.id);
      final isNowInside = meters <= env.radiusMeters;

      if (isNowInside && !wasInside) {
        _inside.add(env.id);
        // Passa environmentId e nome do ambiente para o use case buscar os triggers ativos
        await _fireTriggers(env.id, env.name);
      } else if (!isNowInside && wasInside) {
        _inside.remove(env.id);
      }
    }
  }
}

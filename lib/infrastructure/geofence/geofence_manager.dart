import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/repositories/i_environment_repository.dart';
import '../../domain/usecases/fire_triggers_use_case.dart';

// Implementação de geofencing usando geolocator com lógica manual de distância.
//
// Por que não geofence_service: o pacote foi descontinuado (v6 removida do pub.dev).
// O substituto recomendado (geofencing_api) será adotado no Sprint 5 junto com
// flutter_background_service para suporte a background real.
//
// Sprint 3 foca em foreground: o stream de posição roda enquanto o app está aberto.
class GeofenceManager {
  final IEnvironmentRepository _envRepo;
  final FireTriggersUseCase _fireTriggers;

  StreamSubscription<Position>? _positionSub;

  // Conjunto de IDs de environments em que o usuário está atualmente dentro.
  // Evita disparar o evento ENTER repetidamente enquanto permanece no local.
  final _insideEnvironments = <String>{};

  GeofenceManager(this._envRepo, this._fireTriggers);

  // Verifica e solicita permissões de localização, depois inicia o stream de posição.
  Future<void> start() async {
    final permission = await _ensurePermission();
    if (!permission) {
      debugPrint('[GeofenceManager] Permissão de localização negada.');
      return;
    }

    // distanceFilter: só notifica quando o dispositivo mover pelo menos 10m,
    // reduzindo chamadas ao banco sem sacrificar precisão para raios >= 50m
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: _onError);
  }

  // Para o stream e limpa o estado interno.
  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _insideEnvironments.clear();
  }

  // Retorna true se o stream de posição está ativo.
  bool get isRunning => _positionSub != null;

  // Chamado a cada nova posição do GPS.
  // Compara a distância com cada ambiente e dispara ENTER/EXIT conforme necessário.
  Future<void> _onPosition(Position position) async {
    final environments = await _envRepo.getAll();

    for (final env in environments) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        env.latitude,
        env.longitude,
      );

      final wasInside = _insideEnvironments.contains(env.id);
      final isNowInside = distance <= env.radiusMeters;

      if (isNowInside && !wasInside) {
        // Evento ENTER: usuário acabou de entrar no raio do ambiente
        _insideEnvironments.add(env.id);
        await _fireTriggers(env.id, env.name);
      } else if (!isNowInside && wasInside) {
        // Evento EXIT: usuário saiu do raio
        _insideEnvironments.remove(env.id);
      }
    }
  }

  void _onError(Object error) {
    debugPrint('[GeofenceManager] Erro no stream de posição: $error');
  }

  // Verifica se temos permissão; solicita se necessário.
  // Retorna false se negada permanentemente ou o usuário recusar.
  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}

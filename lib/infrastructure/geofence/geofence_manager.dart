import 'package:flutter/foundation.dart';
// latlong2 já está no pubspec (Sprint 4). Sprint 5 usa:
// import 'package:latlong2/latlong.dart';
// const _dist = Distance();
// final m = _dist.as(LengthUnit.Meter, LatLng(posLat, posLng), LatLng(env.latitude, env.longitude));

import '../../domain/repositories/i_environment_repository.dart';
import '../../domain/usecases/fire_triggers_use_case.dart';

// STUB — GPS desativado temporariamente.
//
// Motivo: geolocator ^13.x é incompatível com Android SDK 36 e
// geolocator ^14.x requer Dart SDK >=3.10.0 (versão atual: 3.5.4).
//
// Plano: Sprint 5 integra flutter_background_service + upgrade do Flutter/Dart SDK,
// momento em que este stub será substituído pela implementação real com
// Geolocator.getPositionStream() e lógica ENTER/EXIT por distanceBetween.
//
// A interface pública (start, stop, isRunning) já está no formato final
// para que a troca seja feita sem alterar providers ou callers.
class GeofenceManager {
  // Dependências mantidas para não quebrar os providers e facilitar a troca
  // ignore: unused_field
  final IEnvironmentRepository _envRepo;
  // ignore: unused_field
  final FireTriggersUseCase _fireTriggers;

  bool _running = false;

  GeofenceManager(this._envRepo, this._fireTriggers);

  Future<void> start() async {
    // GPS desativado neste sprint — não faz nada
    debugPrint('[GeofenceManager] GPS stub: monitoramento não iniciado (Sprint 5).');
    _running = false;
  }

  Future<void> stop() async {
    _running = false;
  }

  bool get isRunning => _running;
}

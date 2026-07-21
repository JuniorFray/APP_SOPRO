import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/i_environment_repository.dart';
import '../../domain/usecases/fire_triggers_use_case.dart';
import '../../domain/usecases/show_market_list_use_case.dart';
import '../location/native_location_service.dart';
import '../logging/core/correlation_manager.dart';
import '../logging/core/logger.dart';
import 'native_geofence_service.dart';

// Monitora a posição do usuário e dispara triggers quando ele entra num ambiente.
//
// Opera em dois modos complementares:
//
// 1. GEOFENCING NATIVO (principal, app fechado/morto):
//    Registra todos os ambientes no GeofencingClient do Android via
//    NativeGeofenceService. O sistema Android gerencia as transições
//    e aciona o GeofenceReceiver.kt sem depender do app estar vivo.
//    → Notificação enviada pelo GeofenceReceiver: "Você está em: [nome]"
//
// 2. GPS STREAM (complementar, app em foreground/background):
//    FusedLocationProviderClient via MethodChannel. Dispara triggers com
//    texto específico e loga no Supabase — mais rico que o modo nativo.
//    → Padrão ENTER/EXIT com accuracy bonus de até 100 m.
//
// Os dois modos podem co-existir: o nativo garante cobertura quando o
// foreground service morre (ex: Motorola agressivo); o GPS stream oferece
// triggers completos com textos personalizados quando o app está vivo.
class GeofenceManager {
  final IEnvironmentRepository _envRepo;
  final FireTriggersUseCase _fireTriggers;
  // Entrada em ambiente tipo Mercado dispara a lista de compras em vez dos gatilhos.
  final ShowMarketListUseCase _showMarketList;
  final NativeLocationService _locationService;
  final NativeGeofenceService _nativeGeofence;

  // Subscription ao stream de posições — cancelada em stop()
  StreamSubscription<({double latitude, double longitude, double accuracy})>?
      _sub;

  // IDs dos ambientes que o usuário está dentro no momento atual
  final _inside = <String>{};

  // Reutilizado a cada cálculo para evitar instâncias desnecessárias
  static const _dist = Distance();

  // Throttle da persistência de last_known_lat/lon a partir do stream (RAM só —
  // não precisa sobreviver a restart). Grava quando passou o intervalo mínimo OU
  // a posição andou o suficiente desde a última escrita.
  DateTime? _lastPersistAt;
  LatLng?   _lastPersistPos;
  static const _persistMinInterval       = Duration(seconds: 60);
  static const _persistMinDistanceMeters = 200.0;

  bool _running = false;

  GeofenceManager(
    this._envRepo,
    this._fireTriggers,
    this._showMarketList,
    this._locationService,
    this._nativeGeofence,
  );

  /// Verifica/solicita permissão, registra geofences nativos e assina o GPS stream.
  Future<void> start() async {
    final correlationId = CorrelationManager.beginOperation('geofence');

    bool ok = await _locationService.checkPermission();
    if (!ok) ok = await _locationService.requestPermission();

    if (!ok) {
      Logger.warn(
        'geofence_permission_denied',
        feature: 'geofence',
        action: 'start',
        correlationId: correlationId,
      );
      debugPrint('[GeofenceManager] Permissão de localização não concedida — monitoramento não iniciado.');
      return;
    }

    // ── Geofences nativos ──────────────────────────────────────────────────
    // Solicita permissão de background (Android 10+) para que o GeofenceReceiver
    // seja acionado mesmo com o app morto.
    final hasBg = await _nativeGeofence.hasBackgroundPermission();
    if (!hasBg) await _nativeGeofence.requestBackgroundPermission();

    // Registra cada ambiente no GeofencingClient — idempotente: chamar novamente
    // com o mesmo ID apenas atualiza o geofence existente.
    final envs = await _envRepo.getAll();
    var registeredCount = 0;
    for (final env in envs) {
      final sw = Stopwatch()..start();
      try {
        await _nativeGeofence.addGeofence(
          id:           env.id,
          lat:          env.latitude,
          lng:          env.longitude,
          radiusMeters: env.radiusMeters,
          name:         env.name,
        );
        registeredCount++;
      } catch (e, st) {
        Logger.warn(
          'native_geofence_register_failed',
          payload: {
            'env_id':     env.id,
            'env_name':   env.name,
            'error':      e.toString(),
          },
          exception:     e,
          stackTrace:    st,
          feature:       'geofence',
          action:        'register',
          correlationId: correlationId,
          durationMs:    sw.elapsedMilliseconds,
        );
        debugPrint('[GeofenceManager] Falha ao registrar geofence nativo ${env.id}: $e');
      }
    }

    // Se count < total, alguns ambientes não serão detectados com o app morto.
    Logger.info(
      'native_geofence_registered',
      payload: {
        'count': registeredCount,
        'total': envs.length,
      },
      feature:       'geofence',
      action:        'register',
      correlationId: correlationId,
    );
    debugPrint('[GeofenceManager] $registeredCount/${envs.length} geofence(s) nativo(s) registrado(s).');

    // ── GPS stream (triggers completos quando app está vivo) ───────────────
    _sub = _locationService.getPositionStream().listen(
      _onPosition,
      onError: (Object e, StackTrace st) {
        Logger.error(
          'geofence_stream_error',
          exception:     e,
          stackTrace:    st,
          feature:       'geofence',
          action:        'gps_stream',
          correlationId: CorrelationManager.correlationIdFor('geofence'),
        );
        debugPrint('[GeofenceManager] Erro no stream: $e');
      },
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
    CorrelationManager.endOperation('geofence');
    debugPrint('[GeofenceManager] Monitoramento parado.');
  }

  bool get isRunning => _running;

  // Persiste a última posição do stream nas MESMAS chaves lidas pelo
  // GeocodingService (last_known_lat/lon) — assim a busca de local em qualquer
  // tela herda um fix fresco, não só a tela Novo Ambiente ou o overlay de voz.
  //
  // THROTTLE: o stream emite a cada 2s/10m — granular demais para bias de busca.
  // Só grava quando passou >= _persistMinInterval OU a posição andou
  // >= _persistMinDistanceMeters desde a última escrita. Controle só em RAM.
  Future<void> _persistLastKnown(LatLng pos) async {
    final now  = DateTime.now();
    final last = _lastPersistPos;
    final movedEnough = last == null ||
        _dist.as(LengthUnit.Meter, last, pos) >= _persistMinDistanceMeters;
    final timeEnough = _lastPersistAt == null ||
        now.difference(_lastPersistAt!) >= _persistMinInterval;
    // Nenhum critério atingido → throttled, não grava (mantém o último valor).
    if (!movedEnough && !timeEnough) return;

    // Marca ANTES do await para não enfileirar gravações concorrentes do stream.
    _lastPersistAt  = now;
    _lastPersistPos = pos;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_known_lat', pos.latitude);
      await prefs.setDouble('last_known_lon', pos.longitude);
      Logger.debug(
        'last_known_location_persisted',
        payload: {
          'latitude':  pos.latitude,
          'longitude': pos.longitude,
          // Qual critério liberou a escrita (confere throttle nos logs).
          'trigger':   timeEnough ? 'interval' : 'distance',
        },
        feature: 'geofence',
        action:  'persist_last_known',
      );
    } catch (e, st) {
      Logger.warn(
        'last_known_persist_failed',
        exception:  e,
        stackTrace: st,
        feature:    'geofence',
        action:     'persist_last_known',
      );
    }
  }

  // Callback do EventChannel — avaliado para cada posição recebida do GPS.
  Future<void> _onPosition(
    ({double latitude, double longitude, double accuracy}) pos,
  ) async {
    final envs    = await _envRepo.getAll();
    final current = LatLng(pos.latitude, pos.longitude);

    // Mantém last_known_lat/lon fresco para o viés de busca em QUALQUER tela.
    // unawaited: não bloqueia a avaliação de geofences abaixo (throttle interno).
    unawaited(_persistLastKnown(current));

    // Limita o bônus de accuracy a 100 m para evitar disparos com GPS ruim
    final accuracyBonus = pos.accuracy.clamp(0.0, 100.0);

    for (final env in envs) {
      final meters = _dist.as(
        LengthUnit.Meter,
        current,
        LatLng(env.latitude, env.longitude),
      );

      final wasInside  = _inside.contains(env.id);
      // Considera "dentro" quando a distância está dentro do raio + margem de GPS
      final isNowInside = meters <= env.radiusMeters + accuracyBonus;

      if (isNowInside && !wasInside) {
        _inside.add(env.id);
        Logger.info(
          'geofence_enter',
          payload: {
            'environment_id':   env.id,
            'environment_name': env.name,
            'distance_m':       meters.toStringAsFixed(1),
            'accuracy_m':       pos.accuracy.toStringAsFixed(1),
          },
          feature:       'geofence',
          action:        'enter',
          correlationId: CorrelationManager.correlationIdFor('geofence'),
        );
        // Mercado → lista de compras; ambiente comum → gatilhos ativos.
        if (env.isMarket) {
          await _showMarketList(env.id, env.name);
        } else {
          await _fireTriggers(env.id, env.name);
        }
      } else if (!isNowInside && wasInside) {
        _inside.remove(env.id);
        Logger.info(
          'geofence_exit',
          payload: {
            'environment_id':   env.id,
            'environment_name': env.name,
          },
          feature:       'geofence',
          action:        'exit',
          correlationId: CorrelationManager.correlationIdFor('geofence'),
        );
      }
    }
  }
}

import 'package:flutter/services.dart';

import '../../domain/entities/environment_entity.dart';
import '../logging/app_logger.dart';

// Wrapper Dart para o MethodChannel "com.sopro.sopro/native_geofence".
// Delega o monitoramento de geofences ao GeofencingClient do Android —
// o sistema gerencia as zonas mesmo com o app fechado ou morto.
//
// Quando uma transição ENTER é detectada, o Android aciona o GeofenceReceiver.kt
// que envia a notificação via NotificationManager sem depender do app estar vivo.
class NativeGeofenceService {
  static const _channel = MethodChannel('com.sopro.sopro/native_geofence');

  // Registra um ambiente no GeofencingClient com log no Supabase.
  // Convenience wrapper de [addGeofence] para uso após criar/editar um ambiente.
  // Loga 'native_geofence_added' para confirmar que o geofence foi aceito.
  Future<void> addSingleGeofence(EnvironmentEntity env) async {
    await addGeofence(
      id:           env.id,
      lat:          env.latitude,
      lng:          env.longitude,
      radiusMeters: env.radiusMeters,
      name:         env.name,
    );
    AppLogger.log('native_geofence_added', {
      'env_id':   env.id,
      'env_name': env.name,
    });
  }

  // Registra um geofence circular permanente no GeofencingClient.
  //
  // [id]           — ID único do ambiente (PK do banco); usado como requestId.
  // [lat], [lng]   — centro do círculo.
  // [radiusMeters] — raio em metros.
  // [name]         — nome do ambiente exibido na notificação offline.
  //
  // Chamar novamente com o mesmo [id] atualiza o geofence existente (idempotente).
  Future<void> addGeofence({
    required String id,
    required double lat,
    required double lng,
    required double radiusMeters,
    required String name,
  }) async {
    await _channel.invokeMethod<void>('addGeofence', {
      'id':     id,
      'lat':    lat,
      'lng':    lng,
      'radius': radiusMeters,
      'name':   name,
    });
  }

  // Remove o geofence identificado por [id] do GeofencingClient.
  // Deve ser chamado ao deletar um ambiente para evitar notificações órfãs.
  Future<void> removeGeofence(String id) async {
    await _channel.invokeMethod<void>('removeGeofence', {'id': id});
  }

  // Remove todos os geofences registrados e limpa o mapa de nomes.
  Future<void> clearGeofences() async {
    await _channel.invokeMethod<void>('clearGeofences');
  }

  // Retorna true se ACCESS_BACKGROUND_LOCATION foi concedido.
  // Necessário no Android 10+ para disparos quando o app não está em foreground.
  Future<bool> hasBackgroundPermission() async {
    return await _channel.invokeMethod<bool>(
          'hasBackgroundLocationPermission',
        ) ??
        false;
  }

  // Solicita ACCESS_BACKGROUND_LOCATION ao usuário.
  // No Android 11+, o sistema abre diretamente a tela de Configurações —
  // o usuário deve selecionar "Sempre" manualmente.
  Future<bool> requestBackgroundPermission() async {
    return await _channel.invokeMethod<bool>(
          'requestBackgroundLocationPermission',
        ) ??
        false;
  }
}

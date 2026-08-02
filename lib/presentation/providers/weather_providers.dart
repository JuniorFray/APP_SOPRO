import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/geocoding/geocoding_repository.dart';
import '../../infrastructure/weather/weather_service.dart';
import 'database_provider.dart';

// Serviço de clima — injeta o DAO de cache. Singleton por sessão.
final weatherServiceProvider = Provider<WeatherService>((ref) {
  return WeatherService(ref.watch(databaseProvider).weatherCacheDao);
});

// Clima atual para o card da Home. Usa last_known_lat/lon (mesma fonte do
// bias de geocoding, mantida fresca pelo GeofenceManager). Coords ausentes
// ou 0.0 → null sem chamar a API (card fica no estado "em breve").
final currentWeatherProvider = FutureProvider<WeatherInfo?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final lat = prefs.getDouble('last_known_lat') ?? 0.0;
  final lon = prefs.getDouble('last_known_lon') ?? 0.0;
  if (lat == 0.0 && lon == 0.0) return null;
  final svc = ref.watch(weatherServiceProvider);
  final info = await svc.getCurrentWeather(lat, lon);
  if (info == null) return null;
  // /weather não traz pop — busca a chance de chuva "em breve" do /forecast
  // (cache compartilhado) e injeta no card.
  final pop = await svc.getPopSoon(lat, lon);
  // O OWM rotula a cidade pela ESTAÇÃO mais próxima — às vezes a vizinha (ex.:
  // Vila Caiçara/Praia Grande vinha como "Mongaguá"). Substitui pelo rótulo real
  // "Bairro, Cidade" das coords via reverse (Photon, cacheado — barato).
  var city = info.cityName;
  try {
    final label = await ref.read(geocodingRepositoryProvider).placeLabel(lat, lon);
    if (label.isNotEmpty) city = label;
  } catch (_) {/* mantém o nome do OWM se o reverso falhar */}
  return info.copyWith(popToday: pop, cityName: city);
});

// Previsão dos próximos dias para a tira do card da Home. Mesma fonte de
// coordenadas do clima atual. Lista vazia quando sem coords/sem chave.
final currentForecastProvider =
    FutureProvider<List<ForecastDay>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final lat = prefs.getDouble('last_known_lat') ?? 0.0;
  final lon = prefs.getDouble('last_known_lon') ?? 0.0;
  if (lat == 0.0 && lon == 0.0) return const [];
  return ref.watch(weatherServiceProvider).getForecast(lat, lon);
});

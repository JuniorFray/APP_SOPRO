import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  return ref.watch(weatherServiceProvider).getCurrentWeather(lat, lon);
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

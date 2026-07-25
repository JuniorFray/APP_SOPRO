import '../weather/weather_service.dart' show WeatherInfo, ForecastDay;

// IWeatherProvider — contrato comum de clima (Tool Provider, spec
// voice_structure_doc/architecture/08-Tool-Providers.md).
//
// Abstrai clima atual / previsão / chance de chuva para desacoplar Skills e
// Planner do provedor concreto (hoje OpenWeatherMap via WeatherService).
// Camada fina: WeatherService já implementa estes métodos — só declara
// `implements`, sem tocar na lógica HTTP/cache.
abstract class IWeatherProvider {
  // Clima atual no ponto (com cache TTL 3h). null quando indisponível.
  Future<WeatherInfo?> getCurrentWeather(double lat, double lon);

  // Previsão dos próximos dias (até 5, exclui hoje).
  Future<List<ForecastDay>> getForecast(double lat, double lon);

  // Chance de chuva "em breve" (0-100) reaproveitando o cache do forecast.
  Future<int?> getPopSoon(double lat, double lon);
}

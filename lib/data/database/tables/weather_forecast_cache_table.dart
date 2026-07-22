import 'package:drift/drift.dart';

// Cache da previsão de vários dias (endpoint /forecast do OWM). Guarda a lista
// de dias já processada como JSON num único registro por coordenada arredondada.
// Mesmo TTL do clima atual (3h). Evita nova chamada /forecast a cada Home.
class WeatherForecastCache extends Table {
  TextColumn get id => text()();          // chave: "lat_arred:lon_arred"
  TextColumn get forecastJson => text()(); // List<ForecastDay> serializada
  IntColumn get fetchedAt => integer()();  // timestamp Unix ms
  IntColumn get expiresAt => integer()();  // timestamp Unix ms — fetchedAt + 3h

  @override
  Set<Column> get primaryKey => {id};
}

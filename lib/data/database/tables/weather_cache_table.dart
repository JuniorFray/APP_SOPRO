import 'package:drift/drift.dart';

// Cache de previsão do tempo por coordenada arredondada (evita nova
// chamada a cada abertura da Home). TTL de pelo menos 2h (folga: 3h).
class WeatherCacheEntries extends Table {
  TextColumn get id => text()(); // chave: "lat_arred:lon_arred", ex "-22.75:-47.64"
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get tempCelsius => real()();
  TextColumn get condition => text()();      // ex.: "Clear", "Rain" (campo main do OWM)
  TextColumn get description => text()();    // ex.: "céu limpo" (description, lang=pt_br)
  TextColumn get iconCode => text()();        // ex.: "01d" (código de ícone do OWM)
  IntColumn get humidity => integer().withDefault(const Constant(0))(); // % (main.humidity)
  TextColumn get cityName => text().withDefault(const Constant(''))(); // "name" do OWM
  IntColumn get fetchedAt => integer()();     // timestamp Unix ms
  IntColumn get expiresAt => integer()();     // timestamp Unix ms — fetchedAt + 3h

  @override
  Set<Column> get primaryKey => {id};
}

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../../core/constants/app_constants.dart';
import '../../data/database/daos/weather_cache_dao.dart';
import '../../data/database/sopro_database.dart';

// Resultado de clima ATUAL exposto à apresentação (sem acoplamento a Drift).
class WeatherInfo {
  final double tempCelsius;
  final String condition;   // campo "main" do OWM (ex.: "Clear", "Rain")
  final String description; // "description" pt_br (ex.: "céu limpo")
  final String iconCode;    // código de ícone do OWM (ex.: "01d")
  final int humidity;       // umidade relativa em % (main.humidity)
  final String cityName;    // "name" do OWM (ex.: "Piracicaba")
  WeatherInfo({
    required this.tempCelsius,
    required this.condition,
    required this.description,
    required this.iconCode,
    required this.humidity,
    required this.cityName,
  });
}

// Um dia da previsão (endpoint /forecast agrupado por dia).
class ForecastDay {
  final DateTime date;   // meia-noite local do dia
  final double tempMin;
  final double tempMax;
  final String condition;
  final String iconCode; // ícone do horário mais próximo do meio-dia

  ForecastDay({
    required this.date,
    required this.tempMin,
    required this.tempMax,
    required this.condition,
    required this.iconCode,
  });

  Map<String, dynamic> toJson() => {
        'date': date.millisecondsSinceEpoch,
        'min': tempMin,
        'max': tempMax,
        'cond': condition,
        'icon': iconCode,
      };

  factory ForecastDay.fromJson(Map<String, dynamic> j) => ForecastDay(
        date: DateTime.fromMillisecondsSinceEpoch(j['date'] as int),
        tempMin: (j['min'] as num).toDouble(),
        tempMax: (j['max'] as num).toDouble(),
        condition: j['cond'] as String,
        iconCode: j['icon'] as String,
      );
}

// Busca e cacheia clima atual + previsão de dias via OpenWeatherMap.
// Chamada HTTP pura (sem código nativo) — mesmo serviço serve Android e iOS.
class WeatherService {
  final WeatherCacheDao _cacheDao;
  WeatherService(this._cacheDao);

  // Chave de cache: coordenada arredondada para 2 casas decimais
  // (~1.1km de precisão — suficiente para clima, maximiza cache hit).
  String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)}:${lon.toStringAsFixed(2)}';

  Future<WeatherInfo?> getCurrentWeather(double lat, double lon) async {
    final key = _cacheKey(lat, lon);
    final cached = await _cacheDao.findValid(key);
    if (cached != null) {
      return WeatherInfo(
        tempCelsius: cached.tempCelsius,
        condition: cached.condition,
        description: cached.description,
        iconCode: cached.iconCode,
        humidity: cached.humidity,
        cityName: cached.cityName,
      );
    }

    final apiKey = AppConstants.openWeatherKey;
    if (apiKey.isEmpty) return null;

    HttpClient? client;
    try {
      final uri = Uri.https('api.openweathermap.org', '/data/2.5/weather', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'appid': apiKey,
        'units': 'metric',
        'lang': 'pt_br',
      });
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await response.transform(const Utf8Decoder()).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final main = json['main'] as Map<String, dynamic>;
      final weatherArr = json['weather'] as List<dynamic>;
      final weather = weatherArr.first as Map<String, dynamic>;

      final info = WeatherInfo(
        tempCelsius: (main['temp'] as num).toDouble(),
        condition: weather['main'] as String,
        description: weather['description'] as String,
        iconCode: weather['icon'] as String,
        humidity: (main['humidity'] as num).toInt(),
        cityName: (json['name'] as String?) ?? '',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      await _cacheDao.upsert(WeatherCacheEntriesCompanion.insert(
        id: key,
        lat: lat,
        lon: lon,
        tempCelsius: info.tempCelsius,
        condition: info.condition,
        description: info.description,
        iconCode: info.iconCode,
        humidity: Value(info.humidity),
        cityName: Value(info.cityName),
        fetchedAt: now,
        expiresAt: now + const Duration(hours: 3).inMilliseconds,
      ));
      return info;
    } catch (_) {
      client?.close();
      return null; // silencioso — card mostra estado neutro, não quebra a Home
    }
  }

  // Previsão dos próximos dias (endpoint /forecast, 5 dias/3h). Agrupa as
  // entradas de 3-em-3h por dia, tirando min/max de temperatura e o ícone do
  // horário mais próximo do meio-dia como representativo. Retorna até 5 dias
  // futuros (exclui hoje, que já aparece no clima atual). Cache TTL 3h.
  Future<List<ForecastDay>> getForecast(double lat, double lon) async {
    final key = _cacheKey(lat, lon);
    final cached = await _cacheDao.findValidForecast(key);
    if (cached != null) {
      try {
        final list = jsonDecode(cached.forecastJson) as List<dynamic>;
        return list
            .map((e) => ForecastDay.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {/* JSON corrompido → refaz abaixo */}
    }

    final apiKey = AppConstants.openWeatherKey;
    if (apiKey.isEmpty) return const [];

    HttpClient? client;
    try {
      final uri = Uri.https('api.openweathermap.org', '/data/2.5/forecast', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'appid': apiKey,
        'units': 'metric',
        'lang': 'pt_br',
      });
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        client.close();
        return const [];
      }
      final body = await response.transform(const Utf8Decoder()).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final list = (json['list'] as List<dynamic>).cast<Map<String, dynamic>>();
      final days = _groupByDay(list);

      final now = DateTime.now().millisecondsSinceEpoch;
      await _cacheDao.upsertForecast(WeatherForecastCacheCompanion.insert(
        id: key,
        forecastJson: jsonEncode(days.map((d) => d.toJson()).toList()),
        fetchedAt: now,
        expiresAt: now + const Duration(hours: 3).inMilliseconds,
      ));
      return days;
    } catch (_) {
      client?.close();
      return const [];
    }
  }

  // Agrupa a lista de 3h em dias. Exclui hoje. Até 5 dias.
  List<ForecastDay> _groupByDay(List<Map<String, dynamic>> list) {
    final today = DateTime.now();
    final todayKey = _dayKey(today.year, today.month, today.day);

    // dayKey → {min, max, midEntry (mais próxima de 12h)}
    final byDay = <String, _DayAcc>{};
    for (final item in list) {
      final dtSec = (item['dt'] as num).toInt();
      final dt = DateTime.fromMillisecondsSinceEpoch(dtSec * 1000);
      final k = _dayKey(dt.year, dt.month, dt.day);
      if (k == todayKey) continue; // hoje já está no clima atual

      final main = item['main'] as Map<String, dynamic>;
      final w = (item['weather'] as List<dynamic>).first as Map<String, dynamic>;
      final tMin = (main['temp_min'] as num).toDouble();
      final tMax = (main['temp_max'] as num).toDouble();

      final acc = byDay.putIfAbsent(k, () => _DayAcc(dt));
      acc.min = acc.min == null ? tMin : (tMin < acc.min! ? tMin : acc.min!);
      acc.max = acc.max == null ? tMax : (tMax > acc.max! ? tMax : acc.max!);
      // Ícone/condição do horário mais próximo do meio-dia.
      final noonDist = (dt.hour - 12).abs();
      if (acc.bestNoonDist == null || noonDist < acc.bestNoonDist!) {
        acc.bestNoonDist = noonDist;
        acc.iconCode = w['icon'] as String;
        acc.condition = w['main'] as String;
      }
    }

    final result = byDay.values
        .map((a) => ForecastDay(
              date: DateTime(a.anyDt.year, a.anyDt.month, a.anyDt.day),
              tempMin: a.min ?? 0,
              tempMax: a.max ?? 0,
              condition: a.condition ?? '',
              iconCode: a.iconCode ?? '01d',
            ))
        .toList()
      ..sort((x, y) => x.date.compareTo(y.date));
    return result.take(5).toList();
  }

  String _dayKey(int y, int m, int d) => '$y-$m-$d';
}

// Acumulador interno por dia durante o agrupamento da previsão.
class _DayAcc {
  final DateTime anyDt;
  double? min;
  double? max;
  int? bestNoonDist;
  String? iconCode;
  String? condition;
  _DayAcc(this.anyDt);
}

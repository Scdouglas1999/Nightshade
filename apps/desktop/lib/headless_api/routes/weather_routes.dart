/// Declarative route table for weather + radar endpoints.
///
/// Counterpart to `handlers/weather_handlers.dart`. Aggregates the
/// `/api/weather/*` surface: radar, forecast, NWS alerts, cloud-cover
/// satellite reads, settings, safe-imaging gate, and the cache-clear
/// kick.
library;

import '../handlers/weather_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [WeatherHandlers].
List<HeadlessRoute> buildWeatherRoutes(WeatherHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/weather/radar', h.handleGetRadarData),
  HeadlessRoute(HttpMethod.get, '/api/weather/forecast', h.handleGetForecast),
  HeadlessRoute(HttpMethod.get, '/api/weather/alerts', h.handleGetAlerts),
  HeadlessRoute(
    HttpMethod.get,
    '/api/weather/cloud-cover',
    h.handleGetCloudCover,
  ),
  HeadlessRoute(HttpMethod.get, '/api/weather/settings', h.handleGetSettings),
  HeadlessRoute(
    HttpMethod.post,
    '/api/weather/settings',
    h.handleUpdateSettings,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/weather/safe-imaging',
    h.handleCheckSafeImaging,
  ),
  HeadlessRoute(HttpMethod.get, '/api/weather/current', h.handleGetCurrent),
  HeadlessRoute(
    HttpMethod.post,
    '/api/weather/clear-cache',
    h.handleClearCache,
  ),
];

/// Declarative route table for the sessions / analytics surface.
///
/// Counterpart to `handlers/analytics_handlers.dart`. Sessions CRUD plus
/// the read-only `/api/analytics/*` rollups that aggregate across
/// sessions (total integration time, target-level statistics).
///
/// Order constraint: the literal sub-paths (`active`, `recent`) must
/// register before any `<id>`-parameterised route on `/api/sessions`.
library;

import '../handlers/analytics_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [AnalyticsHandlers].
List<HeadlessRoute> buildAnalyticsRoutes(AnalyticsHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(HttpMethod.get, '/api/sessions', h.handleGetAllSessions),
      HeadlessRoute(
          HttpMethod.get, '/api/sessions/active', h.handleGetActiveSession),
      HeadlessRoute(
          HttpMethod.get, '/api/sessions/recent', h.handleGetRecentSessions),
      HeadlessRoute(
          HttpMethod.get, '/api/sessions/<id>', h.handleGetSessionById),
      HeadlessRoute(
          HttpMethod.get, '/api/sessions/<id>/stats', h.handleGetSessionStats),
      HeadlessRoute(HttpMethod.get, '/api/sessions/<id>/psf-tiles',
          h.handleGetSessionPsfTiles),
      HeadlessRoute(HttpMethod.get, '/api/sessions/<id>/residuals',
          h.handleGetSessionResiduals),
      HeadlessRoute(HttpMethod.get, '/api/sessions/target/<targetId>',
          h.handleGetSessionsForTarget),
      HeadlessRoute(HttpMethod.post, '/api/sessions', h.handleCreateSession),
      HeadlessRoute(
          HttpMethod.put, '/api/sessions/<id>', h.handleUpdateSession),
      HeadlessRoute(
          HttpMethod.post, '/api/sessions/<id>/end', h.handleEndSession),
      HeadlessRoute(
          HttpMethod.delete, '/api/sessions/<id>', h.handleDeleteSession),
      HeadlessRoute(HttpMethod.get, '/api/analytics/summary',
          h.handleGetAnalyticsSummary),
      HeadlessRoute(HttpMethod.get, '/api/analytics/integration-time',
          h.handleGetTotalIntegrationTime),
      HeadlessRoute(HttpMethod.get, '/api/analytics/target-statistics',
          h.handleGetTargetStatistics),
    ];

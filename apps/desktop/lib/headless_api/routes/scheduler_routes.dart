/// Declarative route table for the intelligent-scheduler surface.
///
/// Counterpart to `handlers/scheduler_handlers.dart`. All endpoints are
/// pure-function reads against the scheduler's astronomical math —
/// altitude / transit-time / rise-set / hours-above-horizon — plus the
/// `optimize-targets` POST that runs the per-night ranking.
library;

import '../handlers/scheduler_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [SchedulerHandlers].
List<HeadlessRoute> buildSchedulerRoutes(
  SchedulerHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(
    HttpMethod.get,
    '/api/scheduler/preview',
    h.handlePreviewDecision,
  ),
  HeadlessRoute(HttpMethod.get, '/api/scheduler/state', h.handleGetState),
  HeadlessRoute(HttpMethod.post, '/api/scheduler/control', h.handleControl),
  HeadlessRoute(HttpMethod.post, '/api/scheduler/config', h.handleUpdateConfig),
  HeadlessRoute(
    HttpMethod.get,
    '/api/scheduler/altitude',
    h.handleCalculateAltitude,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/scheduler/transit-time',
    h.handleCalculateTransitTime,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/scheduler/rise-set',
    h.handleCalculateRiseSet,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/scheduler/hours-above-horizon',
    h.handleCalculateHoursAbove,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/scheduler/optimize-targets',
    h.handleOptimizeTargets,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/scheduler/twilight-times',
    h.handleGetTwilightTimes,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/scheduler/moon-info',
    h.handleGetMoonInfo,
  ),
];

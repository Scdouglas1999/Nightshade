/// Declarative route table for the focus-model surface.
///
/// Counterpart to `handlers/focus_model_handlers.dart`. Persists the
/// per-filter temperature/focus regression points, exposes the current
/// regression model, surfaces the predicted focus point for a given
/// temperature, and feeds the "should refocus?" gate the sequencer
/// consults between exposures.
library;

import '../handlers/focus_model_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [FocusModelHandlers].
List<HeadlessRoute> buildFocusModelRoutes(
  FocusModelHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/focus-model/data', h.handleGetFocusData),
  HeadlessRoute(
    HttpMethod.post,
    '/api/focus-model/add-point',
    h.handleAddFocusPoint,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/focus-model/clear',
    h.handleClearFocusData,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/focus-model/model',
    h.handleGetFocusModel,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/focus-model/predict',
    h.handlePredictFocus,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/focus-model/filter-offsets',
    h.handleGetFilterOffsets,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/focus-model/filter-offsets',
    h.handleSetFilterOffsets,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/focus-model/should-refocus',
    h.handleShouldRefocus,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/focus-model/export',
    h.handleExportFocusData,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/focus-model/import',
    h.handleImportFocusData,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/focus-model/predictive',
    h.handleGetPredictiveSettings,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/focus-model/predictive/config',
    h.handleUpdatePredictiveConfig,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/focus-model/predictive/clear-samples',
    h.handleClearPredictiveSamples,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/focus-model/predictive/export',
    h.handleExportPredictiveModel,
  ),
];

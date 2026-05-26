/// Declarative route table for mosaic-planning endpoints.
///
/// Counterpart to `handlers/mosaic_handlers.dart`. All reads/writes for
/// panel generation, area calculation, validation, and time estimation;
/// the recommended-exposure GET wraps the sequencer's exposure model.
library;

import '../handlers/mosaic_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [MosaicHandlers].
List<HeadlessRoute> buildMosaicRoutes(MosaicHandlers h) => <HeadlessRoute>[
      HeadlessRoute(HttpMethod.post, '/api/mosaic/generate-panels',
          h.handleGeneratePanels),
      HeadlessRoute(HttpMethod.post, '/api/mosaic/generate-sequence',
          h.handleGenerateSequence),
      HeadlessRoute(HttpMethod.post, '/api/mosaic/calculate-area',
          h.handleCalculateArea),
      HeadlessRoute(
          HttpMethod.post, '/api/mosaic/validate', h.handleValidateMosaic),
      HeadlessRoute(
          HttpMethod.post, '/api/mosaic/estimate-time', h.handleEstimateTime),
      HeadlessRoute(HttpMethod.get, '/api/mosaic/recommended-exposure',
          h.handleRecommendExposure),
    ];

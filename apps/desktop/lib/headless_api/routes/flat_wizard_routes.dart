/// Declarative route table for the flat-wizard surface.
///
/// Counterpart to `handlers/flat_wizard_handlers.dart`. Calibrates one
/// or many filters into a sequence definition; the resulting sequence
/// is dispatched through the standard sequencer surface.
library;

import '../handlers/flat_wizard_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [FlatWizardHandlers].
List<HeadlessRoute> buildFlatWizardRoutes(FlatWizardHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(HttpMethod.post, '/api/flat-wizard/calibrate',
          h.handleCalibrateFilter),
      HeadlessRoute(HttpMethod.post, '/api/flat-wizard/calibrate-multi',
          h.handleCalibrateMultipleFilters),
      HeadlessRoute(HttpMethod.post, '/api/flat-wizard/generate-sequence',
          h.handleGenerateSequence),
      HeadlessRoute(HttpMethod.post, '/api/flat-wizard/quick-calibrate',
          h.handleQuickCalibrate),
    ];

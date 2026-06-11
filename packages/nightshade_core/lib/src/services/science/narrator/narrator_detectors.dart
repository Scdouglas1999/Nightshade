/// Factory for the standard Night Narrator detector set + the per-eventType
/// cooldown windows the engine applies on top of dedupe.
///
/// Kept in one place so the service and the unit tests instantiate an identical
/// engine. The cooldown map encodes the spec's "long cooldown" / "once per band"
/// hints for the events that would otherwise be allowed to re-fire whenever
/// their dedupeKey legitimately changes (best-seeing, tilt bands, pipeline
/// failures per stage).
library;

import '../science_status.dart' show ScienceStage;
import 'narrator_engine.dart';
import 'detectors/discovery_detectors.dart';
import 'detectors/milestone_detectors.dart';
import 'detectors/conditions_detectors.dart';
import 'detectors/equipment_detectors.dart';
import 'detectors/quality_detectors.dart';

/// The full v1 detector catalog (all 19 detectors), discovery-first.
NarratorEngine buildDefaultNarratorEngine() {
  return NarratorEngine(
    detectors: [
      // Discovery
      MovingObjectDetector(),
      LightCurveEventDetector(),
      PeriodFoundDetector(),
      // Milestone
      LimitingMagDetector(),
      CalibrationLockedDetector(),
      BestSeeingDetector(),
      IntegrationMilestoneDetector(),
      // Conditions
      TransparencyTrendDetector(),
      SkyDarknessDetector(),
      CloudsVsFocusDetector(),
      ExcellentTransparencyDetector(),
      // Equipment
      TiltDetector(),
      FocusDriftDetector(),
      GradientDetector(),
      GuidingDegradedDetector(),
      // Quality / pipeline
      ClippingDetector(),
      RejectBurstDetector(),
      SolveDropDetector(),
      PipelineFailureDetector(),
    ],
    cooldowns: defaultNarratorCooldowns,
  );
}

/// Per-eventType cooldown windows. eventTypes absent here are gated by dedupe
/// alone.
final Map<String, Duration> defaultNarratorCooldowns = {
  'milestone.best_seeing': const Duration(minutes: 30),
  'discovery.moving_object': const Duration(minutes: 15),
  'equipment.tilt': const Duration(hours: 6),
  'equipment.focus_drift': const Duration(minutes: 20),
  'equipment.guiding_degraded': const Duration(minutes: 15),
  'conditions.transparency_trend': const Duration(minutes: 15),
  'quality.solve_drop': const Duration(minutes: 15),
  // Pipeline failures are keyed per-stage (eventType is
  // `quality.pipeline_failure.<stage>`); the engine matches the full string.
  // Generate a cooldown entry for every ScienceStage so no stage (e.g.
  // fitsWriteback / autoGrade) is silently left ungated.
  for (final stage in ScienceStage.values)
    'quality.pipeline_failure.${stage.name}': const Duration(minutes: 10),
};

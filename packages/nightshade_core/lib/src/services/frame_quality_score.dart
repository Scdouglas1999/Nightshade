import 'dart:math' as math;

/// The 0-100 composite quality score stamped on a captured frame.
///
/// One implementation, because there are two capture paths and they were not
/// agreeing. `ImagingService` (the Imaging screen's snapshot/loop) computed a
/// score and stored it; the SEQUENCER frame path — every frame of every
/// unattended night — stored `NULL`.
///
/// What that cost, measured in the running app on 2026-08-09 after a clean
/// ten-frame run:
///
/// ```
/// sqlite> select hfr, star_count, quality_score from captured_images limit 1;
///         2.2388  35  NULL
///
/// Analytics -> Captured Images:  Good: 0   Needs Review: 10   Poor: 0
///                                every tile "65 score"
/// ```
///
/// `FrameQualityAssessmentService` reads `image.qualityScore ?? 75.0`, so with
/// the column null EVERY sequencer frame was assessed from the same constant:
/// the 65 on the tiles was a property of the fallback, not of the frame. A
/// sharp frame and a soft one scored identically, and because 65 sits under the
/// service's `advisoryScore < 70` line, the gallery labelled a flawless night
/// "Needs Review" ten times out of ten and "Good" zero.
///
/// That is worse than a wrong label. Anything downstream that ranks or rejects
/// on quality — stack frame selection, auto-reject, the "best frame" pick — was
/// ranking a constant.
///
/// The weights and bands below are lifted verbatim from
/// `ImagingService._calculateQualityScore`, which in turn mirrors the Rust
/// implementation in `imaging/fits.rs`. Deliberately not retuned here: making
/// the two paths agree is one change, and choosing what "good" should mean is a
/// separate decision with its own evidence.
double computeFrameQualityScore({
  required double? hfr,
  required int? starCount,
  double? mean,
  double? stdDev,
}) {
  double score = 0.0;
  double weightSum = 0.0;

  // HFR (40%). Excellent < 2.0, good 2-3, fair 3-5, poor > 5.
  if (hfr != null && hfr > 0.0) {
    final hfrScore = hfr < 2.0
        ? 100.0
        : hfr < 3.0
        ? 100.0 - (hfr - 2.0) * 25.0
        : hfr < 5.0
        ? 75.0 - (hfr - 3.0) * 25.0
        : math.max(0.0, 25.0 - math.min(5.0, hfr - 5.0) * 5.0);
    score += hfrScore * 0.4;
    weightSum += 0.4;
  }

  // Star count (30%). Excellent > 100, good 50-100, fair 20-50, poor < 20.
  if (starCount != null) {
    final starScore = starCount >= 100
        ? 100.0
        : starCount >= 50
        ? 66.0 + (starCount - 50) / 50.0 * 34.0
        : starCount >= 20
        ? 33.0 + (starCount - 20) / 30.0 * 33.0
        : math.max(0.0, starCount / 20.0 * 33.0);
    score += starScore * 0.3;
    weightSum += 0.3;
  }

  // Background uniformity (30%), via the coefficient of variation.
  //
  // The sequencer's frame event does not carry mean/stdDev, so this component
  // is simply absent there rather than counted as zero — hence the
  // renormalisation below. Scoring a missing measurement as 0 would punish
  // every sequencer frame for a number nobody measured, which is the same
  // mistake in a different place.
  if (mean != null && stdDev != null && mean > 0.0) {
    final cv = stdDev / mean;
    final uniformityScore = cv < 0.1
        ? 100.0
        : cv < 0.3
        ? 100.0 - (cv - 0.1) * 333.0
        : math.max(0.0, 33.0 - math.min(0.33, cv - 0.3) * 100.0);
    score += uniformityScore * 0.3;
    weightSum += 0.3;
  }

  // No measurement at all: say so with a null rather than inventing a number.
  // The assessment service's own `?? 75.0` fallback then applies, and at least
  // it is applying to a frame we genuinely could not measure.
  if (weightSum <= 0.0) return double.nan;

  return (score / weightSum).clamp(0.0, 100.0);
}

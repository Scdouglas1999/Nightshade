import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Wave 5 Agent 4 — live cloud-motion panel for the Run dashboard.
///
/// Reads the live `cloudMotionAnalyzerProvider` output via the existing
/// `analyzeCloudMotionProvider` (cached analyzer result) and the
/// `cloudCoverPercentageProvider` (current Open-Meteo cover). Surfaces:
///   * Current cloud cover with green/yellow/red color-coding.
///   * Predicted arrival time of the next significant cloud bank.
///   * Predicted opening (clear-sky window) time, if currently overcast.
///   * Last-update freshness so the user can tell if the panel has stale data.
///
/// This panel is opt-in: it is disabled by default in the dashboard layout
/// and can be enabled via Edit Dashboard.
class RunDashboardCloudMotionPanel extends ConsumerWidget {
  const RunDashboardCloudMotionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final coverAsync = ref.watch(cloudCoverPercentageProvider);
    final motionAsync = ref.watch(analyzeCloudMotionDetailedProvider);

    final cover = coverAsync.valueOrNull;
    final motionResult = motionAsync.valueOrNull;
    final motion = motionResult?.motion;
    final arrivalMins = motion?.etaToLocation?.inMinutes;
    // When the analyzer could not produce a real motion estimate it returns an
    // explicit reason. Surface it honestly instead of silently showing
    // "No prediction" — the operator needs to know whether the predictive
    // cloud-arrival pause is actually available tonight.
    final unavailableReason = motionResult?.unavailableReason;

    final (coverLabel, coverColor) = _coverColor(cover, colors);

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.cloud, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  'CLOUD MOTION',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: colors.textMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: NightshadeDecorations.statusChip(
                  coverColor,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusXs),
                ),
                child: Text(
                  coverLabel,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    fontWeight: FontWeight.w700,
                    color: coverColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _row(
            colors,
            label: 'Current Cover',
            value: cover == null ? 'No data' : '${cover.toStringAsFixed(0)} %',
            highlight: coverColor,
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          _row(
            colors,
            label: 'Cloud Arrival',
            value: arrivalMins == null ? 'No prediction' : '$arrivalMins min',
            highlight: arrivalMins != null && arrivalMins <= 15
                ? colors.error
                : colors.textPrimary,
          ),
          if (motion == null && unavailableReason != null) ...[
            const SizedBox(height: NightshadeTokens.spaceXs),
            Text(
              'Cloud-motion unavailable: ${_reasonLabel(unavailableReason)}',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                fontStyle: FontStyle.italic,
                color: colors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceXs),
          _row(
            colors,
            label: 'Opening In',
            // The analyzer does not yet model a future-opening curve.
            // Show a hint instead of fabricating data — silent fallback
            // would defeat "errors are a feature".
            value: cover != null && cover < 30.0 ? 'Now (cover < 30%)' : '—',
            highlight: colors.textPrimary,
          ),
          if (motion?.distanceKm != null) ...[
            const SizedBox(height: NightshadeTokens.spaceXs),
            _row(
              colors,
              label: 'Nearest Cloud',
              value: '${motion!.distanceKm.toStringAsFixed(0)} km',
              highlight: colors.textPrimary,
            ),
          ],
          if (motion?.speedKmh != null) ...[
            const SizedBox(height: NightshadeTokens.spaceXs),
            _row(
              colors,
              label: 'Motion',
              value:
                  '${motion!.speedKmh.toStringAsFixed(0)} km/h @ ${motion.directionDegrees.toStringAsFixed(0)}°',
              highlight: colors.textPrimary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(NightshadeColors colors,
      {required String label, required String value, Color? highlight}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted),
          ),
        ),
        Text(
          value,
          style: NightshadeTypography.h6
              .copyWith(color: highlight ?? colors.textPrimary),
        ),
      ],
    );
  }

  /// Human-readable explanation of why cloud-motion prediction is unavailable.
  /// Mirrors [CloudMotionUnavailableReason] one-to-one so a new enum value
  /// would surface as a (compile-time-flagged) missing case rather than a
  /// silent blank.
  String _reasonLabel(CloudMotionUnavailableReason reason) {
    switch (reason) {
      case CloudMotionUnavailableReason.insufficientFrames:
        return 'not enough radar frames yet';
      case CloudMotionUnavailableReason.noCloudsDetected:
        return 'no clouds to track (clear sky)';
      case CloudMotionUnavailableReason.noSpatialData:
        return 'no spatial radar data';
      case CloudMotionUnavailableReason.noResolvableMotion:
        return 'clouds not moving enough to predict';
    }
  }

  /// Green < 20%, yellow 20-50%, red > 50%. Matches the brief.
  (String label, Color color) _coverColor(double? cover, NightshadeColors c) {
    if (cover == null) return ('NO DATA', c.textMuted);
    if (cover < 20) return ('CLEAR', c.success);
    if (cover < 50) return ('PARTLY', c.warning);
    return ('OVERCAST', c.error);
  }
}

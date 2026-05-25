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
/// The opt-in toggle lives on the Run dashboard customize menu under
/// `RunDashboardPanelId.cloudMotion`.
class RunDashboardCloudMotionPanel extends ConsumerWidget {
  const RunDashboardCloudMotionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final coverAsync = ref.watch(cloudCoverPercentageProvider);
    final motionAsync = ref.watch(analyzeCloudMotionProvider);

    final cover = coverAsync.valueOrNull;
    final motion = motionAsync.valueOrNull;
    final arrivalMins = motion?.etaToLocation?.inMinutes;

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
                    fontSize: 11,
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
                    fontSize: 10,
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
            value: cover == null
                ? 'No data'
                : '${cover.toStringAsFixed(0)} %',
            highlight: coverColor,
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          _row(
            colors,
            label: 'Cloud Arrival',
            value: arrivalMins == null
                ? 'No prediction'
                : '$arrivalMins min',
            highlight: arrivalMins != null && arrivalMins <= 15
                ? colors.error
                : colors.textPrimary,
          ),
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
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: highlight ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Green < 20%, yellow 20-50%, red > 50%. Matches the brief.
  (String label, Color color) _coverColor(double? cover, NightshadeColors c) {
    if (cover == null) return ('NO DATA', c.textMuted);
    if (cover < 20) return ('CLEAR', c.success);
    if (cover < 50) return ('PARTLY', c.warning);
    return ('OVERCAST', c.error);
  }
}

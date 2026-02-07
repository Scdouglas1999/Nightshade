import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ScienceInsightsPanel extends StatelessWidget {
  final NightshadeColors colors;
  final ScienceFrameQualityMetricsRow? frameMetrics;
  final FramePhotometricCalibrationRow? latestCalibration;
  final TransparencySampleRow? latestTransparency;

  const ScienceInsightsPanel({
    super.key,
    required this.colors,
    required this.frameMetrics,
    required this.latestCalibration,
    required this.latestTransparency,
  });

  @override
  Widget build(BuildContext context) {
    final insights = _buildInsights();

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Insights',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (insights.isEmpty)
              Text(
                'No actionable insights yet. Keep capturing frames.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              )
            else
              ...insights.map(
                (insight) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: insight.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          insight.message,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            height: 1.32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_Insight> _buildInsights() {
    final output = <_Insight>[];
    final fm = frameMetrics;
    if (fm != null) {
      if (fm.highClipPercent > 1.5) {
        output.add(
          const _Insight(
            message:
                'High clipping is elevated. Reduce exposure or gain to protect highlights.',
            color: Color(0xFFEF4444),
          ),
        );
      }
      if (fm.lowClipPercent > 1.5) {
        output.add(
          const _Insight(
            message:
                'Shadow clipping is elevated. Consider longer exposure or less aggressive black point.',
            color: Color(0xFF3B82F6),
          ),
        );
      }
      if (fm.uniformityCv > 0.28) {
        output.add(
          const _Insight(
            message:
                'Brightness uniformity is uneven. Check gradients, flats, and optical tilt.',
            color: Color(0xFFF59E0B),
          ),
        );
      }
      if (fm.snr < 10) {
        output.add(
          const _Insight(
            message:
                'Frame SNR is low. Stack more frames or increase exposure length.',
            color: Color(0xFF22C55E),
          ),
        );
      }
    }

    final transparency = latestTransparency;
    if (transparency != null && transparency.transparencyPercent < 75) {
      output.add(
        _Insight(
          message:
              'Sky transparency is ${transparency.transparencyPercent.toStringAsFixed(1)}%. Quality frames may vary; prioritize best windows.',
          color: const Color(0xFF06B6D4),
        ),
      );
    }

    final calibration = latestCalibration;
    if (calibration != null &&
        calibration.isCalibrated &&
        calibration.calibrationRms > 0.2) {
      output.add(
        _Insight(
          message:
              'Photometric fit RMS is ${calibration.calibrationRms.toStringAsFixed(2)}. Verify focus and plate-solve inputs.',
          color: const Color(0xFFA855F7),
        ),
      );
    }

    return output;
  }
}

class _Insight {
  final String message;
  final Color color;

  const _Insight({
    required this.message,
    required this.color,
  });
}

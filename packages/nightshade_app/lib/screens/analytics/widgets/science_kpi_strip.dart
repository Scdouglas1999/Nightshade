import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ScienceKpiStrip extends StatelessWidget {
  final NightshadeColors colors;
  final FramePhotometricCalibrationRow? latestCalibration;
  final TransparencySampleRow? latestTransparency;
  final ScienceFrameQualityMetricsRow? latestFrameQuality;
  final int movingCandidateCount;

  const ScienceKpiStrip({
    super.key,
    required this.colors,
    required this.latestCalibration,
    required this.latestTransparency,
    required this.latestFrameQuality,
    required this.movingCandidateCount,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _KpiCard(
          colors: colors,
          title: 'Calibration',
          value: latestCalibration == null
              ? 'N/A'
              : latestCalibration!.isCalibrated
                  ? 'Calibrated'
                  : 'Uncalibrated',
          subtitle: latestCalibration?.zeroPoint == null
              ? 'ZP unavailable'
              : 'ZP ${latestCalibration!.zeroPoint!.toStringAsFixed(2)}',
        ),
        _KpiCard(
          colors: colors,
          title: 'Transparency',
          value: latestTransparency == null
              ? 'N/A'
              : '${latestTransparency!.transparencyPercent.toStringAsFixed(1)}%',
          subtitle: latestTransparency?.qualityBucket ?? 'No trend yet',
        ),
        _KpiCard(
          colors: colors,
          title: 'Uniformity CV',
          value: latestFrameQuality == null
              ? 'N/A'
              : latestFrameQuality!.uniformityCv.toStringAsFixed(3),
          subtitle: latestFrameQuality == null
              ? 'No frame metrics yet'
              : 'SNR ${latestFrameQuality!.snr.toStringAsFixed(1)}',
        ),
        _KpiCard(
          colors: colors,
          title: 'Moving Objects',
          value: movingCandidateCount.toString(),
          subtitle: movingCandidateCount == 0
              ? 'No candidates'
              : 'Live track overlay ready',
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final String value;
  final String subtitle;

  const _KpiCard({
    required this.colors,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: NightshadeCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

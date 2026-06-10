import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'adaptive_chart_container.dart';

/// Card: Zero-Point trend across the current session.
///
/// Y axis is mag (higher is better — fainter stars detectable). The line
/// is drawn from all calibrated frames in chronological order, with the
/// uncalibrated frames dropped on the floor so the trend reflects what
/// the photometric model actually believes about the sky tonight.
///
/// Why this matters: a smoothly rising ZP across the night says
/// transparency is improving (or you came out of moonlight or twilight);
/// a sudden drop says clouds rolled in. NINA/SGP plot HFR over time but
/// neither plots ZP.
class ZeroPointTrendCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<FramePhotometricCalibrationRow> calibrations;

  const ZeroPointTrendCard({
    super.key,
    required this.colors,
    required this.calibrations,
  });

  @override
  Widget build(BuildContext context) {
    final points = <_TrendPoint>[];
    for (final c in calibrations) {
      final zp = c.zeroPoint;
      if (zp == null || !zp.isFinite || !c.isCalibrated) continue;
      points.add(_TrendPoint(c.timestamp, zp));
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return _TrendCardShell(
      colors: colors,
      icon: LucideIcons.gauge,
      title: 'Zero point over time',
      subtitle:
          'Higher = fainter stars detectable at the same exposure. Rises mean '
          'transparency is improving; sudden drops typically indicate '
          'clouds.',
      points: points,
      lineColor: colors.success,
      yLabel: 'ZP (mag)',
      formatY: (v) => v.toStringAsFixed(2),
      emptyMessage:
          'No calibrated frames yet. The trend appears once at least one '
          'frame fits a photometric model.',
    );
  }
}

/// Card: rolling plate-solve success rate across the current session.
///
/// Computed as a sliding window (default 8 frames) over the captured-image
/// stream — at frame N the value is the fraction of the last 8 frames
/// that returned a WCS. This is much more diagnostic than the raw cumulative
/// rate because it shows *when* solving started failing, which is usually
/// the moment clouds appeared or guiding drifted past tolerance.
/// HFR trend from accepted light frames (classic session quality metric).
class HfrTrendCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<DbCapturedImage> lightFrames;

  const HfrTrendCard({
    super.key,
    required this.colors,
    required this.lightFrames,
  });

  @override
  Widget build(BuildContext context) {
    final points = <_TrendPoint>[];
    final sorted = lightFrames
        .where((img) => img.isAccepted && img.hfr != null)
        .toList(growable: false)
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    for (final img in sorted) {
      points.add(_TrendPoint(img.capturedAt, img.hfr!));
    }

    return _TrendCardShell(
      colors: colors,
      icon: LucideIcons.focus,
      title: 'HFR over time',
      subtitle:
          'Half-flux radius of detected stars per frame. Spikes usually mean '
          'focus drift, seeing degradation, or clouds.',
      points: points,
      lineColor: colors.warning,
      yLabel: 'HFR (px)',
      formatY: (v) => v.toStringAsFixed(2),
      emptyMessage: 'HFR appears once star metrics are recorded on captures.',
    );
  }
}

/// Uniformity CV trend from frame-quality maps.
class UniformityTrendCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<ScienceFrameQualityMetricsRow> frameMetrics;

  const UniformityTrendCard({
    super.key,
    required this.colors,
    required this.frameMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final points = <_TrendPoint>[];
    final sorted = frameMetrics.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (final m in sorted) {
      if (!m.uniformityCv.isFinite) continue;
      points.add(_TrendPoint(m.timestamp, m.uniformityCv));
    }

    return _TrendCardShell(
      colors: colors,
      icon: LucideIcons.layoutGrid,
      title: 'Field uniformity (CV)',
      subtitle:
          'Background brightness coefficient of variation. Values above ~0.28 '
          'often indicate gradients from vignetting or moon glow.',
      points: points,
      lineColor: colors.primary,
      yLabel: 'CV',
      formatY: (v) => v.toStringAsFixed(3),
      emptyMessage:
          'Uniformity maps appear once frame-quality processing is enabled.',
    );
  }
}

class SolveRateTrendCard extends StatelessWidget {
  final NightshadeColors colors;
  final List<DbCapturedImage> lightFrames;
  final int windowSize;

  const SolveRateTrendCard({
    super.key,
    required this.colors,
    required this.lightFrames,
    this.windowSize = 8,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = lightFrames.toList(growable: false)
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final points = <_TrendPoint>[];
    if (sorted.length >= 2) {
      for (var i = 0; i < sorted.length; i++) {
        final start = math.max(0, i + 1 - windowSize);
        final window = sorted.sublist(start, i + 1);
        final solved =
            window.where((img) => img.isPlateSolved).length / window.length;
        points.add(_TrendPoint(sorted[i].capturedAt, solved * 100.0));
      }
    }

    return _TrendCardShell(
      colors: colors,
      icon: LucideIcons.crosshair,
      title: 'Plate-solve rate (rolling)',
      subtitle:
          'Fraction of the last $windowSize frames that solved. A dip is the '
          'fastest indicator that clouds, guiding excursions, or focus drift '
          'are starting to affect the session.',
      points: points,
      lineColor: colors.info,
      yLabel: 'Solve rate (%)',
      minY: 0,
      maxY: 100,
      formatY: (v) => '${v.toStringAsFixed(0)}%',
      emptyMessage:
          'Need at least 2 light frames before a rolling solve-rate trend '
          'is meaningful.',
    );
  }
}

class _TrendPoint {
  final DateTime timestamp;
  final double value;
  _TrendPoint(this.timestamp, this.value);
}

class _TrendCardShell extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<_TrendPoint> points;
  final Color lineColor;
  final String yLabel;
  final String Function(double) formatY;
  final double? minY;
  final double? maxY;
  final String emptyMessage;

  const _TrendCardShell({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.lineColor,
    required this.yLabel,
    required this.formatY,
    required this.emptyMessage,
    this.minY,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: lineColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (points.isNotEmpty)
                  _LatestPill(
                    colors: colors,
                    label: formatY(points.last.value),
                    color: lineColor,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            AdaptiveChartContainer(
              preferredHeight: 160,
              child: points.length < 2
                  ? _Placeholder(colors: colors, message: emptyMessage)
                  : _buildChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final firstTs = points.first.timestamp;
    final spots = points
        .map((p) => FlSpot(
              p.timestamp.difference(firstTs).inSeconds.toDouble(),
              p.value,
            ))
        .toList();

    final values = points.map((p) => p.value);
    final dataMin = values.reduce(math.min);
    final dataMax = values.reduce(math.max);
    final padding = math.max(0.05, (dataMax - dataMin) * 0.1);
    final effectiveMinY = minY ?? (dataMin - padding);
    final effectiveMaxY = maxY ?? (dataMax + padding);
    final yRange = math.max(1e-6, effectiveMaxY - effectiveMinY);
    final lastX = spots.last.x == 0 ? 1.0 : spots.last.x;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: lastX,
        minY: effectiveMinY,
        maxY: effectiveMaxY,
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: colors.border),
        ),
        gridData: FlGridData(
          horizontalInterval: yRange / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.border.withValues(alpha: 0.3)),
          getDrawingVerticalLine: (_) =>
              FlLine(color: colors.border.withValues(alpha: 0.2)),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: math.max(1, (lastX / 4).floorToDouble()),
              getTitlesWidget: (value, meta) {
                final mins = (value / 60).round();
                return Text(
                  '${mins}m',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    color: colors.textSecondary,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              yLabel,
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize10),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (value, meta) => Text(
                formatY(value),
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: lineColor,
            barWidth: 2,
            isCurved: false,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.12),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => colors.surface,
            getTooltipItems: (touched) => touched.map((spot) {
              final mins = (spot.x / 60).round();
              return LineTooltipItem(
                '${formatY(spot.y)}\n${mins}m into session',
                NightshadeTypography.labelQuiet.copyWith(
                  color: colors.textPrimary,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _LatestPill extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final Color color;

  const _LatestPill({
    required this.colors,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final NightshadeColors colors;
  final String message;

  const _Placeholder({required this.colors, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize11,
          color: colors.textSecondary,
          height: 1.4,
        ),
      ),
    );
  }
}

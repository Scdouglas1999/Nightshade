import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart' show DbCapturedImage;

import 'adaptive_chart_container.dart';
import 'chart_axis.dart';

/// Chart data point with timestamp and value
class ChartDataPoint {
  final DateTime timestamp;
  final double value;

  const ChartDataPoint({
    required this.timestamp,
    required this.value,
  });
}

/// Generic session chart for a measured time series.
///
/// Draws what was measured: samples are joined with straight segments (a spline
/// invents values between samples and overshoots past the real minimum, which
/// on an HFR trace reads as focus the run never achieved), and the median is
/// marked so a frame can be judged against the night rather than by eye.
class SessionChart extends StatelessWidget {
  final String title;

  /// Axis label including units, e.g. `HFR (px)`.
  final String yAxisLabel;

  /// What the series measures, as a noun phrase for prose — "sensor
  /// temperature", "guiding RMS". Separate from [yAxisLabel] because the axis
  /// label carries units and reads as a typo in a sentence: composing the empty
  /// state from it produced "No HFR (px) recorded for these frames" and, for
  /// the temperature chart whose axis is just the unit, "No °C recorded for
  /// these frames". Falls back to the card title.
  final String? measurementName;

  final List<ChartDataPoint> dataPoints;
  final Color lineColor;
  final double? minY;
  final double? maxY;

  /// Values above this read as a problem; drawn as a threshold line when the
  /// data comes near it. Optional — most series have no meaningful limit.
  final double? warnAbove;

  const SessionChart({
    super.key,
    required this.title,
    required this.yAxisLabel,
    required this.dataPoints,
    this.measurementName,
    this.lineColor = NightshadeChartColors.seriesBlue,
    this.minY,
    this.maxY,
    this.warnAbove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    if (dataPoints.isEmpty) {
      return _ChartShell(
        title: title,
        yAxisLabel: yAxisLabel,
        colors: colors,
        child: AdaptiveChartContainer.fixed(
          height: 150,
          child: Center(
            child: Text(
              'No ${measurementName ?? title.toLowerCase()} recorded for '
              'these frames',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    // Never trust the caller's ordering: the standalone-image query returns
    // newest-first while the per-session query returns oldest-first, and an
    // unsorted series silently draws the night backwards (and, with x measured
    // from the first point, produced a negative axis whose labels vanished).
    final points = dataPoints.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final values = points.map((p) => p.value).toList(growable: false);
    final sorted = values.toList()..sort();
    final median = _percentile(sorted, 0.5);
    final p90 = _percentile(sorted, 0.9);
    final dataMin = sorted.first;
    final dataMax = sorted.last;

    final NiceAxis axis = NiceAxis.forRange(minY ?? dataMin, maxY ?? dataMax);
    final isFlat = dataMax - dataMin <= 0;

    final firstTimestamp = points.first.timestamp;
    final spots = points
        .map((point) => FlSpot(
              point.timestamp.difference(firstTimestamp).inMilliseconds /
                  1000.0,
              point.value,
            ))
        .toList(growable: false);
    final maxX = spots.last.x <= 0 ? 1.0 : spots.last.x;
    // Divide the span exactly rather than snapping to a round step: that puts
    // the final tick ON the axis end, so fl_chart's boundary label coincides
    // with a tick instead of drawing a second offset copy of it — and it does
    // not pad the plot out to a tick the data never reaches.
    final xInterval = maxX / 4;

    return _ChartShell(
      title: title,
      yAxisLabel: yAxisLabel,
      colors: colors,
      summary: _ChartSummary(
        colors: colors,
        median: axis.label(median),
        spread: '${axis.label(dataMin)}–${axis.label(dataMax)}',
        p90: axis.label(p90),
        count: points.length,
      ),
      child: AdaptiveChartContainer(
        preferredHeight: 150,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: axis.interval,
              verticalInterval: xInterval,
              getDrawingHorizontalLine: (_) => FlLine(
                color: colors.border.withValues(alpha: 0.3),
                strokeWidth: 1,
              ),
              getDrawingVerticalLine: (_) => FlLine(
                color: colors.border.withValues(alpha: 0.3),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: xInterval,
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(
                      elapsedAxisLabel(value),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: NightshadeTypography.fontSize10,
                      ),
                    ),
                  ),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: axis.interval,
                  getTitlesWidget: (value, meta) => Text(
                    axis.label(value),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize10,
                    ),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: colors.border),
            ),
            minX: 0,
            maxX: maxX,
            minY: axis.min,
            maxY: axis.max,
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                // The median is the honest "typical" value for a skewed
                // quantity like HFR, where a few clouded frames drag the mean.
                HorizontalLine(
                  y: median,
                  color: colors.textMuted.withValues(alpha: 0.55),
                  strokeWidth: 1,
                  dashArray: const [4, 4],
                ),
                if (warnAbove != null &&
                    warnAbove! <= axis.max &&
                    warnAbove! >= axis.min)
                  HorizontalLine(
                    y: warnAbove!,
                    color: colors.warning.withValues(alpha: 0.5),
                    strokeWidth: 1,
                    dashArray: const [2, 4],
                  ),
              ],
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                // Straight segments only: these are measurements, not a model.
                isCurved: false,
                color: lineColor,
                barWidth: 1.6,
                isStrokeCapRound: true,
                dotData: FlDotData(show: spots.length <= 40),
                belowBarData: BarAreaData(
                  // A filled area under a constant series implies a magnitude
                  // that isn't being measured — the sensor sitting at 20.0 C
                  // filled half the card.
                  show: !isFlat,
                  color: lineColor.withValues(alpha: 0.08),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => colors.surfaceElevated,
                getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                  final when = firstTimestamp
                      .add(Duration(milliseconds: (spot.x * 1000).round()));
                  return LineTooltipItem(
                    '${axis.label(spot.y)} $yAxisLabel\n'
                    '${DateFormat('HH:mm:ss').format(when)}'
                    '  ·  +${elapsedAxisLabel(spot.x)}',
                    NightshadeTypography.labelQuiet.copyWith(
                      color: colors.textPrimary,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Linear-interpolated percentile of an already-sorted list.
  static double _percentile(List<double> sorted, double fraction) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final position = fraction * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }
}

/// Card, title and axis caption shared by the populated and empty states so the
/// two never differ in height or padding.
class _ChartShell extends StatelessWidget {
  final String title;
  final String yAxisLabel;
  final NightshadeColors colors;
  final Widget child;
  final Widget? summary;

  const _ChartShell({
    required this.title,
    required this.yAxisLabel,
    required this.colors,
    required this.child,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: NightshadeTypography.h5
                            .copyWith(color: colors.textPrimary),
                      ),
                      Text(
                        yAxisLabel,
                        style: NightshadeTypography.caption
                            .copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (summary != null) summary!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Median / spread / n, so the chart answers "was this a good night?" without
/// the user reading values off the line.
class _ChartSummary extends StatelessWidget {
  final NightshadeColors colors;
  final String median;
  final String spread;
  final String p90;
  final int count;

  const _ChartSummary({
    required this.colors,
    required this.median,
    required this.spread,
    required this.p90,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: NightshadeTypography.caption
                    .copyWith(color: colors.textMuted),
              ),
              Text(
                value,
                style: NightshadeTypography.labelSm
                    .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        stat('median', median),
        stat('p90', p90),
        stat('range', spread),
        stat('n', '$count'),
      ],
    );
  }
}

/// The one frame population every chart on the session card plots.
///
/// Each chart used to pick its own: HFR filtered `isAccepted` and the other
/// three filtered nothing, so a single card reported n=10 beside n=12 and n=16
/// for the same night. Worse than untidy — the guiding trace then averaged in
/// the frames the grader had already thrown out and claimed a p90 of 3.9" for a
/// session whose accepted subs never guided past 0.95", which reads as a mount
/// fault that does not exist. Calibration frames are excluded for the same
/// reason: a dark's sensor temperature is real but it is not part of the night
/// the rest of the card describes.
List<DbCapturedImage> sessionChartFrames(List<DbCapturedImage> images) => images
    .where(
        (image) => image.isAccepted && image.frameType.toLowerCase() == 'light')
    .toList(growable: false);

/// HFR (Half-Flux Radius) trend chart
class HfrChart extends StatelessWidget {
  final List<DbCapturedImage> images;

  const HfrChart({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    // No per-chart population filter here (or in the three charts below): the
    // caller passes [sessionChartFrames] so all four describe the same frames.
    final dataPoints = images
        .where((img) => img.hfr != null)
        .map((img) => ChartDataPoint(
              timestamp: img.capturedAt,
              value: img.hfr!,
            ))
        .toList();

    return SessionChart(
      title: 'Image quality',
      yAxisLabel: 'HFR (px)',
      measurementName: 'half-flux radius',
      dataPoints: dataPoints,
      lineColor: NightshadeChartColors.seriesBlue,
    );
  }
}

/// Temperature trend chart
class TemperatureChart extends StatelessWidget {
  final List<DbCapturedImage> images;

  const TemperatureChart({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    final dataPoints = images
        .where((img) => img.sensorTemp != null)
        .map((img) => ChartDataPoint(
              timestamp: img.capturedAt,
              value: img.sensorTemp!,
            ))
        .toList();

    return SessionChart(
      title: 'Sensor temperature',
      yAxisLabel: '°C',
      dataPoints: dataPoints,
      lineColor: NightshadeChartColors.seriesOrange,
    );
  }
}

/// Guiding RMS chart
class GuidingRmsChart extends StatelessWidget {
  final List<DbCapturedImage> images;

  const GuidingRmsChart({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    final dataPoints = images
        .where((img) => img.guidingRmsTotal != null)
        .map((img) => ChartDataPoint(
              timestamp: img.capturedAt,
              value: img.guidingRmsTotal!,
            ))
        .toList();

    return SessionChart(
      title: 'Guiding performance',
      yAxisLabel: 'RMS (arcsec)',
      measurementName: 'guiding RMS',
      dataPoints: dataPoints,
      lineColor: NightshadeChartColors.seriesGreen,
      // Guiding worse than about 1" starts to bloat stars at typical
      // amateur focal lengths, so it is worth marking on the plot.
      warnAbove: 1.0,
    );
  }
}

/// Focuser position chart (for focus drift tracking)
class FocuserPositionChart extends StatelessWidget {
  final List<DbCapturedImage> images;

  const FocuserPositionChart({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    final dataPoints = images
        .where((img) => img.focuserPosition != null)
        .map((img) => ChartDataPoint(
              timestamp: img.capturedAt,
              value: img.focuserPosition!.toDouble(),
            ))
        .toList();

    return SessionChart(
      title: 'Focus drift',
      yAxisLabel: 'Focuser position (steps)',
      measurementName: 'focuser position',
      dataPoints: dataPoints,
      lineColor: NightshadeChartColors.seriesViolet,
    );
  }
}

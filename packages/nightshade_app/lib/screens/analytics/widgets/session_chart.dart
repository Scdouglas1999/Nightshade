import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/src/database/database.dart' show CapturedImage;

/// Chart data point with timestamp and value
class ChartDataPoint {
  final DateTime timestamp;
  final double value;

  const ChartDataPoint({
    required this.timestamp,
    required this.value,
  });
}

/// Generic session chart widget for displaying time-series data
class SessionChart extends StatelessWidget {
  final String title;
  final String yAxisLabel;
  final List<ChartDataPoint> dataPoints;
  final Color lineColor;
  final double? minY;
  final double? maxY;

  const SessionChart({
    super.key,
    required this.title,
    required this.yAxisLabel,
    required this.dataPoints,
    this.lineColor = Colors.blue,
    this.minY,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    if (dataPoints.isEmpty) {
      return NightshadeCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'No data',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Find min/max for scaling
    final values = dataPoints.map((p) => p.value).toList();
    final dataMinY = minY ?? values.reduce((a, b) => a < b ? a : b);
    final dataMaxY = maxY ?? values.reduce((a, b) => a > b ? a : b);
    // Ensure minimum range to avoid division by zero with single datapoint
    final yRange = max(dataMaxY - dataMinY, 1.0);
    final yPadding = yRange * 0.1;

    final chartMinY = dataMinY - yPadding;
    final chartMaxY = dataMaxY + yPadding;

    // Convert timestamps to x values (seconds from first point)
    final firstTimestamp = dataPoints.first.timestamp;
    final spots = dataPoints.map((point) {
      final x = point.timestamp.difference(firstTimestamp).inSeconds.toDouble();
      return FlSpot(x, point.value);
    }).toList();

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: yRange / 4,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: colors.border.withValues(alpha: 0.3),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: colors.border.withValues(alpha: 0.3),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: spots.last.x / 4,
                        getTitlesWidget: (value, meta) {
                          final duration = Duration(seconds: value.toInt());
                          final hours = duration.inHours;
                          final minutes = duration.inMinutes.remainder(60);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              hours > 0
                                  ? '${hours}h${minutes}m'
                                  : '${minutes}m',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yRange / 4,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(1),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: colors.border),
                  ),
                  minX: 0,
                  maxX: spots.last.x,
                  minY: chartMinY,
                  maxY: chartMaxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: lineColor,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: lineColor.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) => colors.surface,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final duration = Duration(seconds: spot.x.toInt());
                          final hours = duration.inHours;
                          final minutes = duration.inMinutes.remainder(60);
                          final timeStr = hours > 0
                              ? '${hours}h ${minutes}m'
                              : '${minutes}m';
                          return LineTooltipItem(
                            '$yAxisLabel\n${spot.y.toStringAsFixed(2)}\n$timeStr',
                            TextStyle(
                              color: colors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// HFR (Half-Flux Radius) trend chart
class HfrChart extends StatelessWidget {
  final List<CapturedImage> images;

  const HfrChart({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    final dataPoints = images
        .where((img) => img.hfr != null && img.isAccepted)
        .map((img) => ChartDataPoint(
              timestamp: img.capturedAt,
              value: img.hfr!,
            ))
        .toList();

    return SessionChart(
      title: 'Image Quality',
      yAxisLabel: 'HFR (px)',
      dataPoints: dataPoints,
      lineColor: Colors.blue,
    );
  }
}

/// Temperature trend chart
class TemperatureChart extends StatelessWidget {
  final List<CapturedImage> images;

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
      title: 'Temperature',
      yAxisLabel: '°C',
      dataPoints: dataPoints,
      lineColor: Colors.orange,
    );
  }
}

/// Guiding RMS chart
class GuidingRmsChart extends StatelessWidget {
  final List<CapturedImage> images;

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
      title: 'Guiding Performance',
      yAxisLabel: 'RMS (")',
      dataPoints: dataPoints,
      lineColor: Colors.green,
    );
  }
}

/// Focuser position chart (for focus drift tracking)
class FocuserPositionChart extends StatelessWidget {
  final List<CapturedImage> images;

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
      title: 'Focus Drift',
      yAxisLabel: 'Position',
      dataPoints: dataPoints,
      lineColor: Colors.purple,
    );
  }
}

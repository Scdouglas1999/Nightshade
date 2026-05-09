import 'package:flutter/material.dart';

import '../../theme/nightshade_colors.dart';

/// A single guide data point for the graph
class GuideDataPoint {
  final DateTime timestamp;
  final double raError;
  final double decError;
  final double? raPulse;
  final double? decPulse;

  const GuideDataPoint({
    required this.timestamp,
    required this.raError,
    required this.decError,
    this.raPulse,
    this.decPulse,
  });
}

/// Time scale options for the graph
enum GraphTimeScale {
  oneMinute(Duration(minutes: 1), '1m'),
  fiveMinutes(Duration(minutes: 5), '5m'),
  fifteenMinutes(Duration(minutes: 15), '15m'),
  thirtyMinutes(Duration(minutes: 30), '30m');

  final Duration duration;
  final String label;

  const GraphTimeScale(this.duration, this.label);
}

/// Y-axis scale options for the graph
enum GraphYScale {
  one(1.0, '±1"'),
  two(2.0, '±2"'),
  four(4.0, '±4"'),
  eight(8.0, '±8"');

  final double arcsec;
  final String label;

  const GraphYScale(this.arcsec, this.label);
}

/// Advanced guiding graph widget that displays RA/Dec error traces over time
class GuideGraphAdvanced extends StatelessWidget {
  /// List of guide data points (newest last)
  final List<GuideDataPoint> data;

  /// Time scale for X-axis
  final GraphTimeScale timeScale;

  /// Y-axis scale in arcseconds
  final GraphYScale yScale;

  /// Whether to show RA trace
  final bool showRa;

  /// Whether to show Dec trace
  final bool showDec;

  /// Whether to show pulse duration overlay
  final bool showPulses;

  /// Current RMS values for the statistics bar
  final double rmsRa;
  final double rmsDec;
  final double rmsTotal;

  /// Callback when time scale is changed
  final void Function(GraphTimeScale)? onTimeScaleChanged;

  /// Callback when Y scale is changed
  final void Function(GraphYScale)? onYScaleChanged;

  const GuideGraphAdvanced({
    super.key,
    required this.data,
    this.timeScale = GraphTimeScale.fiveMinutes,
    this.yScale = GraphYScale.two,
    this.showRa = true,
    this.showDec = true,
    this.showPulses = false,
    this.rmsRa = 0,
    this.rmsDec = 0,
    this.rmsTotal = 0,
    this.onTimeScaleChanged,
    this.onYScaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      children: [
        // Graph controls and RMS stats
        _buildControlsBar(context),
        const SizedBox(height: 4),
        // Main graph
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors.background,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _GraphPainter(
                    colors: colors,
                    data: data,
                    timeScale: timeScale,
                    yScale: yScale,
                    showRa: showRa,
                    showDec: showDec,
                    showPulses: showPulses,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsBar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colors = Theme.of(context).extension<NightshadeColors>()!;
        final isCompact = constraints.maxWidth < 450;
        final isVeryCompact = constraints.maxWidth < 350;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 6 : 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              // RMS Statistics - hide on very compact screens (shown elsewhere)
              if (!isVeryCompact)
                Flexible(
                  child: ClipRect(
                    child: _buildRmsStats(colors: colors, compact: isCompact),
                  ),
                ),
              if (!isVeryCompact) SizedBox(width: isCompact ? 6 : 8),
              // Time scale selector
              _buildScaleSelector(
                colors: colors,
                label: isCompact ? 'T:' : 'Time:',
                value: timeScale.label,
                items: GraphTimeScale.values,
                onChanged: onTimeScaleChanged != null
                    ? (scale) => onTimeScaleChanged!(scale as GraphTimeScale)
                    : null,
                compact: isCompact,
              ),
              SizedBox(width: isCompact ? 8 : 16),
              // Y scale selector
              _buildScaleSelector(
                colors: colors,
                label: isCompact ? 'Y:' : 'Scale:',
                value: yScale.label,
                items: GraphYScale.values,
                onChanged: onYScaleChanged != null
                    ? (scale) => onYScaleChanged!(scale as GraphYScale)
                    : null,
                compact: isCompact,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRmsStats({
    required NightshadeColors colors,
    bool compact = false,
  }) {
    final spacing = compact ? 8.0 : 16.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRmsValue(
          'RA',
          rmsRa,
          colors.error,
          colors: colors,
          compact: compact,
        ),
        SizedBox(width: spacing),
        _buildRmsValue(
          'Dec',
          rmsDec,
          colors.info,
          colors: colors,
          compact: compact,
        ),
        SizedBox(width: spacing),
        _buildRmsValue(
          'Tot',
          rmsTotal,
          colors.textPrimary,
          colors: colors,
          bold: true,
          compact: compact,
        ),
      ],
    );
  }

  Widget _buildRmsValue(
    String label,
    double value,
    Color color, {
    required NightshadeColors colors,
    bool bold = false,
    bool compact = false,
  }) {
    final fontSize = compact ? 10.0 : 12.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: fontSize,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          '${value.toStringAsFixed(2)}"',
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildScaleSelector<T>({
    required NightshadeColors colors,
    required String label,
    required String value,
    required List<T> items,
    required void Function(T)? onChanged,
    bool compact = false,
  }) {
    final fontSize = compact ? 10.0 : 12.0;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: fontSize),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<T>(
          initialValue: items.firstWhere(
            (item) => (item as dynamic).label == value,
            orElse: () => items.first,
          ),
          onSelected: onChanged,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: colors.surfaceHover,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style:
                      TextStyle(color: colors.textPrimary, fontSize: fontSize),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: colors.textPrimary,
                  size: compact ? 14 : 16,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => items.map((item) {
            return PopupMenuItem<T>(
              value: item,
              child: Text((item as dynamic).label as String),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  final NightshadeColors colors;
  final List<GuideDataPoint> data;
  final GraphTimeScale timeScale;
  final GraphYScale yScale;
  final bool showRa;
  final bool showDec;
  final bool showPulses;

  static const double leftMargin = 35;
  static const double bottomMargin = 20;
  static const double topMargin = 5;
  static const double rightMargin = 5;

  _GraphPainter({
    required this.colors,
    required this.data,
    required this.timeScale,
    required this.yScale,
    required this.showRa,
    required this.showDec,
    required this.showPulses,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final graphRect = Rect.fromLTRB(
      leftMargin,
      topMargin,
      size.width - rightMargin,
      size.height - bottomMargin,
    );

    // Draw background and grid
    _drawGrid(canvas, size, graphRect);

    // Draw Y-axis labels
    _drawYAxisLabels(canvas, graphRect);

    // Draw X-axis labels
    _drawXAxisLabels(canvas, size, graphRect);

    // Clip to graph area
    canvas.save();
    canvas.clipRect(graphRect);

    // Draw data traces
    if (data.isNotEmpty) {
      if (showRa) {
        _drawTrace(canvas, graphRect, true);
      }
      if (showDec) {
        _drawTrace(canvas, graphRect, false);
      }
    }

    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size, Rect graphRect) {
    final paint = Paint()
      ..color = colors.border.withValues(alpha: 0.8)
      ..strokeWidth = 0.5;

    // Draw vertical grid lines (time divisions)
    const numVerticalLines = 4;
    for (int i = 0; i <= numVerticalLines; i++) {
      final x = graphRect.left + (graphRect.width / numVerticalLines) * i;
      canvas.drawLine(
        Offset(x, graphRect.top),
        Offset(x, graphRect.bottom),
        paint,
      );
    }

    // Draw horizontal grid lines (error divisions)
    const numHorizontalLines = 4;
    for (int i = 0; i <= numHorizontalLines; i++) {
      final y = graphRect.top + (graphRect.height / numHorizontalLines) * i;
      // Highlight zero line
      if (i == numHorizontalLines ~/ 2) {
        paint.color = colors.borderHighlight;
        paint.strokeWidth = 1;
      } else {
        paint.color = colors.border.withValues(alpha: 0.8);
        paint.strokeWidth = 0.5;
      }
      canvas.drawLine(
        Offset(graphRect.left, y),
        Offset(graphRect.right, y),
        paint,
      );
    }
  }

  void _drawYAxisLabels(Canvas canvas, Rect graphRect) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final labels = [
      '+${yScale.arcsec.toStringAsFixed(0)}"',
      '+${(yScale.arcsec / 2).toStringAsFixed(1)}"',
      '0',
      '-${(yScale.arcsec / 2).toStringAsFixed(1)}"',
      '-${yScale.arcsec.toStringAsFixed(0)}"',
    ];

    for (int i = 0; i < labels.length; i++) {
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(color: colors.textMuted, fontSize: 9),
      );
      textPainter.layout();

      final y = graphRect.top + (graphRect.height / (labels.length - 1)) * i;
      textPainter.paint(
        canvas,
        Offset(2, y - textPainter.height / 2),
      );
    }
  }

  void _drawXAxisLabels(Canvas canvas, Size size, Rect graphRect) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final now = DateTime.now();
    const numLabels = 5;

    for (int i = 0; i < numLabels; i++) {
      final offsetMs = timeScale.duration.inMilliseconds *
          (numLabels - 1 - i) ~/
          (numLabels - 1);
      final time = now.subtract(Duration(milliseconds: offsetMs));
      final label =
          '${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(color: colors.textMuted, fontSize: 9),
      );
      textPainter.layout();

      final x = graphRect.left + (graphRect.width / (numLabels - 1)) * i;
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, graphRect.bottom + 4),
      );
    }
  }

  void _drawTrace(Canvas canvas, Rect graphRect, bool isRa) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = isRa ? colors.error : colors.info
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final now = DateTime.now();
    final startTime = now.subtract(timeScale.duration);
    bool first = true;

    for (final point in data) {
      if (point.timestamp.isBefore(startTime)) continue;

      final timeFraction =
          point.timestamp.difference(startTime).inMilliseconds /
              timeScale.duration.inMilliseconds;
      final x = graphRect.left + graphRect.width * timeFraction.clamp(0.0, 1.0);

      final error = isRa ? point.raError : point.decError;
      final errorFraction = (error / yScale.arcsec).clamp(-1.0, 1.0);
      final y = graphRect.top +
          graphRect.height / 2 -
          (errorFraction * graphRect.height / 2);

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) {
    return data != oldDelegate.data ||
        colors != oldDelegate.colors ||
        timeScale != oldDelegate.timeScale ||
        yScale != oldDelegate.yScale ||
        showRa != oldDelegate.showRa ||
        showDec != oldDelegate.showDec;
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';

/// A histogram display widget for showing image brightness distribution
class HistogramDisplay extends StatefulWidget {
  /// The histogram data (typically 256 bins for 8-bit display)
  final List<int>? histogram;

  /// Optional separate RGB histograms for color images
  final List<int>? redHistogram;
  final List<int>? greenHistogram;
  final List<int>? blueHistogram;

  /// Whether to use logarithmic scale (better for astrophotography)
  final bool logarithmic;

  /// Whether to show grid lines
  final bool showGrid;

  /// Whether to show clipping indicators
  final bool showClipping;

  /// Whether to allow toggling logarithmic mode
  final bool allowLogToggle;

  /// Height of the histogram widget
  final double height;

  /// Color for the histogram bars (used when not showing RGB)
  final Color? barColor;

  /// Callback when logarithmic mode is toggled
  final ValueChanged<bool>? onLogToggled;

  const HistogramDisplay({
    super.key,
    this.histogram,
    this.redHistogram,
    this.greenHistogram,
    this.blueHistogram,
    this.logarithmic = true,
    this.showGrid = true,
    this.showClipping = true,
    this.allowLogToggle = false,
    this.height = 60,
    this.barColor,
    this.onLogToggled,
  });

  @override
  State<HistogramDisplay> createState() => _HistogramDisplayState();
}

class _HistogramDisplayState extends State<HistogramDisplay> {
  late bool _isLogarithmic;

  @override
  void initState() {
    super.initState();
    _isLogarithmic = widget.logarithmic;
  }

  @override
  void didUpdateWidget(HistogramDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logarithmic != oldWidget.logarithmic) {
      _isLogarithmic = widget.logarithmic;
    }
  }

  bool get _hasRgbData =>
      widget.redHistogram != null &&
      widget.greenHistogram != null &&
      widget.blueHistogram != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>();
    final primaryColor = colors?.primary ?? Colors.blue;

    final effectiveHistogram = widget.histogram;
    final hasData = effectiveHistogram != null && effectiveHistogram.isNotEmpty;

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // Grid lines
          if (widget.showGrid && hasData)
            CustomPaint(
              painter: _GridPainter(
                gridColor: (colors?.border ?? Colors.grey).withValues(alpha: 0.3),
              ),
              size: Size.infinite,
            ),

          // Histogram bars
          if (hasData)
            _hasRgbData
                ? CustomPaint(
                    painter: _RgbHistogramPainter(
                      redHistogram: widget.redHistogram!,
                      greenHistogram: widget.greenHistogram!,
                      blueHistogram: widget.blueHistogram!,
                      logarithmic: _isLogarithmic,
                    ),
                    size: Size.infinite,
                  )
                : CustomPaint(
                    painter: _HistogramPainter(
                      histogram: effectiveHistogram,
                      color: widget.barColor ?? primaryColor,
                      logarithmic: _isLogarithmic,
                      showClipping: widget.showClipping,
                      clippingColor: colors?.error ?? Colors.red,
                    ),
                    size: Size.infinite,
                  )
          else
            Center(
              child: Text(
                'No data',
                style: TextStyle(
                  fontSize: 10,
                  color: colors?.textMuted ?? Colors.grey,
                ),
              ),
            ),

          // Log toggle button
          if (widget.allowLogToggle && hasData)
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isLogarithmic = !_isLogarithmic;
                  });
                  widget.onLogToggled?.call(_isLogarithmic);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _isLogarithmic ? 'LOG' : 'LIN',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: _isLogarithmic ? primaryColor : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color gridColor;

  _GridPainter({required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    // Horizontal lines (25%, 50%, 75%)
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines (at 25%, 50%, 75%)
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return gridColor != oldDelegate.gridColor;
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> histogram;
  final Color color;
  final bool logarithmic;
  final bool showClipping;
  final Color clippingColor;

  _HistogramPainter({
    required this.histogram,
    required this.color,
    required this.logarithmic,
    required this.showClipping,
    required this.clippingColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (histogram.isEmpty) return;

    final bins = histogram.length;
    if (bins == 0) return;

    // Find max value for normalization
    final maxVal = histogram.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final barWidth = size.width / bins;

    // Main histogram paint
    final paint = Paint()
      ..style = PaintingStyle.fill;

    for (int i = 0; i < bins; i++) {
      final value = histogram[i];
      double normalizedHeight;

      if (logarithmic) {
        // Logarithmic scale: log(1 + value) / log(1 + maxVal)
        normalizedHeight = value > 0
            ? math.log(1 + value) / math.log(1 + maxVal)
            : 0;
      } else {
        // Linear scale
        normalizedHeight = value / maxVal;
      }

      final barHeight = normalizedHeight * size.height;

      // Check for clipping (first or last few bins with high values)
      final isClipping = showClipping &&
          ((i < 3 && value > maxVal * 0.1) ||
           (i >= bins - 3 && value > maxVal * 0.1));

      paint.color = isClipping
          ? clippingColor.withValues(alpha: 0.8)
          : color.withValues(alpha: 0.7);

      canvas.drawRect(
        Rect.fromLTWH(
          i * barWidth,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) {
    return histogram != oldDelegate.histogram ||
        color != oldDelegate.color ||
        logarithmic != oldDelegate.logarithmic;
  }
}

class _RgbHistogramPainter extends CustomPainter {
  final List<int> redHistogram;
  final List<int> greenHistogram;
  final List<int> blueHistogram;
  final bool logarithmic;

  _RgbHistogramPainter({
    required this.redHistogram,
    required this.greenHistogram,
    required this.blueHistogram,
    required this.logarithmic,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bins = redHistogram.length;
    if (bins == 0) return;

    // Find global max for consistent scaling
    final allValues = [...redHistogram, ...greenHistogram, ...blueHistogram];
    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final barWidth = size.width / bins;

    // Draw each channel with additive blending
    _drawChannel(canvas, size, redHistogram, Colors.red.withValues(alpha: 0.5), barWidth, maxVal);
    _drawChannel(canvas, size, greenHistogram, Colors.green.withValues(alpha: 0.5), barWidth, maxVal);
    _drawChannel(canvas, size, blueHistogram, Colors.blue.withValues(alpha: 0.5), barWidth, maxVal);
  }

  void _drawChannel(Canvas canvas, Size size, List<int> histogram,
      Color color, double barWidth, int maxVal) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < histogram.length; i++) {
      final value = histogram[i];
      double normalizedHeight;

      if (logarithmic) {
        normalizedHeight = value > 0
            ? math.log(1 + value) / math.log(1 + maxVal)
            : 0;
      } else {
        normalizedHeight = value / maxVal;
      }

      final barHeight = normalizedHeight * size.height;

      canvas.drawRect(
        Rect.fromLTWH(
          i * barWidth,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RgbHistogramPainter oldDelegate) {
    return redHistogram != oldDelegate.redHistogram ||
        greenHistogram != oldDelegate.greenHistogram ||
        blueHistogram != oldDelegate.blueHistogram ||
        logarithmic != oldDelegate.logarithmic;
  }
}

/// A compact histogram display for use in overlays
class CompactHistogramDisplay extends StatelessWidget {
  final List<int>? histogram;
  final double width;
  final double height;
  final Color? barColor;
  final String? title;

  const CompactHistogramDisplay({
    super.key,
    this.histogram,
    this.width = 200,
    this.height = 60,
    this.barColor,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>();

    return Container(
      width: width,
      height: height + (title != null ? 20 : 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: colors?.textMuted ?? Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: HistogramDisplay(
              histogram: histogram,
              height: height - 16,
              barColor: barColor,
              logarithmic: true,
              showGrid: false,
              showClipping: true,
              allowLogToggle: false,
            ),
          ),
        ],
      ),
    );
  }
}

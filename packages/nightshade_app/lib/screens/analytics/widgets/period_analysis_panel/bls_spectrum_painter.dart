part of '../period_analysis_panel.dart';

/// Paints the BLS SR spectrum (SR vs trial period).
class _BlsSpectrumPainter extends StatelessWidget {
  final NightshadeColors colors;
  final List<double> trialPeriods;
  final List<double> srSpectrum;
  final double bestPeriod;

  const _BlsSpectrumPainter({
    required this.colors,
    required this.trialPeriods,
    required this.srSpectrum,
    required this.bestPeriod,
  });

  @override
  Widget build(BuildContext context) {
    if (trialPeriods.isEmpty) {
      return Center(
        child: Text(
          'No BLS data',
          style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize12),
        ),
      );
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _BlsSpectrumCustomPainter(
        trialPeriods: trialPeriods,
        srSpectrum: srSpectrum,
        bestPeriod: bestPeriod,
        plotColor: NightshadeChartColors.seriesGreen,
        peakColor: NightshadeChartColors.seriesAmber,
        borderColor: colors.border,
        textColor: colors.textSecondary,
        gridColor: colors.border.withValues(alpha: 0.3),
      ),
    );
  }
}

class _BlsSpectrumCustomPainter extends CustomPainter {
  final List<double> trialPeriods;
  final List<double> srSpectrum;
  final double bestPeriod;
  final Color plotColor;
  final Color peakColor;
  final Color borderColor;
  final Color textColor;
  final Color gridColor;

  _BlsSpectrumCustomPainter({
    required this.trialPeriods,
    required this.srSpectrum,
    required this.bestPeriod,
    required this.plotColor,
    required this.peakColor,
    required this.borderColor,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trialPeriods.isEmpty) return;

    const leftMargin = 45.0;
    const bottomMargin = 28.0;
    const topMargin = 8.0;
    const rightMargin = 12.0;
    final plotWidth = size.width - leftMargin - rightMargin;
    final plotHeight = size.height - topMargin - bottomMargin;
    final plotRect =
        Rect.fromLTWH(leftMargin, topMargin, plotWidth, plotHeight);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plotRect, borderPaint);

    // Use log scale for period axis.
    final logMinP = math.log(trialPeriods.first);
    final logMaxP = math.log(trialPeriods.last);
    final logRange = logMaxP - logMinP;
    if (logRange <= 0) return;

    var maxSr = 0.0;
    for (final sr in srSpectrum) {
      if (sr > maxSr) maxSr = sr;
    }
    if (maxSr <= 0) maxSr = 1.0;
    final srRange = maxSr * 1.1;

    // Grid.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final y = plotRect.top + plotHeight * (1.0 - i / 4.0);
      canvas.drawLine(
          Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
    }

    // Axis labels.
    final textStyle =
        TextStyle(color: textColor, fontSize: NightshadeTypography.fontSize9);

    // Y-axis.
    for (var i = 0; i <= 4; i++) {
      final value = srRange * i / 4.0;
      final y = plotRect.bottom - (i / 4.0) * plotHeight;
      final tp = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(1), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotRect.left - tp.width - 4, y - tp.height / 2));
    }

    // X-axis: log-spaced period labels.
    for (var i = 0; i <= 4; i++) {
      final logVal = logMinP + logRange * i / 4.0;
      final period = math.exp(logVal);
      final x = plotRect.left + plotWidth * i / 4.0;
      final label = period < 1
          ? '${(period * 24).toStringAsFixed(1)}h'
          : '${period.toStringAsFixed(1)}d';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, plotRect.bottom + 4));
    }

    final xLabelPainter = TextPainter(
      text: TextSpan(text: 'Period', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    xLabelPainter.paint(
      canvas,
      Offset(
        plotRect.left + plotWidth / 2 - xLabelPainter.width / 2,
        plotRect.bottom + 16,
      ),
    );

    // Draw the SR spectrum.
    final linePaint = Paint()
      ..color = plotColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    final step = math.max(1, trialPeriods.length ~/ plotWidth.toInt());
    final path = Path();
    var first = true;
    for (var i = 0; i < trialPeriods.length; i += step) {
      final logP = math.log(trialPeriods[i]);
      final x = plotRect.left + (logP - logMinP) / logRange * plotWidth;
      final y = plotRect.bottom - (srSpectrum[i] / srRange) * plotHeight;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    // Mark best period.
    final bestLogP = math.log(bestPeriod);
    final bestX = plotRect.left + (bestLogP - logMinP) / logRange * plotWidth;
    final peakPaint = Paint()
      ..color = peakColor
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(bestX, plotRect.top),
      Offset(bestX, plotRect.bottom),
      peakPaint,
    );

    final peakLabel = TextPainter(
      text: TextSpan(
        text:
            'P=${bestPeriod < 1 ? '${(bestPeriod * 24).toStringAsFixed(2)}h' : '${bestPeriod.toStringAsFixed(3)}d'}',
        style: TextStyle(
            color: peakColor,
            fontSize: NightshadeTypography.fontSize9,
            fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelX =
        (bestX + 4).clamp(plotRect.left, plotRect.right - peakLabel.width);
    peakLabel.paint(canvas, Offset(labelX, plotRect.top + 2));
  }

  @override
  bool shouldRepaint(covariant _BlsSpectrumCustomPainter oldDelegate) {
    return oldDelegate.trialPeriods != trialPeriods ||
        oldDelegate.srSpectrum != srSpectrum ||
        oldDelegate.bestPeriod != bestPeriod;
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Panel that provides Lomb-Scargle and BLS period detection analysis
/// for variable star and exoplanet transit detection.
class PeriodAnalysisPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final List<LightCurvePoint> lightCurve;

  const PeriodAnalysisPanel({
    super.key,
    required this.colors,
    required this.lightCurve,
  });

  @override
  ConsumerState<PeriodAnalysisPanel> createState() =>
      _PeriodAnalysisPanelState();
}

class _PeriodAnalysisPanelState extends ConsumerState<PeriodAnalysisPanel> {
  final _customPeriodController = TextEditingController();
  double _minPeriod = 0.01;
  double _maxPeriod = 10.0;

  @override
  void dispose() {
    _customPeriodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(periodAnalysisProvider);
    final colors = widget.colors;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(LucideIcons.activity, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Period Analysis',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (analysisState.result != null)
                  Tooltip(
                    message: 'Clear results',
                    child: InkWell(
                      onTap: () =>
                          ref.read(periodAnalysisProvider.notifier).clear(),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(LucideIcons.x,
                            size: 14, color: colors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Controls row
            _buildControls(colors, analysisState),
            const SizedBox(height: 16),

            // Results
            if (analysisState.isRunning)
              SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Computing periodograms...',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else if (analysisState.error != null)
              _buildError(colors, analysisState.error!)
            else if (analysisState.result != null)
              _buildResults(colors, analysisState)
            else
              _buildEmptyState(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(
      NightshadeColors colors, PeriodAnalysisState analysisState) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    'Min period (d):',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    height: 28,
                    child: TextField(
                      controller: TextEditingController(
                          text: _minPeriod.toStringAsFixed(3)),
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: colors.border),
                        ),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null && parsed > 0) {
                          _minPeriod = parsed;
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Text(
                    'Max period (d):',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    height: 28,
                    child: TextField(
                      controller: TextEditingController(
                          text: _maxPeriod.toStringAsFixed(1)),
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: colors.border),
                        ),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null && parsed > 0) {
                          _maxPeriod = parsed;
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            NightshadeButton(
              label: 'Run Period Search',
              icon: LucideIcons.search,
              size: ButtonSize.small,
              onPressed: analysisState.isRunning
                  ? null
                  : () {
                      ref.read(periodAnalysisProvider.notifier).runAnalysis(
                            lightCurve: widget.lightCurve,
                            config: PeriodAnalysisConfig(
                              minPeriodDays: _minPeriod,
                              maxPeriodDays: _maxPeriod,
                            ),
                          );
                    },
            ),
          ],
        ),
        if (analysisState.result != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Custom period (d):',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 28,
                child: TextField(
                  controller: _customPeriodController,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. 1.234',
                    hintStyle: TextStyle(color: colors.textMuted, fontSize: 11),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: colors.border),
                    ),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NightshadeButton(
                label: 'Fold',
                size: ButtonSize.small,
                onPressed: () {
                  final period = double.tryParse(_customPeriodController.text);
                  if (period != null && period > 0) {
                    ref.read(periodAnalysisProvider.notifier).setCustomPeriod(
                          periodDays: period,
                          lightCurve: widget.lightCurve,
                        );
                  }
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildError(NightshadeColors colors, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(NightshadeColors colors) {
    final pointCount = widget.lightCurve.length;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.activity, size: 24, color: colors.textMuted),
            const SizedBox(height: 8),
            Text(
              pointCount < 10
                  ? 'Need at least 10 photometry points ($pointCount available)'
                  : 'Click "Run Period Search" to analyze $pointCount data points',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(
      NightshadeColors colors, PeriodAnalysisState analysisState) {
    final result = analysisState.result!;
    final ls = result.lombScargle;
    final bls = result.bls;

    // Phase fold at the best LS period by default.
    final service = ref.read(periodAnalysisServiceProvider);
    final lsPhaseFold = service.phaseFold(
      points: widget.lightCurve,
      periodDays: ls.bestPeriod,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Best period summary
        _buildPeriodSummary(colors, ls, bls),
        const SizedBox(height: 16),

        // Lomb-Scargle power spectrum
        Text(
          'Lomb-Scargle Periodogram',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: _PeriodogramPainter(
            colors: colors,
            frequencies: ls.frequencies,
            powers: ls.powers,
            bestFrequency: ls.bestFrequency,
            plotColor: const Color(0xFF60A5FA),
            peakColor: const Color(0xFFF59E0B),
            xLabel: 'Frequency (1/day)',
            yLabel: 'Power',
          ),
        ),
        const SizedBox(height: 16),

        // Phase-folded light curve at best LS period
        Text(
          'Phase-Folded Light Curve (P = ${_formatPeriod(ls.bestPeriod)})',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: _PhaseFoldPainter(
            colors: colors,
            points: lsPhaseFold,
            plotColor: const Color(0xFF60A5FA),
          ),
        ),
        const SizedBox(height: 16),

        // BLS results
        _buildBlsSection(colors, bls),

        // Custom phase fold (if set)
        if (analysisState.customPhaseFold != null &&
            analysisState.customPeriodDays != null) ...[
          const SizedBox(height: 16),
          Text(
            'Custom Phase Fold (P = ${_formatPeriod(analysisState.customPeriodDays!)})',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _PhaseFoldPainter(
              colors: colors,
              points: analysisState.customPhaseFold!,
              plotColor: const Color(0xFFA78BFA),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPeriodSummary(
      NightshadeColors colors, LombScargleResult ls, BlsResult bls) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ResultColumn(
              colors: colors,
              label: 'Lomb-Scargle Best Period',
              value: _formatPeriod(ls.bestPeriod),
              detail:
                  'Peak power: ${ls.peakPower.toStringAsFixed(2)}  |  FAP: ${_formatFap(ls.falseAlarmProbability)}',
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: colors.border,
          ),
          Expanded(
            child: _ResultColumn(
              colors: colors,
              label: 'BLS Best Period',
              value: _formatPeriod(bls.bestPeriod),
              detail:
                  'Depth: ${(bls.transitDepth * 1000).toStringAsFixed(1)} mmag  |  SDE: ${bls.signalDetectionEfficiency.toStringAsFixed(1)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlsSection(NightshadeColors colors, BlsResult bls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Box Least Squares (Transit Search)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        // BLS SR spectrum
        SizedBox(
          height: 180,
          child: _BlsSpectrumPainter(
            colors: colors,
            trialPeriods: bls.trialPeriods,
            srSpectrum: bls.srSpectrum,
            bestPeriod: bls.bestPeriod,
          ),
        ),
        const SizedBox(height: 8),
        // BLS detail stats
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _BlsStat(
                colors: colors,
                label: 'Period',
                value: _formatPeriod(bls.bestPeriod)),
            _BlsStat(
                colors: colors,
                label: 'Duration',
                value: _formatDuration(bls.transitDuration)),
            _BlsStat(
                colors: colors,
                label: 'Depth',
                value: '${(bls.transitDepth * 1000).toStringAsFixed(1)} mmag'),
            _BlsStat(
                colors: colors,
                label: 'SDE',
                value: bls.signalDetectionEfficiency.toStringAsFixed(2)),
            _BlsStat(
                colors: colors,
                label: 'Mid-phase',
                value: bls.transitMidPhase.toStringAsFixed(3)),
          ],
        ),
      ],
    );
  }

  String _formatPeriod(double periodDays) {
    if (periodDays < 1.0) {
      final hours = periodDays * 24.0;
      if (hours < 1.0) {
        final minutes = hours * 60.0;
        return '${minutes.toStringAsFixed(1)} min';
      }
      return '${hours.toStringAsFixed(2)} hr';
    }
    return '${periodDays.toStringAsFixed(4)} d';
  }

  String _formatDuration(double durationDays) {
    final hours = durationDays * 24.0;
    if (hours < 1.0) {
      return '${(hours * 60.0).toStringAsFixed(1)} min';
    }
    return '${hours.toStringAsFixed(2)} hr';
  }

  String _formatFap(double fap) {
    if (fap < 1e-10) return '< 1e-10';
    if (fap < 0.001) return fap.toStringAsExponential(1);
    return fap.toStringAsFixed(4);
  }
}

class _ResultColumn extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final String detail;

  const _ResultColumn({
    required this.colors,
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BlsStat extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;

  const _BlsStat({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 10),
        ),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Custom painters for the periodogram and phase-fold plots
// =============================================================================

/// Paints the Lomb-Scargle power spectrum.
class _PeriodogramPainter extends StatelessWidget {
  final NightshadeColors colors;
  final List<double> frequencies;
  final List<double> powers;
  final double bestFrequency;
  final Color plotColor;
  final Color peakColor;
  final String xLabel;
  final String yLabel;

  const _PeriodogramPainter({
    required this.colors,
    required this.frequencies,
    required this.powers,
    required this.bestFrequency,
    required this.plotColor,
    required this.peakColor,
    required this.xLabel,
    required this.yLabel,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _PeriodogramCustomPainter(
        frequencies: frequencies,
        powers: powers,
        bestFrequency: bestFrequency,
        plotColor: plotColor,
        peakColor: peakColor,
        borderColor: colors.border,
        textColor: colors.textSecondary,
        gridColor: colors.border.withValues(alpha: 0.3),
        xLabel: xLabel,
        yLabel: yLabel,
      ),
    );
  }
}

class _PeriodogramCustomPainter extends CustomPainter {
  final List<double> frequencies;
  final List<double> powers;
  final double bestFrequency;
  final Color plotColor;
  final Color peakColor;
  final Color borderColor;
  final Color textColor;
  final Color gridColor;
  final String xLabel;
  final String yLabel;

  _PeriodogramCustomPainter({
    required this.frequencies,
    required this.powers,
    required this.bestFrequency,
    required this.plotColor,
    required this.peakColor,
    required this.borderColor,
    required this.textColor,
    required this.gridColor,
    required this.xLabel,
    required this.yLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frequencies.isEmpty || powers.isEmpty) return;

    const leftMargin = 45.0;
    const bottomMargin = 28.0;
    const topMargin = 8.0;
    const rightMargin = 12.0;
    final plotWidth = size.width - leftMargin - rightMargin;
    final plotHeight = size.height - topMargin - bottomMargin;
    final plotRect =
        Rect.fromLTWH(leftMargin, topMargin, plotWidth, plotHeight);

    // Draw border.
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plotRect, borderPaint);

    // Compute data range.
    final minFreq = frequencies.first;
    final maxFreq = frequencies.last;
    final freqRange = maxFreq - minFreq;
    if (freqRange <= 0) return;

    var maxPower = 0.0;
    for (final p in powers) {
      if (p > maxPower) maxPower = p;
    }
    if (maxPower <= 0) maxPower = 1.0;
    final powerRange = maxPower * 1.1; // 10% headroom.

    // Draw grid lines.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final y = plotRect.top + plotHeight * (1.0 - i / 4.0);
      canvas.drawLine(
          Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
    }
    for (var i = 1; i < 5; i++) {
      final x = plotRect.left + plotWidth * i / 5.0;
      canvas.drawLine(
          Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
    }

    // Draw axis labels.
    _drawAxisLabels(canvas, plotRect, minFreq, maxFreq, maxPower);

    // Down-sample for rendering if there are too many points.
    final step = math.max(1, frequencies.length ~/ plotWidth.toInt());

    // Draw the power spectrum line.
    final linePaint = Paint()
      ..color = plotColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    final path = Path();
    var first = true;
    for (var i = 0; i < frequencies.length; i += step) {
      final x =
          plotRect.left + (frequencies[i] - minFreq) / freqRange * plotWidth;
      final y = plotRect.bottom - (powers[i] / powerRange) * plotHeight;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    // Mark the best frequency with a vertical line.
    final bestX =
        plotRect.left + (bestFrequency - minFreq) / freqRange * plotWidth;
    final peakPaint = Paint()
      ..color = peakColor
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(bestX, plotRect.top),
      Offset(bestX, plotRect.bottom),
      peakPaint,
    );

    // Draw a small label at the peak.
    final peakLabel = TextPainter(
      text: TextSpan(
        text: 'P=${(1.0 / bestFrequency).toStringAsFixed(3)}d',
        style: TextStyle(
            color: peakColor, fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelX =
        (bestX + 4).clamp(plotRect.left, plotRect.right - peakLabel.width);
    peakLabel.paint(canvas, Offset(labelX, plotRect.top + 2));
  }

  void _drawAxisLabels(Canvas canvas, Rect plotRect, double minFreq,
      double maxFreq, double maxPower) {
    final textStyle = TextStyle(color: textColor, fontSize: 9);

    // Y-axis labels.
    for (var i = 0; i <= 4; i++) {
      final value = maxPower * 1.1 * i / 4.0;
      final y = plotRect.bottom - (i / 4.0) * plotRect.height;
      final tp = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(1), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotRect.left - tp.width - 4, y - tp.height / 2));
    }

    // X-axis labels.
    for (var i = 0; i <= 4; i++) {
      final value = minFreq + (maxFreq - minFreq) * i / 4.0;
      final x = plotRect.left + plotRect.width * i / 4.0;
      final tp = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(1), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, plotRect.bottom + 4));
    }

    // Axis names.
    final xLabelPainter = TextPainter(
      text: TextSpan(text: xLabel, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    xLabelPainter.paint(
      canvas,
      Offset(
        plotRect.left + plotRect.width / 2 - xLabelPainter.width / 2,
        plotRect.bottom + 16,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _PeriodogramCustomPainter oldDelegate) {
    return oldDelegate.frequencies != frequencies ||
        oldDelegate.powers != powers ||
        oldDelegate.bestFrequency != bestFrequency;
  }
}

/// Paints a phase-folded light curve.
class _PhaseFoldPainter extends StatelessWidget {
  final NightshadeColors colors;
  final List<PhaseFoldedPoint> points;
  final Color plotColor;

  const _PhaseFoldPainter({
    required this.colors,
    required this.points,
    required this.plotColor,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          'No data to display',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      );
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _PhaseFoldCustomPainter(
        points: points,
        plotColor: plotColor,
        borderColor: colors.border,
        textColor: colors.textSecondary,
        gridColor: colors.border.withValues(alpha: 0.3),
      ),
    );
  }
}

class _PhaseFoldCustomPainter extends CustomPainter {
  final List<PhaseFoldedPoint> points;
  final Color plotColor;
  final Color borderColor;
  final Color textColor;
  final Color gridColor;

  _PhaseFoldCustomPainter({
    required this.points,
    required this.plotColor,
    required this.borderColor,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftMargin = 50.0;
    const bottomMargin = 28.0;
    const topMargin = 8.0;
    const rightMargin = 12.0;
    final plotWidth = size.width - leftMargin - rightMargin;
    final plotHeight = size.height - topMargin - bottomMargin;
    final plotRect =
        Rect.fromLTWH(leftMargin, topMargin, plotWidth, plotHeight);

    // Border.
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plotRect, borderPaint);

    // Compute magnitude range. Note: magnitudes are inverted (brighter = lower number).
    var minMag = points.first.magnitude;
    var maxMag = points.first.magnitude;
    for (final p in points) {
      if (p.magnitude < minMag) minMag = p.magnitude;
      if (p.magnitude > maxMag) maxMag = p.magnitude;
    }
    final magRange = math.max(0.01, maxMag - minMag);
    final displayMin = minMag - magRange * 0.15;
    final displayMax = maxMag + magRange * 0.15;
    final displayRange = displayMax - displayMin;

    // Grid.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final y = plotRect.top + plotHeight * i / 4.0;
      canvas.drawLine(
          Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
    }
    for (var i = 1; i < 5; i++) {
      final x = plotRect.left + plotWidth * i / 5.0;
      canvas.drawLine(
          Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
    }

    // Axis labels.
    final textStyle = TextStyle(color: textColor, fontSize: 9);

    // Y-axis (inverted — brighter at top, so displayMax at top and displayMin at bottom).
    for (var i = 0; i <= 4; i++) {
      // Inverted: top of plot = displayMin (brightest), bottom = displayMax (faintest).
      final value = displayMax - (displayRange * i / 4.0);
      final y = plotRect.top + plotHeight * (1.0 - i / 4.0);
      final tp = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(3), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotRect.left - tp.width - 4, y - tp.height / 2));
    }

    // X-axis (phase 0 to 1).
    for (var i = 0; i <= 5; i++) {
      final phase = i / 5.0;
      final x = plotRect.left + plotWidth * phase;
      final tp = TextPainter(
        text: TextSpan(text: phase.toStringAsFixed(1), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, plotRect.bottom + 4));
    }

    // Phase label.
    final phaseLabelPainter = TextPainter(
      text: TextSpan(text: 'Phase', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    phaseLabelPainter.paint(
      canvas,
      Offset(
        plotRect.left + plotWidth / 2 - phaseLabelPainter.width / 2,
        plotRect.bottom + 16,
      ),
    );

    // Draw error bars and data points.
    final dotPaint = Paint()
      ..color = plotColor
      ..style = PaintingStyle.fill;
    final errorPaint = Paint()
      ..color = plotColor.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;

    for (final point in points) {
      final x = plotRect.left + point.phase * plotWidth;
      // Inverted Y: lower magnitude = higher on screen.
      final yNorm = (point.magnitude - displayMin) / displayRange;
      final y = plotRect.top + yNorm * plotHeight;

      // Error bar.
      final errPixels = (point.uncertainty / displayRange) * plotHeight;
      canvas.drawLine(
          Offset(x, y - errPixels), Offset(x, y + errPixels), errorPaint);

      // Data point.
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PhaseFoldCustomPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.plotColor != plotColor;
  }
}

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
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      );
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _BlsSpectrumCustomPainter(
        trialPeriods: trialPeriods,
        srSpectrum: srSpectrum,
        bestPeriod: bestPeriod,
        plotColor: const Color(0xFF34D399),
        peakColor: const Color(0xFFF59E0B),
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
    final textStyle = TextStyle(color: textColor, fontSize: 9);

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
            color: peakColor, fontSize: 9, fontWeight: FontWeight.w600),
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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'adaptive_chart_container.dart';

part 'period_analysis_panel/result_widgets.dart';
part 'period_analysis_panel/periodogram_painter.dart';
part 'period_analysis_panel/phase_fold_painter.dart';
part 'period_analysis_panel/bls_spectrum_painter.dart';

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
                      fontSize: NightshadeTypography.fontSize15,
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
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline8),
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
              AdaptiveChartContainer.fixed(
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
                            color: colors.textSecondary,
                            fontSize: NightshadeTypography.fontSize12),
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
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: NightshadeTypography.fontSize12),
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
                          fontSize: NightshadeTypography.fontSize12,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                NightshadeTokens.radiusInline4)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline4),
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
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: NightshadeTypography.fontSize12),
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
                          fontSize: NightshadeTypography.fontSize12,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                NightshadeTokens.radiusInline4)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline4),
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
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize12),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 28,
                child: TextField(
                  controller: _customPeriodController,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: NightshadeTypography.fontSize12,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. 1.234',
                    hintStyle: TextStyle(
                        color: colors.textMuted,
                        fontSize: NightshadeTypography.fontSize11),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline4)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline4),
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                  color: colors.error,
                  fontSize: NightshadeTypography.fontSize12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(NightshadeColors colors) {
    final pointCount = widget.lightCurve.length;
    return AdaptiveChartContainer.fixed(
      height: 120,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        AdaptiveChartContainer(
          preferredHeight: 200,
          child: _PeriodogramPainter(
            colors: colors,
            frequencies: ls.frequencies,
            powers: ls.powers,
            bestFrequency: ls.bestFrequency,
            plotColor: NightshadeChartColors.seriesBlue,
            peakColor: NightshadeChartColors.seriesAmber,
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
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        AdaptiveChartContainer(
          preferredHeight: 200,
          child: _PhaseFoldPainter(
            colors: colors,
            points: lsPhaseFold,
            plotColor: NightshadeChartColors.seriesBlue,
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
              fontSize: NightshadeTypography.fontSize13,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          AdaptiveChartContainer(
            preferredHeight: 200,
            child: _PhaseFoldPainter(
              colors: colors,
              points: analysisState.customPhaseFold!,
              plotColor: NightshadeChartColors.seriesViolet,
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        // BLS SR spectrum
        AdaptiveChartContainer(
          preferredHeight: 180,
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

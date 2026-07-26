import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import 'adaptive_chart_container.dart';

part 'period_analysis_panel/result_widgets.dart';
part 'period_analysis_panel/periodogram_painter.dart';
part 'period_analysis_panel/phase_fold_painter.dart';
part 'period_analysis_panel/bls_spectrum_painter.dart';

const _kPeriodAnalysisInfo = '''
Period analysis searches your light curve for a repeating signal — the rotation period of a variable star, the orbital period of an eclipsing binary, or the period of a transiting exoplanet. Nightshade runs two complementary algorithms.

Lomb-Scargle is a frequency-domain method that finds sinusoidal periodicity, well suited to smoothly varying stars (pulsators, spotted rotators). Box Least Squares (BLS) instead fits a flat-bottomed box dip and is the standard tool for finding the brief, periodic dimming of a planetary transit.

The False Alarm Probability (FAP) reported for the Lomb-Scargle peak is the chance that noise alone would produce a peak this strong. FAP < 0.01 is a significant detection; FAP < 0.001 is a strong one.

For BLS, the Signal Detection Efficiency (SDE) measures how far the best period stands above the surrounding spectrum. SDE > 6 is noteworthy; SDE > 7 is a strong transit candidate worth following up.

The phase-folded plots wrap every data point onto a single cycle at the best period, so a real signal collapses into a clean shape. As with all photometry charts here, magnitude is inverted — brighter points sit higher on the plot.
''';

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
  double _minPeriod = 0.01;
  double _maxPeriod = 10.0;
  late final _minPeriodController =
      TextEditingController(text: _minPeriod.toStringAsFixed(3));
  late final _maxPeriodController =
      TextEditingController(text: _maxPeriod.toStringAsFixed(1));
  final _customPeriodController = TextEditingController();

  @override
  void dispose() {
    _minPeriodController.dispose();
    _maxPeriodController.dispose();
    _customPeriodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(periodAnalysisProvider);
    final colors = widget.colors;

    return NightshadeCard(
      child: Padding(
        padding: NightshadeTokens.paddingLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(LucideIcons.activity,
                    size: NightshadeTokens.iconSm, color: colors.primary),
                const SizedBox(width: NightshadeTokens.spaceSm),
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
                const ScienceInfoButton(
                  title: 'Period Analysis',
                  body: _kPeriodAnalysisInfo,
                ),
                if (analysisState.result != null)
                  Tooltip(
                    message: 'Clear results',
                    child: InkWell(
                      onTap: () =>
                          ref.read(periodAnalysisProvider.notifier).clear(),
                      borderRadius: NightshadeTokens.borderRadiusLg,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: NightshadeTokens.minTouchTarget,
                          minHeight: NightshadeTokens.minTouchTarget,
                        ),
                        alignment: Alignment.center,
                        child: Icon(LucideIcons.x,
                            size: NightshadeTokens.iconXs,
                            color: colors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),

            // Controls row
            _buildControls(colors, analysisState),
            const SizedBox(height: NightshadeTokens.spaceLg),

            // Results
            if (analysisState.isRunning)
              AdaptiveChartContainer.fixed(
                height: 200,
                child: ShimmerLoading(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: NightshadeTokens.borderRadiusLg,
                      border: Border.all(color: colors.border),
                    ),
                    padding: NightshadeTokens.paddingLg,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SkeletonBox(width: 160, height: 12),
                        SizedBox(height: NightshadeTokens.spaceMd),
                        Expanded(child: SkeletonBox(height: double.infinity)),
                      ],
                    ),
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

  Widget _buildPeriodField({
    required TextEditingController controller,
    ValueChanged<String>? onChanged,
    double width = 70,
  }) {
    return SizedBox(
      width: width,
      child: NightshadeTextField(
        controller: controller,
        hint: width >= 100 ? 'e.g. 1.234' : null,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildControls(
      NightshadeColors colors, PeriodAnalysisState analysisState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 1080;

        final minField = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Min period (d):',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            _buildPeriodField(
              controller: _minPeriodController,
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null && parsed > 0) {
                  _minPeriod = parsed;
                }
              },
            ),
          ],
        );

        final maxField = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Max period (d):',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            _buildPeriodField(
              controller: _maxPeriodController,
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null && parsed > 0) {
                  _maxPeriod = parsed;
                }
              },
            ),
          ],
        );

        Widget runButton = NightshadeButton(
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
        );
        if (stacked) {
          runButton = SizedBox(width: double.infinity, child: runButton);
        }

        final controlBar = stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  minField,
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  maxField,
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  runButton,
                ],
              )
            : Row(
                children: [
                  Expanded(child: minField),
                  const SizedBox(width: NightshadeTokens.spaceLg),
                  Expanded(child: maxField),
                  const SizedBox(width: NightshadeTokens.spaceLg),
                  runButton,
                ],
              );

        if (analysisState.result == null) return controlBar;

        final customLabel = Text(
          'Custom period (d):',
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize12),
        );
        final customField = _buildPeriodField(
          controller: _customPeriodController,
          width: 100,
        );
        Widget foldButton = NightshadeButton(
          label: 'Fold',
          size: ButtonSize.small,
          onPressed: () {
            final period = double.tryParse(_customPeriodController.text);
            if (period != null && period > 0) {
              ref.read(periodAnalysisProvider.notifier).setCustomPeriod(
                    periodDays: period,
                    lightCurve: widget.lightCurve,
                  );
            } else {
              context
                  .showErrorSnackBar('Enter a period in days greater than 0');
            }
          },
        );
        if (stacked) {
          foldButton = SizedBox(width: double.infinity, child: foldButton);
        }

        final customRow = stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      customLabel,
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      Expanded(child: customField),
                    ],
                  ),
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  foldButton,
                ],
              )
            : Row(
                children: [
                  customLabel,
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  customField,
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  foldButton,
                ],
              );

        return Column(
          children: [
            controlBar,
            const SizedBox(height: NightshadeTokens.spaceSm),
            customRow,
          ],
        );
      },
    );
  }

  Widget _buildError(NightshadeColors colors, String error) {
    return Container(
      padding: NightshadeTokens.paddingMd,
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.1),
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle,
              size: NightshadeTokens.iconSm, color: colors.error),
          const SizedBox(width: NightshadeTokens.spaceSm),
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
    final tooFew = pointCount < 10;
    return AdaptiveChartContainer.fixed(
      // The guidance body needs more vertical room than the ready-to-run
      // prompt. At 120px the compact empty state had only 94px after padding
      // and border, so its icon, wrapped title, and body overflowed in valid
      // early-session layouts.
      height: tooFew ? 190 : 120,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: NightshadeTokens.borderRadiusLg,
          border: Border.all(color: colors.border),
        ),
        child: EmptyState.compact(
          icon: LucideIcons.activity,
          title: tooFew
              ? 'Need at least 10 photometry points ($pointCount available)'
              : 'Click "Run Period Search" to analyze $pointCount data points',
          body: tooFew
              ? 'Pick a target star in the Differential Photometry chart and capture more frames.'
              : null,
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
        const SizedBox(height: NightshadeTokens.spaceLg),

        // Lomb-Scargle power spectrum
        Text(
          'Lomb-Scargle Periodogram',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
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
        const SizedBox(height: NightshadeTokens.spaceLg),

        // Phase-folded light curve at best LS period
        Text(
          'Phase-Folded Light Curve (P = ${_formatPeriod(ls.bestPeriod)})',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        AdaptiveChartContainer(
          preferredHeight: 200,
          child: _PhaseFoldPainter(
            colors: colors,
            points: lsPhaseFold,
            plotColor: NightshadeChartColors.seriesBlue,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),

        // BLS results
        _buildBlsSection(colors, bls),

        // Custom phase fold (if set)
        if (analysisState.customPhaseFold != null &&
            analysisState.customPeriodDays != null) ...[
          const SizedBox(height: NightshadeTokens.spaceLg),
          Text(
            'Custom Phase Fold (P = ${_formatPeriod(analysisState.customPeriodDays!)})',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: NightshadeTypography.fontSize13,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
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
    final fap = ls.falseAlarmProbability;
    final _Verdict? lsVerdict = fap < 0.001
        ? _Verdict.strong
        : fap < 0.01
            ? _Verdict.significant
            : null;
    final sde = bls.signalDetectionEfficiency;
    final _Verdict? blsVerdict = sde > 7
        ? _Verdict.strong
        : sde > 6
            ? _Verdict.noteworthy
            : null;

    final lsColumn = _ResultColumn(
      colors: colors,
      label: 'Lomb-Scargle Best Period',
      value: _formatPeriod(ls.bestPeriod),
      detail:
          'Peak power: ${ls.peakPower.toStringAsFixed(2)}  |  FAP: ${_formatFap(fap)}',
      verdict: lsVerdict,
    );
    final blsColumn = _ResultColumn(
      colors: colors,
      label: 'BLS Best Period',
      value: _formatPeriod(bls.bestPeriod),
      detail:
          'Depth: ${(bls.transitDepth * 1000).toStringAsFixed(1)} mmag  |  SDE: ${sde.toStringAsFixed(1)}',
      verdict: blsVerdict,
    );

    return Container(
      padding: NightshadeTokens.paddingMd,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.06),
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 1080) {
            return Column(
              children: [
                lsColumn,
                Divider(
                    height: NightshadeTokens.space2xl, color: colors.border),
                blsColumn,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: lsColumn),
              Container(
                width: 1,
                height: 40,
                color: colors.border,
              ),
              Expanded(child: blsColumn),
            ],
          );
        },
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
        const SizedBox(height: NightshadeTokens.spaceSm),
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
        const SizedBox(height: NightshadeTokens.spaceSm),
        // BLS detail stats
        Wrap(
          spacing: NightshadeTokens.space2xl,
          runSpacing: NightshadeTokens.spaceSm,
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

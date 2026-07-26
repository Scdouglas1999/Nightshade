// Part of ../polar_alignment_screen.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../polar_alignment_screen.dart';

extension _RightPanel on _PolarAlignmentScreenState {
  Widget _buildRightPanel(
    NightshadeColors colors,
    PolarAlignmentState state,
    PolarAlignmentConfig config,
  ) {
    final errorHistory = ref.watch(polarAlignmentErrorHistoryProvider);
    final isAllSky = ref.watch(polarAlignmentUiStateProvider).mode ==
        PolarAlignmentMode.allSky;

    // Error visualization
    //
    // All-Sky mode shows the Sharpcap-style target reticle with a live
    // moving marker; TPPA mode keeps the legacy bar/dial visualization.
    final Widget visualization = isAllSky
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AllSkyTargetReticle(
                azimuthErrorArcsec: state.currentError?.azimuthError ?? 0.0,
                altitudeErrorArcsec: state.currentError?.altitudeError ?? 0.0,
                acceptanceThresholdArcsec: config.autoCompleteThreshold,
                waitingForFirstFrame:
                    state.phase == PolarAlignPhase.adjusting &&
                        state.currentError == null,
              ),
            ),
          )
        : Stack(
            alignment: Alignment.center,
            children: [
              _PolarErrorVisualization(
                colors: colors,
                error: state.currentError,
                phase: state.phase,
                pulseAnimation: _pulseController,
              ),
              if (state.phase == PolarAlignPhase.idle)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Text(
                    'After you start, this bullseye shows live '
                    'azimuth and altitude error while you adjust the '
                    'mount. Rings mark 30", 60", and 120" error zones.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          );

    // Task 4.5: Error trend sparkline chart (only in adjustment phase)
    final Widget? trendChart =
        (state.phase == PolarAlignPhase.adjusting && errorHistory.length > 2)
            ? Container(
                height: 100,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.trendingDown,
                            size: 12, color: colors.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          'Error Trend',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize10,
                            fontWeight: FontWeight.w600,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ErrorTrendChart(
                        colors: colors,
                        errors: errorHistory,
                        threshold: config.autoCompleteThreshold,
                      ),
                    ),
                  ],
                ),
              )
            : null;

    // Error values
    final Widget errorValues = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: _buildErrorValues(colors, state.currentError),
    );

    return Container(
      key: PolarAlignmentTutorialKeys.errorDisplay,
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The flex column below gives all slack to the visualization and lays
          // the readout out at its natural height. That works until the host
          // squeezes this panel below what the readout alone needs, at which
          // point the flex child is starved to zero and the readout overflows
          // the bottom — 6.2px of striped overflow at 800x600, where a
          // dismissible tour nudge may reserve up to 40% of the window height
          // before this panel ever gets measured.
          //
          // Under that floor, abandon the flex layout: give the visualization a
          // fixed readable minimum, let every child take its natural height,
          // and scroll. The numbers are the part the user cannot do without, so
          // they must never be the part that gets clipped.
          // Floor = what the non-flexible children actually need, not a round
          // number: the readout is 32px of padding + a 1px rule + one text row
          // (~46px at scale 1.0, and the row is the only part that scales), and
          // the trend chart is a fixed 100px when present. Anything at or above
          // this fits the flex layout, so the flex layout is what it keeps —
          // a landscape phone panel of ~100px must not change shape.
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final minFlexHeight =
              (trendChart != null ? 100.0 : 0.0) + 88.0 * textScale;

          if (constraints.maxHeight.isFinite &&
              constraints.maxHeight < minFlexHeight) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 160.0 * textScale, child: visualization),
                  if (trendChart != null) trendChart,
                  errorValues,
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(child: visualization),
              if (trendChart != null) trendChart,
              errorValues,
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorValues(
      NightshadeColors colors, PolarAlignmentError? error) {
    if (error == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ErrorValue(colors: colors, label: 'Azimuth', value: '--'),
          _ErrorValue(colors: colors, label: 'Altitude', value: '--'),
          _ErrorValue(
              colors: colors, label: 'Total', value: '--', isPrimary: true),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ErrorValue(
          colors: colors,
          label: 'Azimuth',
          value: '${error.azimuthError.toStringAsFixed(1)}"',
          color: _getErrorColor(colors, error.azimuthError.abs()),
        ),
        _ErrorValue(
          colors: colors,
          label: 'Altitude',
          value: '${error.altitudeError.toStringAsFixed(1)}"',
          color: _getErrorColor(colors, error.altitudeError.abs()),
        ),
        _ErrorValue(
          colors: colors,
          label: 'Total',
          value: '${error.totalError.toStringAsFixed(1)}"',
          color: _getErrorColor(colors, error.totalError),
          isPrimary: true,
        ),
      ],
    );
  }

  Color _getErrorColor(NightshadeColors colors, double error) {
    if (error < 30) return colors.success;
    if (error < 60) return colors.info;
    if (error < 120) return colors.warning;
    return colors.error;
  }
}

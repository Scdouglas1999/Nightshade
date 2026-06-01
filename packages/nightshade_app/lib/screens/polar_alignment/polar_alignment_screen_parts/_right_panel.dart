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

    return Container(
      key: PolarAlignmentTutorialKeys.errorDisplay,
      color: colors.surface,
      child: Column(
        children: [
          // Error visualization
          //
          // All-Sky mode shows the Sharpcap-style target reticle with a live
          // moving marker; TPPA mode keeps the legacy bar/dial visualization.
          Expanded(
            child: isAllSky
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AllSkyTargetReticle(
                        azimuthErrorArcsec:
                            state.currentError?.azimuthError ?? 0.0,
                        altitudeErrorArcsec:
                            state.currentError?.altitudeError ?? 0.0,
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
                              fontSize: 12,
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),

          // Task 4.5: Error trend sparkline chart (only in adjustment phase)
          if (state.phase == PolarAlignPhase.adjusting &&
              errorHistory.length > 2)
            Container(
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
                          fontSize: 10,
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
            ),

          // Error values
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: _buildErrorValues(colors, state.currentError),
          ),
        ],
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

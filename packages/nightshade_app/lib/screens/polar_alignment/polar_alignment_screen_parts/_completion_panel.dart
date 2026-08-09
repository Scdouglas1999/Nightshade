// Part of ../polar_alignment_screen.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../polar_alignment_screen.dart';

/// Whether a finished run actually got the polar axis inside the threshold the
/// operator configured.
///
/// The terminal phase only says "the task ended" — it is reached by Done, by
/// Stop and by the native auto-complete alike. Grading the success tick off the
/// phase told an operator sitting on 30' of residual error that they were
/// aligned. Top-level so the claim is testable without the screen.
bool polarAlignmentReachedThreshold(PolarAlignmentState state) {
  final threshold = state.config?.autoCompleteThreshold;
  if (threshold == null || state.currentError == null) return false;
  return state.isWithinThreshold(threshold);
}

/// Signed change in total error, arcseconds removed (positive = improved).
///
/// `PolarAlignmentState.improvementPercent` clamps to 0..100, so a run that
/// made the alignment *worse* is indistinguishable from one that changed
/// nothing. The panel needs the sign, so it recomputes from the two errors.
double polarAlignmentImprovementArcsec(PolarAlignmentState state) {
  final initial = state.initialError;
  final current = state.currentError;
  if (initial == null || current == null) return 0;
  return initial.totalError - current.totalError;
}

extension _CompletionPanel on _PolarAlignmentScreenState {
  Widget _buildCompleteStatus(
      NightshadeColors colors, PolarAlignmentState state) {
    final reached = polarAlignmentReachedThreshold(state);
    final threshold = state.config?.autoCompleteThreshold;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          reached ? NightshadeIcons.success : NightshadeIcons.warning,
          size: 64,
          color: reached ? colors.success : colors.warning,
        ),
        const SizedBox(height: 16),
        Text(
          reached ? 'Alignment Complete' : 'Alignment Stopped',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize20,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (state.currentError != null)
          Text(
            reached || threshold == null
                ? 'Final error: ${formatPolarError(state.currentError!.totalError)}'
                : 'Still ${formatPolarError(state.currentError!.totalError)} off — '
                    'the ${formatPolarError(threshold)} target was not reached',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: reached ? colors.textSecondary : colors.warning,
            ),
          ),
        const SizedBox(height: 24),
        // Before/After summary card
        if (state.initialError != null && state.currentError != null)
          _buildCompletionSummary(colors, state),
      ],
    );
  }

  /// Task 4.3: Completion summary widget showing before/after
  Widget _buildCompletionSummary(
      NightshadeColors colors, PolarAlignmentState state) {
    final initial = state.initialError!;
    final current = state.currentError!;
    final improvementPercent = state.improvementPercent ?? 0.0;
    // Grade the chip by the SIGN of the change, not by the clamped percent:
    // a run that removed nothing (or made it worse) must not wear the same
    // green "+0%" as one that halved the error.
    final improvedArcsec = polarAlignmentImprovementArcsec(state);
    final roundedPercent = improvementPercent.round();
    final improved = improvedArcsec > 0 && roundedPercent > 0;
    final worsened = improvedArcsec < 0;
    final chipColor = improved
        ? colors.success
        : worsened
            ? colors.error
            : colors.textMuted;
    final chipLabel =
        improved ? '+$roundedPercent%' : (worsened ? 'Worse' : 'No change');

    return LayoutBuilder(
      builder: (context, constraints) {
        final parentMax = constraints.maxWidth;
        final cardWidth =
            parentMax.isFinite ? (parentMax * 0.92).clamp(280.0, 400.0) : 400.0;

        return SizedBox(
          width: cardWidth,
          child: NightshadeCard(
            variant: CardVariant.subtle,
            borderRadius: NightshadeTokens.radiusInline8,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                        improved
                            ? LucideIcons.trendingDown
                            : worsened
                                ? LucideIcons.trendingUp
                                : LucideIcons.minus,
                        size: 18,
                        color: chipColor),
                    const SizedBox(width: 8),
                    Text(
                      'Alignment Summary',
                      style: NightshadeTypography.h5
                          .copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Before/After comparison
                Row(
                  children: [
                    // Before
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: NightshadeDecorations.tintedBadge(
                          colors.error,
                          borderRadius: NightshadeTokens.borderRadiusInline8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Before',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10,
                                fontWeight: FontWeight.w600,
                                color: colors.error,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              formatPolarError(initial.totalError),
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize24,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Az: ${formatPolarError(initial.azimuthError)}',
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize10,
                                  color: colors.textMuted),
                            ),
                            Text(
                              'Alt: ${formatPolarError(initial.altitudeError)}',
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize10,
                                  color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Arrow
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        NightshadeIcons.arrowRight,
                        size: 20,
                        color: colors.textMuted,
                      ),
                    ),

                    // After — tinted by the outcome, not by being the second
                    // box. A green "After" beside an unchanged number reads as
                    // a result the run did not produce.
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: NightshadeDecorations.tintedBadge(
                          chipColor,
                          borderRadius: NightshadeTokens.borderRadiusInline8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'After',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10,
                                fontWeight: FontWeight.w600,
                                color: chipColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              formatPolarError(current.totalError),
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize24,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Az: ${formatPolarError(current.azimuthError)}',
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize10,
                                  color: colors.textMuted),
                            ),
                            Text(
                              'Alt: ${formatPolarError(current.altitudeError)}',
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize10,
                                  color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Improvement progress bar
                Text(
                  'Improvement',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: NightshadeTokens.borderRadiusInline4,
                        child: LinearProgressIndicator(
                          value: improvementPercent / 100.0,
                          backgroundColor: colors.surfaceAlt,
                          color: improvementPercent > 75
                              ? colors.success
                              : improvementPercent > 50
                                  ? colors.info
                                  : colors.warning,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: NightshadeDecorations.tintedBadge(
                        chipColor,
                        borderRadius: NightshadeTokens.borderRadiusInline4,
                      ),
                      child: Text(
                        chipLabel,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize14,
                          fontWeight: FontWeight.bold,
                          color: chipColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorStatus(NightshadeColors colors, PolarAlignmentState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.alertCircle,
          size: 64,
          color: colors.error,
        ),
        const SizedBox(height: 16),
        Text(
          'Error Occurred',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize20,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          state.errorMessage ?? state.statusMessage,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
            color: colors.error,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

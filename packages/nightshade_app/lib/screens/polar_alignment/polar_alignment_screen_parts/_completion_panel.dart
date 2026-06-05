// Part of ../polar_alignment_screen.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../polar_alignment_screen.dart';

extension _CompletionPanel on _PolarAlignmentScreenState {
  Widget _buildCompleteStatus(
      NightshadeColors colors, PolarAlignmentState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          NightshadeIcons.success,
          size: 64,
          color: colors.success,
        ),
        const SizedBox(height: 16),
        Text(
          'Alignment Complete',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize20,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (state.currentError != null)
          Text(
            'Final error: ${state.currentError!.totalError.toStringAsFixed(1)} arcseconds',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: colors.textSecondary,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final parentMax = constraints.maxWidth;
        final cardWidth =
            parentMax.isFinite ? (parentMax * 0.92).clamp(280.0, 400.0) : 400.0;

        return Container(
          width: cardWidth,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: NightshadeTokens.borderRadiusInline8,
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.trendingDown,
                      size: 18, color: colors.success),
                  const SizedBox(width: 8),
                  Text(
                    'Alignment Summary',
                    style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
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
                            '${initial.totalError.toStringAsFixed(0)}"',
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize24,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Az: ${initial.azimuthError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
                          ),
                          Text(
                            'Alt: ${initial.altitudeError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
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

                  // After
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: NightshadeDecorations.tintedBadge(
                        colors.success,
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
                              color: colors.success,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${current.totalError.toStringAsFixed(0)}"',
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize24,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Az: ${current.azimuthError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
                          ),
                          Text(
                            'Alt: ${current.altitudeError.toStringAsFixed(1)}"',
                            style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: NightshadeDecorations.tintedBadge(
                      colors.success,
                      borderRadius: NightshadeTokens.borderRadiusInline4,
                    ),
                    child: Text(
                      '+${improvementPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize14,
                        fontWeight: FontWeight.bold,
                        color: colors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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

// Part of ../polar_alignment_screen.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../polar_alignment_screen.dart';

extension _HistoryPanel on _PolarAlignmentScreenState {
  Widget _buildAdjustmentTips(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusInline8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TipItem(colors: colors, text: 'Make small adjustments'),
          _TipItem(colors: colors, text: 'Watch the error decrease'),
          _TipItem(colors: colors, text: 'Target < 1 arcmin for best results'),
          _TipItem(colors: colors, text: 'Click Done when satisfied'),
        ],
      ),
    );
  }

  /// Task 4.2: Adjustment magnitude guidance widget
  Widget _buildAdjustmentGuidance(
      NightshadeColors colors, PolarAlignmentError error) {
    // Calculate magnitude categories based on total error in arcseconds
    final totalArcsec = error.totalError;

    // Determine adjustment magnitude
    String magnitudeText;
    String adjustmentHint;
    Color magnitudeColor;
    IconData magnitudeIcon;

    if (totalArcsec < 10) {
      magnitudeText = 'Micro adjustments';
      adjustmentHint = 'Barely touch the knobs';
      magnitudeColor = colors.success;
      magnitudeIcon = NightshadeIcons.success;
    } else if (totalArcsec < 30) {
      magnitudeText = '1/8 turn';
      adjustmentHint = 'Very small movements';
      magnitudeColor = colors.success;
      magnitudeIcon = NightshadeIcons.arrowRight;
    } else if (totalArcsec < 60) {
      magnitudeText = '1/4 turn';
      adjustmentHint = 'Small, careful movements';
      magnitudeColor = colors.info;
      magnitudeIcon = NightshadeIcons.arrowRight;
    } else if (totalArcsec < 120) {
      magnitudeText = '1/2 turn';
      adjustmentHint = 'Medium adjustments';
      magnitudeColor = colors.warning;
      magnitudeIcon = LucideIcons.alertCircle;
    } else {
      magnitudeText = 'Large adjustments';
      adjustmentHint = 'Significant correction needed';
      magnitudeColor = colors.error;
      magnitudeIcon = NightshadeIcons.warning;
    }

    // Direction indicators
    final azDirection = error.azimuthError > 0 ? 'Right' : 'Left';
    final altDirection = error.altitudeError > 0 ? 'Down' : 'Up';
    final azMagnitude = error.azimuthError.abs();
    final altMagnitude = error.altitudeError.abs();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.emphasisSurface(
        magnitudeColor,
        borderRadius: NightshadeTokens.borderRadiusInline8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(magnitudeIcon, size: 16, color: magnitudeColor),
              const SizedBox(width: 8),
              Text(
                magnitudeText,
                style: NightshadeTypography.h6.copyWith(color: magnitudeColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            adjustmentHint,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Azimuth direction
          if (azMagnitude > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    error.azimuthError > 0
                        ? NightshadeIcons.arrowRight
                        : NightshadeIcons.arrowLeft,
                    size: 12,
                    color: _getErrorMagnitudeColor(colors, azMagnitude),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Azimuth: $azDirection ${azMagnitude.toStringAsFixed(0)}"',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: _getErrorMagnitudeColor(colors, azMagnitude),
                    ),
                  ),
                ],
              ),
            ),
          // Altitude direction
          if (altMagnitude > 1)
            Row(
              children: [
                Icon(
                  error.altitudeError > 0
                      ? NightshadeIcons.arrowDown
                      : NightshadeIcons.arrowUp,
                  size: 12,
                  color: _getErrorMagnitudeColor(colors, altMagnitude),
                ),
                const SizedBox(width: 6),
                Text(
                  'Altitude: $altDirection ${altMagnitude.toStringAsFixed(0)}"',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: _getErrorMagnitudeColor(colors, altMagnitude),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getErrorMagnitudeColor(NightshadeColors colors, double arcsec) {
    if (arcsec < 10) return colors.success;
    if (arcsec < 30) return colors.info;
    if (arcsec < 60) return colors.warning;
    return colors.error;
  }

  /// Task 4.6: History panel widget
  ///
  /// Why: uses the streaming history provider (`polarAlignmentHistoryStreamProvider`)
  /// so new alignment runs appear in the panel immediately after the run
  /// completes — previously the panel was on a one-shot Future and stale until
  /// the screen was rebuilt.
  Widget _buildHistoryPanel(NightshadeColors colors) {
    final profileId = ref.watch(activeEquipmentProfileProvider)?.id;
    final historyAsync =
        ref.watch(polarAlignmentHistoryStreamProvider(profileId));

    return NightshadeCard(
      variant: CardVariant.standard,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.history, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              Text(
                'Alignment History',
                style:
                    NightshadeTypography.h6.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          historyAsync.when(
            data: (history) {
              if (history.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'No alignment history yet',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: history.take(5).map((entry) {
                  final improvementPercent = entry.initialTotalError > 0
                      ? ((entry.initialTotalError - entry.finalTotalError) /
                              entry.initialTotalError *
                              100)
                          .clamp(0.0, 100.0)
                      : 0.0;

                  final dateStr = _formatDate(entry.completedAt);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: NightshadeTokens.borderRadiusMd,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          entry.autoCompleted
                              ? NightshadeIcons.target
                              : NightshadeIcons.check,
                          size: 14,
                          color: entry.finalTotalError < 60
                              ? colors.success
                              : colors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize10,
                                  color: colors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Final: ${entry.finalTotalError.toStringAsFixed(0)}"',
                                style: NightshadeTypography.labelQuiet
                                    .copyWith(color: colors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: NightshadeDecorations.tintedBadge(
                            improvementPercent > 50
                                ? colors.success
                                : colors.info,
                            borderRadius: NightshadeTokens.borderRadiusInline4,
                          ),
                          child: Text(
                            '+${improvementPercent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize10,
                              fontWeight: FontWeight.w600,
                              color: improvementPercent > 50
                                  ? colors.success
                                  : colors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load history: $error',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: colors.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

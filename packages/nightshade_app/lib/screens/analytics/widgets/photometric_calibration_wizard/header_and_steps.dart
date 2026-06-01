part of '../photometric_calibration_wizard.dart';

extension _PhotometricWizardHeaderAndSteps
    on _PhotometricCalibrationWizardState {
  Widget _buildHeader(NightshadeColors colors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: NightshadeDecorations.tintedBadge(
            colors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.sparkles, color: colors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photometric Calibration Wizard',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Compute transformation coefficients for absolute photometry',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.x, color: colors.textMuted, size: 18),
        ),
      ],
    );
  }

  Widget _buildStepIndicator(NightshadeColors colors) {
    const labels = ['Select Frame', 'Match Stars', 'Compute Fit', 'Save'];
    return Row(
      children: List.generate(labels.length, (index) {
        final isActive = index == _step;
        final isDone = index < _step;
        return Expanded(
          child: Row(
            children: [
              if (index > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isDone
                        ? colors.primary
                        : colors.border.withValues(alpha: 0.3),
                  ),
                ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? colors.primary
                      : isDone
                          ? colors.primary.withValues(alpha: 0.7)
                          : colors.surfaceAlt,
                  border: Border.all(
                    color: isActive || isDone
                        ? colors.primary
                        : colors.border.withValues(alpha: 0.4),
                  ),
                ),
                child: Center(
                  child: isDone
                      ? Icon(LucideIcons.check,
                          color: colors.textPrimary, size: 14)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isActive
                                ? colors.textPrimary
                                : colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              if (index < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isDone
                        ? colors.primary
                        : colors.border.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // =========================================================================
  // Step 1: Select a standard star field frame
  // =========================================================================
}

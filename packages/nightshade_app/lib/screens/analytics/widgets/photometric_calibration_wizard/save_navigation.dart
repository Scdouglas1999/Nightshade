part of '../photometric_calibration_wizard.dart';

extension _PhotometricWizardSaveNavigation
    on _PhotometricCalibrationWizardState {
  Widget _buildStep4Save(NightshadeColors colors) {
    final coeff = _computedCoefficients;
    if (coeff == null) {
      return Text(
        'No coefficients to save.',
        style: TextStyle(color: colors.error),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Save Calibration',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        NightshadeCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCoefficientRow(colors, 'Filter', coeff.filterName),
                _buildCoefficientRow(
                    colors, 'Zero Point', coeff.zeroPoint.toStringAsFixed(4)),
                _buildCoefficientRow(colors, 'Extinction',
                    coeff.extinctionCoefficient.toStringAsFixed(4)),
                _buildCoefficientRow(
                    colors, 'Color Term', coeff.colorTerm.toStringAsFixed(4)),
                _buildCoefficientRow(
                    colors, 'RMS', coeff.rmsResidual.toStringAsFixed(4)),
                _buildCoefficientRow(
                    colors, 'Stars', '${coeff.matchedStarCount}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'These coefficients will be applied to future photometry '
          'measurements taken with the "$_filterName" filter. The standard '
          'equation M_std = m_inst - k*X + T*(B-V) + zp will be used '
          'to convert instrumental magnitudes to the standard system.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: TextStyle(
              color: _statusMessage.contains('Saved')
                  ? colors.success
                  : colors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // Navigation
  // =========================================================================

  Widget _buildNavigationButtons(NightshadeColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_step > 0)
          NightshadeButton(
            onPressed: () => _update(() => _step--),
            label: 'Back',
            variant: ButtonVariant.ghost,
          )
        else
          const SizedBox.shrink(),
        if (_step < 3)
          NightshadeButton(
            onPressed: _canAdvance() ? () => _advance() : null,
            label: 'Next',
          )
        else
          NightshadeButton(
            onPressed: _computedCoefficients != null ? _saveAndClose : null,
            icon: LucideIcons.save,
            label: 'Save Coefficients',
          ),
      ],
    );
  }

  bool _canAdvance() {
    switch (_step) {
      case 0:
        return _selectedImageId != null && _filterName.isNotEmpty;
      case 1:
        return _starMatches.length >= 4;
      case 2:
        return _computedCoefficients != null;
      default:
        return false;
    }
  }

  void _advance() {
    if (_canAdvance()) {
      _update(() => _step++);
    }
  }

  Future<void> _saveAndClose() async {
    final coeff = _computedCoefficients;
    if (coeff == null) return;

    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        await backend.savePhotometricTransform(coeff);
      } else {
        await ref
            .read(photometricTransformServiceProvider)
            .saveTransform(coeff);
      }
      if (mounted) {
        _update(() => _statusMessage = 'Saved successfully!');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (error) {
      if (mounted) {
        _update(() => _statusMessage = 'Save failed: $error');
      }
    }
  }
}

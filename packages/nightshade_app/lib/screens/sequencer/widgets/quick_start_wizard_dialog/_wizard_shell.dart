// Part of ../quick_start_wizard_dialog.dart -- extracted for maintainability.
// ignore_for_file: unused_element

part of '../quick_start_wizard_dialog.dart';

extension _WizardShell on _QuickStartWizardDialogState {
  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  Widget _buildDialog(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 700,
          designMaxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colors),
            _buildStepIndicator(colors),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: _buildCurrentStep(colors),
              ),
            ),
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.wand2, color: colors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick-Start Sequence Wizard',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _stepTitle(_currentStep),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, color: colors.textSecondary, size: 20),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  String _stepTitle(int step) {
    switch (step) {
      case 0:
        return 'Step 1 of 5: Choose Your Target';
      case 1:
        return 'Step 2 of 5: Filters & Exposures';
      case 2:
        return 'Step 3 of 5: Automation';
      case 3:
        return 'Step 4 of 5: Safety';
      case 4:
        return 'Step 5 of 5: Review & Create';
      default:
        return '';
    }
  }

  Widget _buildStepIndicator(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children:
            List.generate(_QuickStartWizardDialogState._totalSteps, (index) {
          final isCompleted = index < _currentStep;
          final isCurrent = index == _currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: isCompleted || isCurrent
                          ? colors.primary
                          : colors.border,
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
                    ),
                  ),
                ),
                if (index < _QuickStartWizardDialogState._totalSteps - 1)
                  const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(NightshadeColors colors) {
    switch (_currentStep) {
      case 0:
        return _buildTargetStep(colors);
      case 1:
        return _buildFiltersStep(colors);
      case 2:
        return _buildAutomationStep(colors);
      case 3:
        return _buildSafetyStep(colors);
      case 4:
        return _buildReviewStep(colors);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFooter(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: () => _update(() => _currentStep--),
              icon: Icon(LucideIcons.chevronLeft,
                  size: 16, color: colors.textSecondary),
              label:
                  Text('Back', style: TextStyle(color: colors.textSecondary)),
            )
          else
            const SizedBox.shrink(),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child:
                    Text('Cancel', style: TextStyle(color: colors.textMuted)),
              ),
              const SizedBox(width: 12),
              if (_currentStep < _QuickStartWizardDialogState._totalSteps - 1)
                NightshadeButton(
                  onPressed: _canAdvance()
                      ? () => _update(() => _currentStep++)
                      : null,
                  icon: LucideIcons.chevronRight,
                  label: 'Next',
                )
              else
                NightshadeButton(
                  onPressed: _canAdvance() ? _createSequence : null,
                  icon: LucideIcons.sparkles,
                  label: 'Create Sequence',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

part of '../target_constraints_editor.dart';

class _WizardHeader extends StatelessWidget {
  final int step;
  final NightshadeColors colors;
  const _WizardHeader({required this.step, required this.colors});

  @override
  Widget build(BuildContext context) {
    String label;
    switch (step) {
      case 1:
        label = 'Step 1 of 3 — Choose constraint type';
        break;
      case 2:
        label = 'Step 2 of 3 — Set parameters';
        break;
      case 3:
        label = 'Step 3 of 3 — Review';
        break;
      default:
        label = '';
    }
    return Row(
      children: [
        Icon(LucideIcons.filter,
            size: NightshadeTokens.iconMd, color: colors.primary),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          'Add constraint',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize16,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _Step1ChooseKind extends StatelessWidget {
  final Set<TargetConstraintKind> existingKinds;
  final TargetConstraintKind? selected;
  final void Function(TargetConstraintKind) onSelect;

  const _Step1ChooseKind({
    required this.existingKinds,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What kind of constraint?',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize14,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        _KindCard(
          key: const ValueKey('wizard-kind-timeWindow'),
          kind: TargetConstraintKind.timeWindow,
          icon: LucideIcons.clock,
          title: 'Time window',
          body: 'Only image between these hours of the night.',
          selected: selected == TargetConstraintKind.timeWindow,
          disabled: existingKinds.contains(TargetConstraintKind.timeWindow),
          onTap: () => onSelect(TargetConstraintKind.timeWindow),
        ),
        _KindCard(
          key: const ValueKey('wizard-kind-moon'),
          kind: TargetConstraintKind.moonIlluminationMax,
          icon: LucideIcons.moon,
          title: 'Moon avoidance',
          body: "Skip this target when the moon's illumination is above a "
              'set percentage.',
          selected: selected == TargetConstraintKind.moonIlluminationMax,
          disabled:
              existingKinds.contains(TargetConstraintKind.moonIlluminationMax),
          onTap: () => onSelect(TargetConstraintKind.moonIlluminationMax),
        ),
        _KindCard(
          key: const ValueKey('wizard-kind-horizon'),
          kind: TargetConstraintKind.customHorizon,
          icon: LucideIcons.mountain,
          title: 'Custom horizon',
          body: 'Respect terrain blocking from a saved horizon profile.',
          selected: selected == TargetConstraintKind.customHorizon,
          disabled: existingKinds.contains(TargetConstraintKind.customHorizon),
          onTap: () => onSelect(TargetConstraintKind.customHorizon),
        ),
        _KindCard(
          key: const ValueKey('wizard-kind-scheduledWindow'),
          kind: TargetConstraintKind.scheduledWindow,
          icon: LucideIcons.calendar,
          title: 'Scheduled window',
          body: 'Force the scheduler onto this target during these hours.',
          selected: selected == TargetConstraintKind.scheduledWindow,
          // Scheduled windows are not unique per target — multiple
          // windows can be stacked.
          disabled: false,
          onTap: () => onSelect(TargetConstraintKind.scheduledWindow),
        ),
      ],
    );
  }
}

class _KindCard extends StatelessWidget {
  final TargetConstraintKind kind;
  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _KindCard({
    super.key,
    required this.kind,
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final borderColor = selected
        ? colors.primary
        : disabled
            ? colors.border.withValues(alpha: 0.4)
            : colors.border;
    final bg = selected
        ? colors.primary.withValues(alpha: 0.08)
        : disabled
            ? colors.surfaceHover
            : colors.surfaceAlt;
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          child: Container(
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: NightshadeTokens.iconMd,
                    color: disabled
                        ? colors.textMuted
                        : selected
                            ? colors.primary
                            : colors.textSecondary),
                const SizedBox(width: NightshadeTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize14,
                              fontWeight: FontWeight.w700,
                              color: disabled
                                  ? colors.textMuted
                                  : colors.textPrimary,
                            ),
                          ),
                          if (disabled) ...[
                            const SizedBox(width: NightshadeTokens.spaceSm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.surfaceHover,
                                borderRadius: BorderRadius.circular(
                                    NightshadeTokens.radiusLg),
                                border: Border.all(color: colors.border),
                              ),
                              child: Text(
                                'already added',
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize10,
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: disabled
                              ? colors.textMuted
                              : colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

part of '../target_constraints_editor.dart';

class _LoadedConstraints {
  final List<TargetConstraint> constraints;
  final List<HorizonProfile> horizonProfiles;
  _LoadedConstraints({
    required this.constraints,
    required this.horizonProfiles,
  });
}

class _ConstraintRow extends StatefulWidget {
  final TargetConstraint constraint;
  final List<HorizonProfile> horizonProfiles;
  final Future<void> Function(TargetConstraint) onChange;
  final Future<void> Function() onDelete;

  const _ConstraintRow({
    required this.constraint,
    required this.horizonProfiles,
    required this.onChange,
    required this.onDelete,
  });

  @override
  State<_ConstraintRow> createState() => _ConstraintRowState();
}

class _ConstraintRowState extends State<_ConstraintRow> {
  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final c = widget.constraint;
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: c.enabled ? colors.surfaceAlt : colors.surfaceHover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            NightshadeSwitch(
              value: c.enabled,
              onChanged: (v) => widget.onChange(c.copyWith(enabled: v)),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            SizedBox(
              width: 150,
              child: Text(
                _kindLabel(c.kind),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: _ConstraintBody(
                constraint: c,
                horizonProfiles: widget.horizonProfiles,
                onChange: widget.onChange,
              ),
            ),
            IconButton(
              tooltip: 'Remove constraint',
              onPressed: widget.onDelete,
              icon: Icon(LucideIcons.trash2,
                  size: NightshadeTokens.iconSm, color: colors.error),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(TargetConstraintKind k) {
    switch (k) {
      case TargetConstraintKind.timeWindow:
        return 'Time window';
      case TargetConstraintKind.moonIlluminationMax:
        return 'Max moon illumination';
      case TargetConstraintKind.customHorizon:
        return 'Custom horizon';
      case TargetConstraintKind.scheduledWindow:
        return 'Scheduled window';
    }
  }
}

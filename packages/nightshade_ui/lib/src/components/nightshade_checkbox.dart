import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// Custom checkbox matching Nightshade theme semantics.
class NightshadeCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const NightshadeCheckbox({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final isDisabled = onChanged == null;
    final checkColor = colors.onPrimary;

    return GestureDetector(
      onTap: isDisabled ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: NightshadeTokens.durationQuick,
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: value
              ? (isDisabled ? colors.surfaceHover : colors.primary)
              : Colors.transparent,
          borderRadius: NightshadeTokens.borderRadiusXs,
          border: Border.all(
            color: value
                ? (isDisabled ? colors.border : colors.primary)
                : colors.border,
            width: 2,
          ),
        ),
        child: value
            ? Icon(
                LucideIcons.check,
                size: 12,
                color: isDisabled ? colors.textMuted : checkColor,
              )
            : null,
      ),
    );
  }
}

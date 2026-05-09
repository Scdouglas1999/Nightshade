import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Compact toggle chip for annotation quick settings (compass, scale, labels, etc.)
class AnnotationQuickSettingChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const AnnotationQuickSettingChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.18)
              : colors.surfaceAlt.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.55)
                : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? colors.primary : colors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

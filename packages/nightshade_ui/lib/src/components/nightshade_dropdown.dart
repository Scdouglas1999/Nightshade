import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';

class NightshadeDropdown extends StatelessWidget {
  final String? value;
  final String? hint;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final bool isExpanded;

  const NightshadeDropdown({
    super.key,
    this.value,
    this.hint,
    required this.items,
    this.onChanged,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: hint != null
              ? Text(
                  hint!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textMuted,
                  ),
                )
              : null,
          isExpanded: isExpanded,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 14,
            color: colors.textSecondary,
          ),
          dropdownColor: colors.surface,
          borderRadius: BorderRadius.circular(8),
          style: TextStyle(
            fontSize: 12,
            color: colors.textPrimary,
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}






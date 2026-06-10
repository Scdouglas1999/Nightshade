import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

class NightshadeDropdown extends StatelessWidget {
  final String? value;
  final String? hint;
  final List<String> items;
  final List<String>? itemLabels;
  final ValueChanged<String?>? onChanged;
  final bool isExpanded;
  final bool isDense;

  const NightshadeDropdown({
    super.key,
    this.value,
    this.hint,
    required this.items,
    this.itemLabels,
    this.onChanged,
    this.isExpanded = false,
    this.isDense = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(color: colors.border.withValues(alpha: 0.85)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: hint != null
              ? Text(
                  hint!,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                )
              : null,
          isExpanded: isExpanded,
          isDense: isDense,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 14,
            color: colors.textSecondary,
          ),
          dropdownColor: colors.surface,
          borderRadius: BorderRadius.circular(8),
          style: TextStyle(fontSize: 12, color: colors.textPrimary),
          items: List.generate(items.length, (index) {
            final item = items[index];
            final label = itemLabels != null && index < itemLabels!.length
                ? itemLabels![index]
                : item;
            return DropdownMenuItem<String>(
              value: item,
              child: Text(label, overflow: TextOverflow.ellipsis),
            );
          }),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

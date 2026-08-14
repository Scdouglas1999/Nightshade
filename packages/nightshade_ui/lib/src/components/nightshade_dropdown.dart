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

  /// The style the closed control paints its current value in.
  ///
  /// Public so a caller that has to SIZE this control can measure the label
  /// with the same style it will be painted in, instead of guessing.
  static const TextStyle labelStyle = TextStyle(fontSize: 12);

  /// Horizontal space this control spends on everything that is not the label:
  /// 12 px padding each side, the 14 px chevron, and the 1 px border each side.
  static const double chromeWidth = 12 + 12 + 14 + 2;

  String _labelFor(int index) =>
      itemLabels != null && index < itemLabels!.length
      ? itemLabels![index]
      : items[index];

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final isEnabled = onChanged != null;

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
              ? Semantics(
                  button: true,
                  enabled: isEnabled,
                  child: Text(
                    hint!,
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
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
          style: labelStyle.copyWith(color: colors.textPrimary),
          items: List.generate(items.length, (index) {
            final item = items[index];
            return DropdownMenuItem<String>(
              value: item,
              // `selected` alone was not enough: AT-SPI carries it as SELECTED,
              // which no menu consumer reads and which never appeared in a live
              // tree dump, so every option of an open Theme / Frame Type menu
              // still announced as a bare button with nothing marking the one
              // in force (NEW-C4). A menu of mutually exclusive options is a
              // radio group, and CHECKED is the state that role publishes —
              // set on every entry so the unchosen ones say "not checked"
              // rather than saying nothing.
              child: Semantics(
                enabled: isEnabled,
                selected: item == value,
                checked: item == value,
                child: Text(_labelFor(index), overflow: TextOverflow.ellipsis),
              ),
            );
          }),
          // The closed control renders the chosen item, so left to itself it
          // inherits that item's `selected` state and announces itself as a
          // selected menu entry. This mirrors DropdownMenuItem's own layout
          // (48px min height, start-aligned) so nothing moves, and carries
          // the role and enabled state Material never publishes — AT-SPI
          // reads an absent enabled flag as "disabled", which is how a live
          // Frame Type / Binning / Theme control came to announce itself as
          // one the user could not operate.
          selectedItemBuilder: (context) => List.generate(
            items.length,
            // Only the enabled state: the dropdown already annotates the
            // button role on its own node, and two fragments that set the
            // same flag are held incompatible and split into two nodes.
            (index) => Semantics(
              enabled: isEnabled,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _labelFor(index),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

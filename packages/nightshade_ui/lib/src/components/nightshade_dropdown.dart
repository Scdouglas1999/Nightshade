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

    // The closed control is ONE control, and it says so here rather than
    // leaving the role to Material.
    //
    // `DropdownButton` publishes `button` only when it believes the child on
    // screen does not: it sets `button: !childHasButtonSemantic`, and
    // `childHasButtonSemantic` is true as soon as a `hint` is supplied —
    // whether or not the hint is the thing being shown. With a `hint` AND a
    // value the closed control shows the value, built by `selectedItemBuilder`,
    // which carries no role of its own, so the whole control reached AT-SPI as
    // ROLE_PANEL: a screen reader was never told the picker was operable. The
    // export sheet's step picker is exactly that shape. Every settings dropdown
    // escaped it only because `SettingRow` merges the row into a node that has
    // a role of its own.
    //
    // Merging is what makes the annotation safe in BOTH shapes: with no hint
    // Material sets the same flag, and two fragments that set one flag are held
    // incompatible and split into two nodes — one named, one operable. Under
    // the merge those fragments land on one node carrying the role, the enabled
    // state and the value's own words, so the platform sees a single button
    // named for what it is showing. The open menu is a route of its own and is
    // untouched by this.
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: isEnabled,
        child: Container(
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
              style: labelStyle.copyWith(color: colors.textPrimary),
              items: List.generate(items.length, (index) {
                final item = items[index];
                return DropdownMenuItem<String>(
                  value: item,
                  // A menu of mutually exclusive options is a radio group, and
                  // CHECKED is the state that role publishes — set on every
                  // entry so the unchosen ones say "not checked" rather than
                  // nothing. `selected` alone is not enough: AT-SPI carries it
                  // as SELECTED, which no menu consumer reads, so every option
                  // announces as a bare button with nothing marking the one in
                  // force.
                  child: Semantics(
                    enabled: isEnabled,
                    selected: item == value,
                    checked: item == value,
                    child: Text(
                      _labelFor(index),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }),
              // The closed control renders the chosen item, so left to itself
              // it inherits that item's `selected` state and announces itself
              // as a selected menu entry. This mirrors DropdownMenuItem's own
              // layout (48px min height, start-aligned) so nothing moves, and
              // carries no semantics of its own: the role and the enabled state
              // are on the merged node above, and the value's words come from
              // this Text.
              selectedItemBuilder: (context) => List.generate(
                items.length,
                (index) => ConstrainedBox(
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
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

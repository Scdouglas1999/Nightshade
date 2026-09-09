import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_decorations.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import 'nightshade_text_field.dart';

/// A select on the Observatory scale: the same 32px [NightshadeDecorations.field]
/// face as [NightshadeTextField], a 14px muted chevron, and an open list on the
/// `popover` decoration.
class NightshadeDropdown extends StatelessWidget {
  final String? value;
  final String? hint;
  final List<String> items;
  final List<String>? itemLabels;
  final ValueChanged<String?>? onChanged;

  /// Force the value/chevron row to fill the control even where the incoming
  /// width is unbounded.
  ///
  /// Rarely needed: a select given a bounded width now fills it on its own, so
  /// its value reads from the leading edge and its chevron sits at the trailing
  /// one, like every other field.
  final bool isExpanded;

  /// No longer read: the closed control's height is fixed by the field face.
  @Deprecated('The field height is fixed; use `dense`. Removed in wave 4.')
  final bool isDense;

  /// 28px instead of 32 — matches [NightshadeTextField.dense] so a dense row
  /// can mix the two without a step in the baseline.
  final bool dense;

  const NightshadeDropdown({
    super.key,
    this.value,
    this.hint,
    required this.items,
    this.itemLabels,
    this.onChanged,
    this.isExpanded = false,
    // ignore: deprecated_member_use_from_same_package
    this.isDense = false,
    this.dense = false,
  });

  /// The style the closed control paints its current value in.
  ///
  /// Public so a caller that has to SIZE this control can measure the label
  /// with the same style it will be painted in, instead of guessing.
  static const TextStyle labelStyle = NightshadeTypography.input;

  /// Horizontal space this control spends on everything that is not the label:
  /// 10px padding each side, the 14px chevron, and the 1px ring each side.
  static const double chromeWidth =
      fieldHorizontalPadding * 2 + fieldIconSize + 2;

  /// The control's height in logical pixels.
  double get height => dense ? fieldHeightDense : fieldHeight;

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
        child: LayoutBuilder(
          builder: (context, constraints) => _closed(
            colors,
            isEnabled: isEnabled,
            // A select is a FIELD: given a width it fills it, so the value
            // reads from the leading edge and the chevron sits at the trailing
            // one. Where the width is UNBOUNDED — a shrink-wrapping Row, which
            // is how a settings row hosts one — filling is not a thing a box
            // can do, and asking Material to try throws.
            expand: isExpanded || constraints.hasBoundedWidth,
          ),
        ),
      ),
    );
  }

  Widget _closed(
    NightshadeColors colors, {
    required bool isEnabled,
    required bool expand,
  }) {
    return Container(
      height: height,
      // centerLEFT: a select reads from the leading edge like every other
      // field, and expanding to the incoming width is what a field does.
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: fieldHorizontalPadding),
      decoration: NightshadeDecorations.field(colors),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: hint != null
              ? Text(hint!, style: labelStyle.copyWith(color: colors.textMuted))
              : null,
          isExpanded: expand,
          // Always dense: the control's height is set by the box above, so
          // Material's 48px button floor would only overflow it.
          isDense: true,
          icon: Icon(
            LucideIcons.chevronDown,
            size: fieldIconSize,
            color: colors.textMuted,
          ),
          dropdownColor: colors.surfaceElevated,
          borderRadius: NightshadeTokens.borderRadiusXl,
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
                child: Text(_labelFor(index), overflow: TextOverflow.ellipsis),
              ),
            );
          }),
          // The closed control renders the chosen item, so left to itself
          // it inherits that item's `selected` state and announces itself
          // as a selected menu entry. This mirrors DropdownMenuItem's own
          // layout (48px min height, start-aligned) so nothing moves, and
          // carries no semantics of its own: the role and the enabled state
          // are on the merged node above, and the value's words come from
          // this Text. The min height is the FIELD height, not Material's
          // 48px menu-item floor: the closed control is a 32px field.
          selectedItemBuilder: (context) => List.generate(
            items.length,
            (index) => ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(_labelFor(index), overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

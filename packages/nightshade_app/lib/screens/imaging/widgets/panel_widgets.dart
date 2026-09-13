import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/help/field_help_copy.dart';
import '../../../widgets/help/field_help_label.dart';
import '../../../widgets/touch_target_floor.dart';

/// Builds an imaging-panel row label, optionally appending a [helpAffordance]
/// when [helpId] is supplied.
///
/// Each of [InputRow], [InputRowEditable], [DropdownRow], and
/// [SliderRowInteractive] renders its label through this helper so the help
/// icon hugs the label text inside the row's label `Expanded`, leaving the
/// label/control flex layout untouched. When [helpId] is null the result is a
/// bare label `Text`.
Widget _panelRowLabel(
  BuildContext context, {
  required String label,
  required TextStyle style,
  required FieldHelpId? helpId,

  /// The control beside this label already carries the label in its own
  /// accessible name (see [DropdownRow]), so publishing it here too would
  /// leave a stranded `panel: Frame Type` node next to `button: Frame Type
  /// Light`. The help affordance keeps its own node either way.
  bool excludeLabelSemantics = false,
}) {
  final Widget text = excludeLabelSemantics
      ? ExcludeSemantics(child: Text(label, style: style))
      : Text(label, style: style);
  if (helpId == null) {
    return text;
  }
  final copy = helpFor(helpId);
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Flexible(child: text),
      const SizedBox(width: NightshadeTokens.spaceXs),
      helpAffordance(
        context,
        title: copy.title,
        body: copy.body,
        position: NightshadeTooltipPosition.top,
      ),
    ],
  );
}

class BigActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool isEnabled;
  final bool isLoading;
  final bool isMobile;

  const BigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.isEnabled = true,
    this.isLoading = false,
    this.isMobile = false,
  });

  @override
  State<BigActionButton> createState() => _BigActionButtonState();
}

class _BigActionButtonState extends State<BigActionButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();
    // NOT started here. Two of these buttons are mounted for as long as the
    // imaging screen is open, but the spinner this controller drives is only
    // built while `isLoading`. Repeating unconditionally kept a ticker
    // scheduling a frame on every vsync the whole time the screen was up, which
    // stops the app from ever idling. Driven by isLoading in build() instead.
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    final effectiveColor =
        widget.isEnabled ? widget.color : widget.color.withValues(alpha: 0.4);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.isEnabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown:
            widget.isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp:
            widget.isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel:
            widget.isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.isEnabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: () {
            final scale = _isPressed && widget.isEnabled ? 0.95 : 1.0;
            return Matrix4.identity()..scaleByDouble(scale, scale, scale, 1.0);
          }(),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isMobile ? 12 : 20,
            vertical: widget.isMobile ? 12 : 16,
          ),
          decoration: NightshadeDecorations.filledButton(
            effectiveColor,
            isHovered: _isHovered && widget.isEnabled,
            isDisabled: !widget.isEnabled,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.isLoading
                  ? OnScreenAnimationGate(
                      controller: _loadingController,
                      repeating: true,
                      child: AnimatedBuilder(
                        animation: _loadingController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _loadingController.value * 2 * math.pi,
                            child: Icon(
                              NightshadeIcons.loading,
                              size: 24,
                              color: primaryForeground.withValues(
                                  alpha: widget.isEnabled ? 1.0 : 0.5),
                            ),
                          );
                        },
                      ),
                    )
                  : Icon(
                      widget.icon,
                      size: widget.isMobile ? 20 : 24,
                      color: primaryForeground.withValues(
                          alpha: widget.isEnabled ? 1.0 : 0.5),
                    ),
              SizedBox(height: widget.isMobile ? 4 : 6),
              Flexible(
                child: Text(
                  widget.label,
                  style: NightshadeTypography.buttonSm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: primaryForeground.withValues(
                      alpha: widget.isEnabled
                          ? 1.0
                          : NightshadeTokens.opacityDisabled,
                    ),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditableCompactInput extends StatefulWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;
  final bool isMobile;

  const EditableCompactInput({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    required this.colors,
    required this.onChanged,
    this.isMobile = false,
  });

  @override
  State<EditableCompactInput> createState() => _EditableCompactInputState();
}

class _EditableCompactInputState extends State<EditableCompactInput> {
  late TextEditingController _controller;
  bool _isEditing = false;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _commitValue();
      }
    });
  }

  @override
  void didUpdateWidget(EditableCompactInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitValue() {
    setState(() => _isEditing = false);
    widget.onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: NightshadeTypography.caption
              .copyWith(color: widget.colors.textMuted),
        ),
        SizedBox(height: widget.isMobile ? 3 : 4),
        GestureDetector(
          onTap: () {
            setState(() => _isEditing = true);
            _focusNode.requestFocus();
            _controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controller.text.length,
            );
          },
          child: Container(
            width: widget.isMobile ? 70 : 90,
            constraints: BoxConstraints(
              // The tap box IS the painted box here, so the floor has to go on
              // the box itself rather than on an invisible wrapper: a
              // `TouchTargetFloor` would centre this fixed-width field inside
              // its (wider) parent slot and shift it off the label. Measured at
              // 70.0x32.0 on every phone width before this. Desktop keeps 34 —
              // `floorFor` returns 0 there, so dense panels do not reflow.
              minHeight: math.max(
                widget.isMobile ? 32 : 34,
                TouchTargetFloor.floorFor(context),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isMobile ? 8 : 10,
              vertical: widget.isMobile ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              border: Border.all(
                color:
                    _isEditing ? widget.colors.primary : widget.colors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _isEditing
                      ? TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          style: NightshadeTypography.buttonSm.copyWith(
                            color: widget.colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _commitValue(),
                        )
                      : Text(
                          widget.value,
                          style: NightshadeTypography.label.copyWith(
                            color: widget.colors.textPrimary,
                          ),
                        ),
                ),
                if (widget.suffix != null)
                  Text(
                    widget.suffix!,
                    style: NightshadeTypography.caption
                        .copyWith(color: widget.colors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PanelSection extends StatelessWidget {
  final String title;
  final Widget child;
  final NightshadeColors colors;

  /// A titled section with a bordered container for grouped imaging controls.
  ///
  /// For settings-style rows with a label and trailing control, compose
  /// [DropdownRow], [InputRow], or [InputRowEditable] inside this section.
  /// Those row widgets follow the same label/control flex layout as
  /// [SettingRow] in `../../settings/widgets/settings_widgets.dart`, adapted
  /// for the denser imaging side panel.
  const PanelSection({
    super.key,
    required this.title,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: NightshadeTypography.caption
              .copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        NightshadeCard(
          padding: const EdgeInsets.all(NightshadeTokens.panelSectionPadding),
          borderRadius: NightshadeTokens.radiusButton,
          child: child,
        ),
      ],
    );
  }
}

class InputRow extends StatelessWidget {
  final String label;
  final String? value;
  final NightshadeColors colors;
  final Widget? trailing;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  const InputRow({
    super.key,
    required this.label,
    this.value,
    required this.colors,
    this.trailing,
    this.helpId,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: NightshadeTokens.panelRowLabelFlex,
          child: _panelRowLabel(
            context,
            label: label,
            style: NightshadeTypography.caption
                .copyWith(color: colors.textSecondary),
            helpId: helpId,
          ),
        ),
        Expanded(
          flex: NightshadeTokens.panelRowControlFlex,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: NightshadeTokens.borderRadiusSm,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? '',
                    style: NightshadeTypography.caption
                        .copyWith(color: colors.textPrimary),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InputRowEditable extends StatefulWidget {
  final String label;
  final String value;
  final String? suffix;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  const InputRowEditable({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    required this.colors,
    required this.onChanged,
    this.helpId,
  });

  @override
  State<InputRowEditable> createState() => _InputRowEditableState();
}

class _InputRowEditableState extends State<InputRowEditable> {
  late TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(InputRowEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Row(
      children: [
        Expanded(
          flex: NightshadeTokens.panelRowLabelFlex,
          child: _panelRowLabel(
            context,
            label: widget.label,
            style: NightshadeTypography.caption
                .copyWith(color: colors.textSecondary),
            helpId: widget.helpId,
          ),
        ),
        Expanded(
          flex: NightshadeTokens.panelRowControlFlex,
          child: Container(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: NightshadeTokens.borderRadiusSm,
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: NightshadeTypography.caption
                  .copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                isDense: true,
                suffixText: widget.suffix,
                suffixStyle: NightshadeTypography.caption
                    .copyWith(color: colors.textMuted),
              ),
              onSubmitted: widget.onChanged,
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class DropdownRow extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final NightshadeColors colors;
  final ValueChanged<String?>? onChanged;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  /// Label + dropdown row for the imaging side panel.
  ///
  /// Layout mirrors [SettingRow] in `../../settings/widgets/settings_widgets.dart`:
  /// label on the left, control on the right. Uses [NightshadeDropdown] for the
  /// control styling.
  const DropdownRow({
    super.key,
    required this.label,
    this.value,
    required this.items,
    required this.colors,
    this.onChanged,
    this.helpId,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;

    // Left apart, the label and the control publish as two adjacent, unrelated
    // nodes — `panel: Frame Type` followed by `button: Light` — so assistive
    // tech announces "Light" with nothing saying what is Light.
    //
    // The control carries BOTH: one merged node reading "Frame Type Light"
    // with the button role and the tap action. The visible label text is
    // excluded from semantics so it does not linger beside it as a second,
    // valueless node; the help affordance keeps its own node, because it is a
    // separate thing to reach.
    return Row(
      children: [
        Expanded(
          flex: NightshadeTokens.panelRowLabelFlex,
          child: _panelRowLabel(
            context,
            label: label,
            style: NightshadeTypography.caption.copyWith(
                color: isEnabled ? colors.textSecondary : colors.textMuted),
            helpId: helpId,
            excludeLabelSemantics: true,
          ),
        ),
        Expanded(
          flex: NightshadeTokens.panelRowControlFlex,
          child: MergeSemantics(
            child: Semantics(
              label: label,
              child: NightshadeDropdown(
                value: items.contains(value) ? value : null,
                items: items,
                isExpanded: true,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SliderRowInteractive extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final NightshadeColors colors;
  final ValueChanged<double>? onChanged;

  /// Optional field-level help. When non-null, a tooltipped help icon is
  /// appended after the label text using copy from [helpFor]. Defaults to null,
  /// preserving the bare-label render for existing call sites.
  final FieldHelpId? helpId;

  const SliderRowInteractive({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.colors,
    this.onChanged,
    this.helpId,
  });

  /// Width of the trailing value, in logical pixels.
  static const double _valueWidth = 45;

  /// Room the help affordance and its gap take out of the label column.
  static const double _helpAffordanceWidth =
      NightshadeTokens.spaceXs + NightshadeTokens.iconXs;

  /// Whether [label] fits the label column of a row [rowWidth] wide.
  ///
  /// The column is [NightshadeTokens.panelRowLabelFlex] of what is left after
  /// the trailing value, less the help affordance when there is one — about
  /// 50px in the 216px side panel. A label that does not fit wraps, and wraps
  /// MID-WORD when a single word is wider than the column: "Settle threshold"
  /// rendered as "Settle threshol" over "d". So a label that does not fit
  /// takes the whole row instead, above its own control.
  static bool labelFitsBeside(
    BuildContext context, {
    required String label,
    required double rowWidth,
    required bool hasHelp,
  }) {
    const totalFlex = NightshadeTokens.panelRowLabelFlex +
        NightshadeTokens.panelRowControlFlex;
    final column = (rowWidth - _valueWidth) *
            NightshadeTokens.panelRowLabelFlex /
            totalFlex -
        (hasHelp ? _helpAffordanceWidth : 0);
    return measureTextWidth(
          context,
          text: label,
          style: NightshadeTypography.caption,
        ) <=
        column;
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;
    final labelWidget = _panelRowLabel(
      context,
      label: label,
      style: NightshadeTypography.caption
          .copyWith(color: isEnabled ? colors.textSecondary : colors.textMuted),
      helpId: helpId,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final beside = !constraints.hasBoundedWidth ||
            labelFitsBeside(
              context,
              label: label,
              rowWidth: constraints.maxWidth,
              hasHelp: helpId != null,
            );
        final row = _row(context, isEnabled, beside ? labelWidget : null);
        if (beside) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: labelWidget),
            row,
          ],
        );
      },
    );
  }

  /// The slider and its value, with the label beside them when it fits.
  Widget _row(BuildContext context, bool isEnabled, Widget? labelWidget) {
    return Row(
      children: [
        if (labelWidget != null)
          Expanded(
            flex: NightshadeTokens.panelRowLabelFlex,
            child: labelWidget,
          ),
        Expanded(
          flex: labelWidget == null
              ? NightshadeTokens.panelRowLabelFlex +
                  NightshadeTokens.panelRowControlFlex
              : NightshadeTokens.panelRowControlFlex,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: isEnabled ? colors.primary : colors.textMuted,
              inactiveTrackColor: colors.border,
              thumbColor: isEnabled ? colors.primary : colors.textMuted,
              overlayColor: colors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: _valueWidth,
          child: Text(
            '${value.toStringAsFixed(1)}$suffix',
            textAlign: TextAlign.right,
            style: NightshadeTypography.monoCaption.copyWith(
                color: isEnabled ? colors.textPrimary : colors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Horizontal padding inside a [SmallButton], its icon size, and the gap
/// between that icon and the label, in logical pixels.
const double _smallButtonPaddingH = 14;
const double _smallButtonIconSize = 14;
const double _smallButtonIconGap = 6;

class SmallButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isOutline;
  final bool isEnabled;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const SmallButton({
    super.key,
    required this.label,
    required this.icon,
    this.isOutline = false,
    this.isEnabled = true,
    required this.colors,
    this.onTap,
  });

  /// The width this button needs to render [label] in full, in logical pixels.
  ///
  /// The label is `Flexible` with `TextOverflow.ellipsis`, so a pair of these
  /// in a fixed two-column `Row` shrinks to "Cool D…" without overflowing,
  /// throwing or logging anything. `AdaptiveColumns` asks this first and
  /// stacks the pair when the answer does not fit.
  static double measureWidth(BuildContext context, {required String label}) =>
      measureTextWidth(
        context,
        text: label,
        style: NightshadeTypography.labelSm,
      ) +
      _smallButtonIconSize +
      _smallButtonIconGap +
      2 * _smallButtonPaddingH;

  @override
  State<SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<SmallButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    final isEnabled = widget.isEnabled;
    // Disabled must not be drawn at the strength of ordinary secondary text:
    // a full-strength `textMuted` border and label is exactly how enabled
    // secondary chrome looks everywhere else, so a disabled outline button
    // reads as pressable and its no-op reads as a swallowed command. Dim the
    // whole control the way the filled variant does.
    final outlineColor = isEnabled
        ? widget.colors.primary
        : widget.colors.textMuted
            .withValues(alpha: NightshadeTokens.opacityDisabled);
    final primaryColor =
        isEnabled ? widget.colors.primary : widget.colors.textMuted;
    final contentColor = widget.isOutline
        ? outlineColor
        : isEnabled
            ? primaryForeground
            : widget.colors.textMuted;

    return MouseRegion(
      // A control that cannot be pressed must not offer the pressable cursor.
      cursor:
          isEnabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: _smallButtonPaddingH,
          ),
          decoration: widget.isOutline
              ? BoxDecoration(
                  color: _isHovered && isEnabled
                      ? outlineColor.withValues(
                          alpha: NightshadeTokens.opacitySubtle,
                        )
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                  border: Border.all(color: outlineColor),
                )
              : NightshadeDecorations.filledButton(
                  primaryColor,
                  isHovered: _isHovered && isEnabled,
                  isDisabled: !isEnabled,
                ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: _smallButtonIconSize,
                color: contentColor,
              ),
              const SizedBox(width: _smallButtonIconGap),
              Flexible(
                child: Text(
                  widget.label,
                  style: NightshadeTypography.labelSm.copyWith(
                    color: contentColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single-line numeric field for a [FormRow] in the imaging side panel.
///
/// It carries no drawn label — the [FormRow] to its left is the label — so the
/// name reaches assistive tech through [semanticLabel] instead. Edits commit on
/// submit and on blur, the same contract the rows it replaces had.
class InlineNumberField extends StatefulWidget {
  const InlineNumberField({
    super.key,
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
    this.suffix,
  });

  /// The value as it should read when not being edited.
  final String value;

  /// The field's accessible name, e.g. "Gain".
  final String semanticLabel;

  /// Trailing unit, 12 px muted.
  final String? suffix;

  /// Called with the committed text.
  final ValueChanged<String> onChanged;

  @override
  State<InlineNumberField> createState() => _InlineNumberFieldState();
}

class _InlineNumberFieldState extends State<InlineNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(InlineNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  void _commit() {
    if (_controller.text == widget.value) return;
    widget.onChanged(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      child: NightshadeTextField(
        controller: _controller,
        focusNode: _focusNode,
        suffix: widget.suffix,
        mono: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

/// A field-shaped box stating a value the operator cannot type into — the
/// capture format, the save folder, the file-name pattern.
///
/// It wears the same `field` decoration and 32 px height as an editable field,
/// so a form row does not change shape depending on whether its value happens
/// to be editable.
class ReadOnlyField extends StatelessWidget {
  const ReadOnlyField({
    super.key,
    required this.value,
    this.mono = false,
    this.muted = false,
  });

  /// What the field states.
  final String value;

  /// Values that are data (paths, patterns) are mono; prose is not.
  final bool mono;

  /// A prompt standing in for a value that has not been set yet.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final base =
        mono ? NightshadeTypography.inputMono : NightshadeTypography.bodySm;
    return Container(
      height: fieldHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd - 2,
      ),
      alignment: Alignment.centerLeft,
      decoration: NightshadeDecorations.field(colors),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base.copyWith(
          color: muted ? colors.textMuted : colors.textPrimary,
        ),
      ),
    );
  }
}

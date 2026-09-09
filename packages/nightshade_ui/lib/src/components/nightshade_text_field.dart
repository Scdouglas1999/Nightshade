import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_decorations.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Field heights in logical pixels (03 §3.3: `inputHeight` 32, dense 28).
// TODO(observatory): fold into NightshadeTokens.inputHeight/inputHeightSm
const double fieldHeight = 32;
const double fieldHeightDense = 28;

/// Horizontal padding inside a field (`observatory.css` `.field`).
const double fieldHorizontalPadding = 10;

/// Leading icon size inside a field, in logical pixels (05 §8: 14 muted).
const double fieldIconSize = NightshadeTokens.iconXs;

/// A single-line text or number field on the Observatory scale.
///
/// 32px tall, 28 with [dense]. The [NightshadeDecorations.field] face is a
/// `well` fill with a near-invisible resting ring that becomes a real 1px
/// `primary` line on focus and `error` on error — the one place in this
/// language where a border carries state.
///
/// The [label] parameter still renders a caption ABOVE the field for the call
/// sites that have not moved yet; new code puts the label to the LEFT with
/// `FormRow(label: …, child: NightshadeTextField(…))`.
class NightshadeTextField extends StatefulWidget {
  final String? initialValue;
  final String? hint;
  final String? label;
  final IconData? prefixIcon;
  final Widget? suffixWidget;
  final String? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool? autocorrect;
  final bool? enableSuggestions;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? errorText;
  final bool enabled;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;

  /// 28px instead of 32 — for a field inside a toolbar or a dense row.
  final bool dense;

  /// Renders the value in [NightshadeTypography.inputMono] with tabular
  /// figures. Every numeric field sets this, so a column of numbers lines up
  /// digit under digit instead of drifting with the glyph widths.
  final bool mono;

  /// Take focus as soon as the field is mounted. Needed by fields that are the
  /// sole purpose of a dialog, so the user can type immediately.
  final bool autofocus;

  const NightshadeTextField({
    super.key,
    this.initialValue,
    this.hint,
    this.label,
    this.prefixIcon,
    this.suffixWidget,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.obscureText = false,
    this.autocorrect,
    this.enableSuggestions,
    this.keyboardType,
    this.maxLines = 1,
    this.errorText,
    this.enabled = true,
    this.controller,
    this.focusNode,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.dense = false,
    this.mono = false,
    this.autofocus = false,
  });

  /// The field's height in logical pixels. Null for a multi-line field, which
  /// grows with its content.
  double? get height =>
      maxLines == 1 ? (dense ? fieldHeightDense : fieldHeight) : null;

  @override
  State<NightshadeTextField> createState() => _NightshadeTextFieldState();
}

class _NightshadeTextFieldState extends State<NightshadeTextField> {
  late FocusNode _focusNode;
  late TextEditingController _controller;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted || _isFocused == _focusNode.hasFocus) return;
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final decoration = NightshadeDecorations.field(
      colors,
      focused: _isFocused && widget.enabled,
      hasError: hasError,
    );
    final ring = decoration.border!.top.color;

    final textStyle =
        (widget.mono
                ? NightshadeTypography.inputMono
                : NightshadeTypography.input)
            .copyWith(
              color: widget.enabled ? colors.textPrimary : colors.textMuted,
            );

    OutlineInputBorder outline(Color color) => OutlineInputBorder(
      borderRadius: NightshadeTokens.borderRadiusSm,
      borderSide: BorderSide(color: color),
    );

    final field = TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      autocorrect: widget.autocorrect ?? !widget.obscureText,
      enableSuggestions: widget.enableSuggestions ?? !widget.obscureText,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      enabled: widget.enabled,
      style: textStyle,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: textStyle.copyWith(color: colors.textMuted),
        prefixIcon: widget.prefixIcon != null
            ? Icon(
                widget.prefixIcon,
                size: fieldIconSize,
                color: _isFocused ? colors.primary : colors.textMuted,
              )
            : null,
        prefixIconConstraints: const BoxConstraints(
          minWidth: fieldIconSize + fieldHorizontalPadding,
          minHeight: fieldIconSize,
        ),
        suffix: widget.suffixWidget,
        suffixText: widget.suffix,
        suffixStyle: NightshadeTypography.caption.copyWith(
          color: colors.textMuted,
        ),
        filled: true,
        fillColor: decoration.color,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: fieldHorizontalPadding,
        ),
        border: outline(ring),
        enabledBorder: outline(ring),
        focusedBorder: outline(ring),
        disabledBorder: outline(ring),
        errorBorder: outline(colors.error),
        focusedErrorBorder: outline(colors.error),
        // `errorText` is deliberately NOT handed to the decoration: Material
        // then reserves a helper-text row under every field whether or not
        // there is an error, which is exactly the vertical drift a fixed 32px
        // field exists to avoid. The message is rendered below instead.
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.label != null) ...<Widget>[
          Text(
            widget.label!,
            style: NightshadeTypography.caption.copyWith(
              color: _isFocused ? colors.primary : colors.textSecondary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
        ],
        SizedBox(
          height: widget.height,
          // The caption above is a sibling of the field, so the field itself
          // reached assistive tech as an anonymous text box — a settings leaf
          // full of them announced fifteen identical unnamed fields.
          child: Semantics(label: widget.label, child: field),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            widget.errorText!,
            style: NightshadeTypography.captionSm.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}

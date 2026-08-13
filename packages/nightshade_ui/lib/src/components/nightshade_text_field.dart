import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

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
    this.autofocus = false,
  });

  @override
  State<NightshadeTextField> createState() => _NightshadeTextFieldState();
}

class _NightshadeTextFieldState extends State<NightshadeTextField> {
  late FocusNode _focusNode;
  late TextEditingController _controller;
  bool _isFocused = false;
  bool _hasContent = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
    _focusNode.addListener(_handleFocusChange);
    _controller.addListener(_handleContentChange);
    _hasContent = _controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.removeListener(_handleContentChange);
    if (widget.focusNode == null) _focusNode.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  void _handleContentChange() {
    final hasContent = _controller.text.isNotEmpty;
    if (hasContent != _hasContent) {
      setState(() => _hasContent = hasContent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    // Determine colors based on state
    final Color borderColor;
    final Color fillColor;
    final List<BoxShadow>? boxShadow;

    if (!widget.enabled) {
      borderColor = colors.border.withValues(alpha: 0.5);
      fillColor = colors.surface;
      boxShadow = null;
    } else if (hasError) {
      borderColor = colors.error;
      fillColor = colors.surface;
      boxShadow = null;
    } else if (_isFocused) {
      borderColor = colors.primary;
      fillColor = colors.surfaceAlt;
      boxShadow = null;
    } else if (_hasContent) {
      // Filled state - slightly different tint to indicate completion
      borderColor = colors.border;
      fillColor = colors.surfaceElevated;
      boxShadow = null;
    } else {
      // Unfocused empty state
      borderColor = colors.border.withValues(alpha: 0.7);
      fillColor = colors.surface;
      boxShadow = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _isFocused ? colors.primary : colors.textSecondary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
        ],
        AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          curve: NightshadeTokens.curveSnappy,
          decoration: BoxDecoration(
            borderRadius: NightshadeTokens.borderRadiusMd,
            boxShadow: boxShadow,
          ),
          // The caption above is a sibling of the field, so the field itself
          // reached assistive tech as an anonymous text box — a settings leaf
          // full of them announced fifteen identical unnamed fields.
          child: Semantics(
            label: widget.label,
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onFieldSubmitted: widget.onSubmitted,
              textInputAction: widget.textInputAction,
              obscureText: widget.obscureText,
              autocorrect: widget.autocorrect ?? !widget.obscureText,
              enableSuggestions:
                  widget.enableSuggestions ?? !widget.obscureText,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              textAlign: widget.textAlign,
              maxLines: widget.maxLines,
              enabled: widget.enabled,
              style: TextStyle(
                fontSize: 13,
                color: widget.enabled ? colors.textPrimary : colors.textMuted,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        size: NightshadeTokens.iconSm,
                        color: _isFocused
                            ? colors.primary
                            : colors.textSecondary,
                      )
                    : null,
                suffix: widget.suffixWidget,
                suffixText: widget.suffix,
                suffixStyle: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
                filled: true,
                fillColor: fillColor,
                contentPadding: NightshadeTokens.inputPadding,
                border: OutlineInputBorder(
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  borderSide: BorderSide(color: borderColor, width: 1.5),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  borderSide: BorderSide(color: borderColor),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  borderSide: BorderSide(color: colors.error),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  borderSide: BorderSide(color: colors.error, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            widget.errorText!,
            style: TextStyle(fontSize: 11, color: colors.error),
          ),
        ],
      ],
    );
  }
}

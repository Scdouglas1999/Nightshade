import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// Custom checkbox matching Nightshade theme semantics.
class NightshadeCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const NightshadeCheckbox({super.key, required this.value, this.onChanged});

  @override
  State<NightshadeCheckbox> createState() => _NightshadeCheckboxState();
}

class _NightshadeCheckboxState extends State<NightshadeCheckbox> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final isDisabled = widget.onChanged == null;
    final checkColor = colors.onPrimary;

    void toggle() => widget.onChanged!(!widget.value);

    // See the note in nightshade_switch.dart: this was a bare GestureDetector,
    // so the control reported no checked state and could not be focused. A
    // checkbox that a keyboard cannot reach is a checkbox that some users simply
    // do not have.
    return Semantics(
      checked: widget.value,
      enabled: !isDisabled,
      onTap: isDisabled ? null : toggle,
      child: FocusableActionDetector(
        enabled: !isDisabled,
        mouseCursor: isDisabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowFocusHighlight: (focused) => setState(() => _isFocused = focused),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: isDisabled ? null : toggle,
          // See nightshade_switch.dart: a second tap node here reads to AT-SPI
          // as an unnamed disabled panel beside the checkbox.
          excludeFromSemantics: true,
          child: AnimatedContainer(
            duration: NightshadeTokens.durationQuick,
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: widget.value
                  ? (isDisabled ? colors.surfaceHover : colors.primary)
                  : Colors.transparent,
              borderRadius: NightshadeTokens.borderRadiusXs,
              border: Border.all(
                color: _isFocused
                    ? colors.primary
                    : widget.value
                    ? (isDisabled ? colors.border : colors.primary)
                    : colors.border,
                width: 2,
              ),
            ),
            child: widget.value
                ? Icon(
                    LucideIcons.check,
                    size: 12,
                    color: isDisabled ? colors.textMuted : checkColor,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class NodeQuickTimeButton extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final VoidCallback onPressed;

  const NodeQuickTimeButton({
    super.key,
    required this.colors,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: Responsive.spacing(context, 8),
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class NodePropertyField extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final Widget child;

  const NodePropertyField({
    super.key,
    required this.colors,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: Responsive.spacing(context, 6)),
          child,
        ],
      ),
    );
  }
}

class NodeTextInput extends StatefulWidget {
  final NightshadeColors colors;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int? maxLines;

  const NodeTextInput({
    super.key,
    required this.colors,
    required this.value,
    required this.onChanged,
    this.hint,
    this.maxLines,
  });

  @override
  State<NodeTextInput> createState() => _NodeTextInputState();
}

class _NodeTextInputState extends State<NodeTextInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(NodeTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputFontSize = Responsive.fontSize(context, 13);
    final inputPaddingH = Responsive.spacing(context, 12);
    final inputPaddingV = Responsive.spacing(context, 10);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: inputPaddingH),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.colors.border),
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        maxLines: widget.maxLines ?? 1,
        minLines: widget.maxLines != null ? 1 : null,
        style: TextStyle(
          fontSize: inputFontSize,
          color: widget.colors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: inputFontSize,
            color: widget.colors.textMuted,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: inputPaddingV),
        ),
      ),
    );
  }
}

class NodeNumberInput extends StatefulWidget {
  final NightshadeColors colors;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final double? min;
  final double? max;
  final int decimals;

  const NodeNumberInput({
    super.key,
    required this.colors,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min,
    this.max,
    this.decimals = 0,
  });

  @override
  State<NodeNumberInput> createState() => _NodeNumberInputState();
}

class _NodeNumberInputState extends State<NodeNumberInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.decimals == 0
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimals),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final hadFocus = _hasFocus;
    _hasFocus = _focusNode.hasFocus;

    // When losing focus, update to the canonical value format
    if (hadFocus && !_hasFocus) {
      final newText = widget.decimals == 0
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimals);
      if (_controller.text != newText) {
        _controller.text = newText;
      }
    }
  }

  @override
  void didUpdateWidget(NodeNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update text if the field doesn't have focus (user isn't typing)
    if (!_hasFocus && oldWidget.value != widget.value) {
      final newText = widget.decimals == 0
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimals);
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputFontSize = Responsive.fontSize(context, 13);
    final suffixFontSize = Responsive.fontSize(context, 12);
    final inputPaddingH = Responsive.spacing(context, 12);
    final inputPaddingV = Responsive.spacing(context, 10);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: inputPaddingH),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null) {
                  var clamped = parsed;
                  if (widget.min != null) {
                    clamped = clamped.clamp(widget.min!, double.infinity);
                  }
                  if (widget.max != null) {
                    clamped =
                        clamped.clamp(double.negativeInfinity, widget.max!);
                  }
                  widget.onChanged(clamped);
                }
              },
              style: TextStyle(
                fontSize: inputFontSize,
                color: widget.colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: inputPaddingV),
              ),
            ),
          ),
          if (widget.suffix != null)
            Text(
              widget.suffix!,
              style: TextStyle(
                fontSize: suffixFontSize,
                color: widget.colors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class NodeNumberInputWithHint extends StatefulWidget {
  final NightshadeColors colors;
  final double value;
  final ValueChanged<double> onChanged;
  final double? min;
  final double? max;
  final String? hintText;

  /// Whether the current value comes from a profile default rather than
  /// an explicit user override. When true, the value text is rendered in
  /// a muted color to visually distinguish it from user-set values.
  final bool isProfileDefault;

  const NodeNumberInputWithHint({
    super.key,
    required this.colors,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.hintText,
    this.isProfileDefault = false,
  });

  @override
  State<NodeNumberInputWithHint> createState() =>
      _NodeNumberInputWithHintState();
}

class _NodeNumberInputWithHintState extends State<NodeNumberInputWithHint> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value.toInt().toString(),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final hadFocus = _hasFocus;
    _hasFocus = _focusNode.hasFocus;

    // When losing focus, update to the canonical value format
    if (hadFocus && !_hasFocus) {
      final newText = widget.value.toInt().toString();
      if (_controller.text != newText) {
        _controller.text = newText;
      }
    }
  }

  @override
  void didUpdateWidget(NodeNumberInputWithHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update text if the field doesn't have focus (user isn't typing)
    if (!_hasFocus && oldWidget.value != widget.value) {
      final newText = widget.value.toInt().toString();
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When showing a profile default, use a muted text color to visually
    // distinguish it from explicitly user-set values.
    final textColor = widget.isProfileDefault
        ? widget.colors.textSecondary
        : widget.colors.textPrimary;

    final inputFontSize = Responsive.fontSize(context, 13);
    final hintFontSize = Responsive.fontSize(context, 12);
    final profileFontSize = Responsive.fontSize(context, 10);
    final inputPaddingH = Responsive.spacing(context, 12);
    final inputPaddingV = Responsive.spacing(context, 10);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: inputPaddingH),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isProfileDefault
              ? widget.colors.border.withValues(alpha: 0.5)
              : widget.colors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null) {
                  var clamped = parsed;
                  if (widget.min != null) {
                    clamped = clamped.clamp(widget.min!, double.infinity);
                  }
                  if (widget.max != null) {
                    clamped =
                        clamped.clamp(double.negativeInfinity, widget.max!);
                  }
                  widget.onChanged(clamped);
                }
              },
              style: TextStyle(
                fontSize: inputFontSize,
                color: textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: inputPaddingV),
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: hintFontSize,
                  color: widget.colors.textMuted,
                ),
              ),
            ),
          ),
          // Show profile indicator when using a profile default
          if (widget.isProfileDefault && widget.hintText != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'profile',
                style: TextStyle(
                  fontSize: profileFontSize,
                  fontWeight: FontWeight.w500,
                  color: widget.colors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NodeToggleSwitch extends StatelessWidget {
  final NightshadeColors colors;
  final bool value;
  final ValueChanged<bool> onChanged;

  const NodeToggleSwitch({
    super.key,
    required this.colors,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? colors.primary : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? colors.primary : colors.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colors.background,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NodeDropdown<T> extends StatelessWidget {
  final NightshadeColors colors;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  const NodeDropdown({
    super.key,
    required this.colors,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dropdownFontSize = Responsive.fontSize(context, 13);
    final dropdownIconSize = Responsive.iconSize(context, 16);
    final dropdownPaddingH = Responsive.spacing(context, 12);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dropdownPaddingH),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(
            LucideIcons.chevronDown,
            size: dropdownIconSize,
            color: colors.textMuted,
          ),
          dropdownColor: colors.surface,
          style: TextStyle(
            fontSize: dropdownFontSize,
            color: colors.textPrimary,
          ),
          items: items.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(labelBuilder(item)),
            );
          }).toList(),
          onChanged: (newValue) {
            if (newValue != null) onChanged(newValue);
          },
        ),
      ),
    );
  }
}

class NodeDangerButton extends StatefulWidget {
  final NightshadeColors colors;
  final String label;
  final IconData icon;
  // Nullable so callers can disable the button when the sequence is
  // locked (e.g. running). `_NodeDangerButtonState` swallows clicks when
  // onPressed is null.
  final VoidCallback? onPressed;

  const NodeDangerButton({
    super.key,
    required this.colors,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<NodeDangerButton> createState() => _NodeDangerButtonState();
}

class _NodeDangerButtonState extends State<NodeDangerButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final btnFontSize = Responsive.fontSize(context, 13);
    final btnIconSize = Responsive.iconSize(context, 15);
    final btnPaddingV = Responsive.spacing(context, 12);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(vertical: btnPaddingV),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.error.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? widget.colors.error : widget.colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: btnIconSize,
                color: _isHovered
                    ? widget.colors.error
                    : widget.colors.textSecondary,
              ),
              SizedBox(width: Responsive.spacing(context, 8)),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: btnFontSize,
                  fontWeight: FontWeight.w500,
                  color: _isHovered
                      ? widget.colors.error
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive section header used consistently across all property panels.
///
/// Replaces the ad-hoc `Text(..., fontSize: 12, fontWeight: w600)` pattern
/// with a single widget that scales for high-res desktop displays.
class NodeSectionHeader extends StatelessWidget {
  final NightshadeColors colors;
  final String label;

  const NodeSectionHeader({
    super.key,
    required this.colors,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: Responsive.fontSize(context, 13),
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
    );
  }
}

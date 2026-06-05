// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// Reusable form primitives shared by every per-node property widget: quick-time buttons, the property field wrapper, text/number/toggle/dropdown inputs and their state classes, the destructive-action button, the number-with-hint variant, and the small node-type badge used in headers.
part of '../node_properties_panel.dart';

class _QuickTimeButton extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final VoidCallback onPressed;

  const _QuickTimeButton({
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: NightshadeTypography.labelQuiet.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}


class _NodeTypeBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _NodeTypeBadge({required this.colors, required this.node});

  Color _getCategoryColor() {
    switch (node.category) {
      case NodeCategory.instruction:
        return colors.primary;
      case NodeCategory.trigger:
        return colors.warning;
      case NodeCategory.logic:
        return colors.accent;
      case NodeCategory.target:
        return colors.warning;
    }
  }

  IconData _getIcon() {
    switch (node.iconName) {
      case 'target':
        return LucideIcons.target;
      case 'camera':
        return LucideIcons.camera;
      case 'circle':
        return LucideIcons.circle;
      case 'shuffle':
        return LucideIcons.shuffle;
      case 'compass':
        return LucideIcons.compass;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'parking-circle':
        return LucideIcons.parkingCircle;
      case 'unlock':
        return LucideIcons.unlock;
      case 'focus':
        return LucideIcons.focus;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'flame':
        return LucideIcons.flame;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'repeat':
        return LucideIcons.repeat;
      case 'layers':
        return LucideIcons.layers;
      case 'git-merge':
        return LucideIcons.gitMerge;
      case 'git-branch':
        return LucideIcons.gitBranch;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'clock':
        return LucideIcons.clock;
      case 'timer':
        return LucideIcons.timer;
      case 'bell':
        return LucideIcons.bell;
      case 'code':
        return LucideIcons.code;
      default:
        return LucideIcons.box;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getCategoryColor();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Icon(_getIcon(), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.nodeType,
                  style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
                ),
                Text(
                  node.category.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Property field wrapper

class _PropertyField extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final Widget child;

  const _PropertyField({
    required this.colors,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _TextInput extends StatefulWidget {
  final NightshadeColors colors;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int? maxLines;

  const _TextInput({
    required this.colors,
    required this.value,
    required this.onChanged,
    this.hint,
    this.maxLines,
  });

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: widget.colors.border),
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        maxLines: widget.maxLines ?? 1,
        minLines: widget.maxLines != null ? 1 : null,
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize13,
          color: widget.colors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
            color: widget.colors.textMuted,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _NumberInput extends StatefulWidget {
  final NightshadeColors colors;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final double? min;
  final double? max;
  final int decimals;

  const _NumberInput({
    required this.colors,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min,
    this.max,
    this.decimals = 0,
  });

  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
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
  void didUpdateWidget(_NumberInput oldWidget) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                fontSize: NightshadeTypography.fontSize13,
                color: widget.colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (widget.suffix != null)
            Text(
              widget.suffix!,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: widget.colors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  final NightshadeColors colors;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleSwitch({
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
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
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
              color: colors.surfaceElevated,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colors.background.withValues(alpha: 0.1),
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

class _Dropdown<T> extends StatelessWidget {
  final NightshadeColors colors;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  const _Dropdown({
    required this.colors,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: colors.textMuted,
          ),
          dropdownColor: colors.surface,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
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

class _DangerButton extends StatefulWidget {
  final NightshadeColors colors;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _DangerButton({
    required this.colors,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<_DangerButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.error.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(
              color: _isHovered ? widget.colors.error : widget.colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: _isHovered
                    ? widget.colors.error
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: NightshadeTypography.labelSm.copyWith(color: _isHovered
                      ? widget.colors.error
                      : widget.colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

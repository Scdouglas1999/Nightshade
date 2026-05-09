import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

class NightshadeSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const NightshadeSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<NightshadeSwitch> createState() => _NightshadeSwitchState();
}

class _NightshadeSwitchState extends State<NightshadeSwitch> {
  bool _isHovered = false;

  /// Creates a slightly lighter shade of the given color
  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;
    final isEnabled = widget.enabled && widget.onChanged != null;

    // Track gradient for active state
    final trackDecoration = widget.value
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _lightenColor(colors.primary, 0.05),
                colors.primary,
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.3),
            ),
          )
        : BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.border,
            ),
            // Inner shadow for recessed feel when off
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 2,
                offset: const Offset(0, 1),
                blurStyle: BlurStyle.inner,
              ),
            ],
          );

    // Thumb with highlight edge
    final thumbColor = widget.value
        ? theme.colorScheme.onPrimary
        : isEnabled
            ? colors.textSecondary
            : colors.textMuted;

    return MouseRegion(
      onEnter: isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: isEnabled ? () => widget.onChanged!(!widget.value) : null,
        child: Opacity(
          opacity: isEnabled ? 1.0 : NightshadeTokens.opacityDisabled,
          child: AnimatedContainer(
            duration: NightshadeTokens.durationNormal,
            curve:
                NightshadeTokens.curveSettle, // Overshoot for satisfying snap
            width: 44,
            height: 24,
            padding: const EdgeInsets.all(2),
            decoration: trackDecoration,
            child: AnimatedAlign(
              duration: NightshadeTokens.durationNormal,
              curve: NightshadeTokens.curveSettle, // Overshoot animation
              alignment:
                  widget.value ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: NightshadeTokens.durationQuick,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: thumbColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    // Shadow under thumb
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                    // Subtle glow on hover
                    if (_isHovered && widget.value)
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                  ],
                  // Highlight edge at top (catches light)
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _lightenColor(thumbColor, 0.15),
                      thumbColor,
                    ],
                    stops: const [0.0, 0.3],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

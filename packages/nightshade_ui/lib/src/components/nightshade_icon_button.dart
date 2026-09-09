import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import 'nightshade_tooltip.dart';

/// The three icon-button sizes.
enum IconButtonSize {
  /// 32 — top bar, page header, capture bar.
  md,

  /// 28 — toolbars.
  sm,

  /// 36 — the side-panel section strip.
  strip,
}

/// A square, ghost-styled icon button — the ONE icon control in the app.
///
/// [tooltip] is required, not optional. An icon with no words is only legible
/// to someone who already knows what it does; making the tooltip part of the
/// constructor is what stops the next 178 `IconButton(` migrations from
/// shipping unlabelled glyphs, and it doubles as the semantics label so the
/// control has a name in the accessibility tree as well as under the pointer.
class NightshadeIconButton extends StatefulWidget {
  const NightshadeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = IconButtonSize.md,
    this.selected = false,
    this.color,
  });

  /// The glyph. Lucide only — never `Icons.*`.
  final IconData icon;

  /// What the button does, in sentence case. Shown on hover and published as
  /// the control's accessible name.
  final String tooltip;

  /// Null disables the button (40% opacity, no colour change).
  final VoidCallback? onPressed;

  /// Which of the three square sizes to draw.
  final IconButtonSize size;

  /// Selected: `primary` at [NightshadeTokens.opacityAccentTint] fill and a
  /// `primary` glyph.
  final bool selected;

  /// Overrides the resting glyph colour — a `destructive` action, a status
  /// tint. Hover and selection still apply on top.
  final Color? color;

  /// The button's edge length in logical pixels.
  double get extent => switch (size) {
    IconButtonSize.md => NightshadeTokens.iconButtonSize,
    IconButtonSize.sm => NightshadeTokens.iconButtonSizeSm,
    IconButtonSize.strip => NightshadeTokens.iconButtonSizeStrip,
  };

  /// The glyph size in logical pixels.
  double get iconSize => switch (size) {
    IconButtonSize.md => _iconButtonGlyphMd,
    IconButtonSize.sm => _iconButtonGlyphSm,
    IconButtonSize.strip => _iconButtonGlyphStrip,
  };

  @override
  State<NightshadeIconButton> createState() => _NightshadeIconButtonState();
}

/// Glyph sizes inside an icon button, in logical pixels (`observatory.css`
/// `.iconbtn .i` 17, `.btn .i` 15, `.sidepanel .strip .item .i` 17). The icon
/// scale has 14 and 16 but neither 15 nor 17.
// TODO(observatory): promote to NightshadeTokens.iconGlyphMd/Sm/Strip
const double _iconButtonGlyphMd = 17;
const double _iconButtonGlyphSm = 15;
const double _iconButtonGlyphStrip = 17;

class _NightshadeIconButtonState extends State<NightshadeIconButton> {
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (!mounted || _hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final disabled = widget.onPressed == null;

    final Color foreground;
    if (widget.selected) {
      foreground = colors.primary;
    } else if (widget.color != null) {
      foreground = widget.color!;
    } else if (_hovered && !disabled) {
      foreground = colors.textPrimary;
    } else {
      foreground = colors.textSecondary;
    }

    final Color fill;
    if (widget.selected) {
      fill = colors.primary.withValues(
        alpha: _hovered && !disabled
            ? NightshadeTokens.opacityAccentTintHover
            : NightshadeTokens.opacityAccentTint,
      );
    } else if (_hovered && !disabled) {
      fill = colors.surfaceHover;
    } else {
      fill = Colors.transparent;
    }

    // The BOX is a SizedBox and the FILL is the animated part. Animating the
    // width and height instead would make a size change tween — and a size is
    // not a state, it is what this button is.
    final Widget button = SizedBox(
      width: widget.extent,
      height: widget.extent,
      child: AnimatedContainer(
        duration: NightshadeTokens.durationFast,
        curve: NightshadeTokens.curveStandard,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: NightshadeTokens.borderRadiusSm,
          border: Border.all(
            color: _focused && !disabled ? colors.primary : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(widget.icon, size: widget.iconSize, color: foreground),
      ),
    );

    // Desktop pointer targets may be 28–36 px (03 §3.3), but below the tablet
    // breakpoint the same button is a TOUCH target and must offer 48 dp. The
    // visual box keeps its size; only the hit area grows.
    final touchFloor =
        MediaQuery.sizeOf(context).width < NightshadeTokens.breakpointTablet;
    final Widget hitArea = touchFloor
        ? ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            child: Center(child: button),
          )
        : button;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.tooltip,
      child: NightshadeTooltip(
        message: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          cursor: disabled
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: FocusableActionDetector(
            enabled: !disabled,
            onShowFocusHighlight: (value) {
              if (!mounted || _focused == value) return;
              setState(() => _focused = value);
            },
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onPressed?.call();
                  return null;
                },
              ),
              ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
                onInvoke: (_) {
                  widget.onPressed?.call();
                  return null;
                },
              ),
            },
            // Every tap callback is dropped when disabled, not just onTap: a
            // GestureDetector that keeps one wired publishes a live tap action
            // beside a correct isEnabled=false flag, which the Linux AT-SPI
            // bridge reports as an enabled button.
            child: GestureDetector(
              onTap: disabled ? null : widget.onPressed,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: disabled ? NightshadeTokens.opacityDisabled : 1,
                  child: hitArea,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

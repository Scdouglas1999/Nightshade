import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import '../utils/touch_target.dart';

enum ButtonVariant { primary, outline, ghost, destructive }

enum ButtonSize { small, medium, large }

/// Solid-fill button with subtle borders and pressed darkening.
class NightshadeButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool isLoading;

  const NightshadeButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.medium,
    this.isLoading = false,
  });

  @override
  State<NightshadeButton> createState() => _NightshadeButtonState();
}

/// How far outside the button's own box the keyboard focus ring is drawn, and
/// how thick that stroke is, in logical pixels. Kept outside the box so the
/// ring never overlaps the label and never changes the control's metrics.
const double _focusRingOffset = 2.0;
const double _focusRingWidth = 2.0;

class _NightshadeButtonState extends State<NightshadeButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: NightshadeTokens.durationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: NightshadeTokens.curveSnappy,
      ),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (!mounted || _isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _handleTapDown(TapDownDetails details) {
    if (!mounted || widget.onPressed == null || widget.isLoading) return;
    setState(() => _isPressed = true);
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails details) => _releasePress();
  void _handleTapCancel() => _releasePress();

  void _releasePress() {
    if (!mounted || !_isPressed) return;
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  /// Smallest interactive box this button may occupy, in logical pixels.
  ///
  /// The visual sizes are deliberately compact for dense desktop panels — 28px
  /// tall for `small`, 40px for the DEFAULT `medium` — but both are under the
  /// platform touch minimums (Android 48, iOS 44), which
  /// `flutter_test`'s tap-target guidelines flag. On a tablet, which is a primary
  /// way this app is driven, that is a genuinely hard-to-hit control.
  ///
  /// Applied only on touch platforms: growing desktop buttons to 48px would
  /// re-flow every dense panel for no accessibility gain, since a mouse has none
  /// of the imprecision the guideline exists to absorb.
  double get _minInteractiveExtent => NightshadeTouchTarget.minExtent(context);

  EdgeInsets get _padding {
    return switch (widget.size) {
      ButtonSize.small => const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm + 2,
        vertical: NightshadeTokens.spaceSm - 2,
      ),
      ButtonSize.medium => const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd + 2,
        vertical: NightshadeTokens.spaceSm + 2,
      ),
      ButtonSize.large => const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg + 2,
        vertical: NightshadeTokens.spaceMd + 2,
      ),
    };
  }

  TextStyle get _textStyle {
    return switch (widget.size) {
      ButtonSize.small => NightshadeTypography.captionSm.copyWith(
        fontWeight: FontWeight.w500,
      ),
      ButtonSize.medium => NightshadeTypography.buttonSm,
      ButtonSize.large => NightshadeTypography.button,
    };
  }

  double get _iconSize {
    return switch (widget.size) {
      ButtonSize.small => NightshadeTokens.iconXs - 2,
      ButtonSize.medium => NightshadeTokens.iconXs,
      ButtonSize.large => NightshadeTokens.iconSm,
    };
  }

  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nightshadeColors;
    final colorScheme = theme.colorScheme;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    final Color foregroundColor;
    final Color borderColor;
    Color? flatColor;

    switch (widget.variant) {
      case ButtonVariant.primary:
        (flatColor, foregroundColor, borderColor) = _buildFilled(
          colors.primary,
          colors,
          colorScheme.onPrimary,
          isDisabled: isDisabled,
        );
      case ButtonVariant.destructive:
        (flatColor, foregroundColor, borderColor) = _buildFilled(
          colors.error,
          colors,
          colorScheme.onError,
          isDisabled: isDisabled,
        );
      case ButtonVariant.outline:
        flatColor = _isHovered && !isDisabled
            ? colors.primary.withValues(alpha: 0.08)
            : Colors.transparent;
        foregroundColor = isDisabled ? colors.textMuted : colors.textPrimary;
        borderColor = _isHovered && !isDisabled
            ? colors.primary.withValues(alpha: 0.45)
            : colors.border;
      case ButtonVariant.ghost:
        flatColor = _isHovered && !isDisabled
            ? colors.surfaceHover
            : Colors.transparent;
        foregroundColor = isDisabled ? colors.textMuted : colors.textSecondary;
        borderColor = Colors.transparent;
    }

    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _releasePress();
        },
        cursor: isDisabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        // A bare GestureDetector has no focus node, so every NightshadeButton
        // in the app was invisible to Tab traversal and could not be activated
        // from the keyboard at all. Live proof: in the 13-step setup wizard the
        // ONLY control Tab could reach was the header's "Skip onboarding"
        // TextButton — three consecutive Tab presses produced a pixel-identical
        // frame, and Return abandoned setup. The wizard was impossible to
        // complete without a mouse.
        child: FocusableActionDetector(
          enabled: !isDisabled,
          onShowFocusHighlight: (value) {
            if (!mounted || _isFocused == value) return;
            setState(() => _isFocused = value);
          },
          actions: <Type, Action<Intent>>{
            // Enter and Space both arrive as ActivateIntent from the app-level
            // default shortcuts; ButtonActivateIntent is the web variant.
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
          // Every tap callback is dropped when disabled, not just `onTap`.
          // `GestureDetector` registers a `TapGestureRecognizer` — and with it
          // a `SemanticsAction.tap` on this node — if ANY of onTapDown/onTapUp/
          // onTapCancel/onTap is non-null. A disabled button that leaves one
          // wired publishes an actionable node: correct
          // `hasEnabledState`/`isEnabled` flags with a live tap action beside
          // them, which the Linux AT-SPI bridge reports as an enabled
          // `button: Start Alignment` carrying no disabled marker.
          child: GestureDetector(
            onTapDown: isDisabled ? null : _handleTapDown,
            onTapUp: isDisabled ? null : _handleTapUp,
            onTapCancel: isDisabled ? null : _handleTapCancel,
            onTap: isDisabled ? null : widget.onPressed,
            child: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                );
              },
              // The focus ring is a STROKE painted in an overflowing Positioned
              // rather than a spread `BoxShadow` on the button itself. A spread
              // shadow is a *filled* round-rect painted behind the box, so on the
              // `ghost` and `outline` variants — whose fill is transparent until
              // hover — it showed straight through the middle and turned the
              // whole control into a solid primary slab with unreadable label
              // text. Stroking it keeps the interior untouched for every variant.
              //
              // The Stack is unconditional (so the AnimatedContainer keeps its
              // element slot, and with it the in-flight colour animation) and
              // sizes itself to its only non-positioned child, so mounting the
              // ring costs no layout: `Clip.none` lets it draw the 2px outside.
              child: Stack(
                clipBehavior: Clip.none,
                // passthrough, NOT the default loose fit: a loose Stack strips
                // the incoming minimum, so a button handed tight constraints —
                // `Expanded(child: NightshadeButton(...))`, a stretched column —
                // would silently shrink to its content the moment the ring was
                // introduced. passthrough hands the AnimatedContainer exactly
                // the constraints it saw before this Stack existed.
                fit: StackFit.passthrough,
                children: [
                  AnimatedContainer(
                    duration: NightshadeTokens.durationQuick,
                    curve: NightshadeTokens.curveSnappy,
                    // Floor the tappable box on touch platforms. `constraints`
                    // rather than extra padding so the fill and border grow with
                    // it and the whole visible control is the target, not a small
                    // shape inside a larger invisible one.
                    constraints: BoxConstraints(
                      minWidth: _minInteractiveExtent,
                      minHeight: _minInteractiveExtent,
                    ),
                    decoration: BoxDecoration(
                      color: flatColor,
                      borderRadius: NightshadeTokens.borderRadiusSm,
                      border: Border.all(color: borderColor),
                    ),
                    child: Padding(
                      padding: _padding,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.isLoading) ...[
                            SizedBox(
                              width: _iconSize,
                              height: _iconSize,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  foregroundColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: NightshadeTokens.spaceSm),
                          ] else if (widget.icon != null) ...[
                            Icon(
                              widget.icon,
                              size: _iconSize,
                              color: foregroundColor,
                            ),
                            const SizedBox(width: NightshadeTokens.spaceSm - 2),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              style: _textStyle.copyWith(
                                color: foregroundColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isFocused && !isDisabled)
                    Positioned(
                      left: -_focusRingOffset,
                      top: -_focusRingOffset,
                      right: -_focusRingOffset,
                      bottom: -_focusRingOffset,
                      // The ring sits over the button's own hit box, so it must
                      // not eat the pointer events the button exists to receive.
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusSm + _focusRingOffset,
                            ),
                            border: Border.all(
                              color: colors.primary,
                              width: _focusRingWidth,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color?, Color, Color) _buildFilled(
    Color base,
    NightshadeColors colors,
    Color onColor, {
    required bool isDisabled,
  }) {
    if (isDisabled) {
      return (colors.surfaceAlt, colors.textMuted, colors.border);
    }
    if (_isPressed) {
      return (_darkenColor(base, 0.1), onColor, _darkenColor(base, 0.15));
    }
    if (_isHovered) {
      return (_lightenColor(base, 0.04), onColor, _darkenColor(base, 0.08));
    }
    return (base, onColor, _darkenColor(base, 0.12));
  }
}

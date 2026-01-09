import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// Animation style for value changes
enum ValueAnimationStyle {
  /// Brief highlight flash on change
  flash,
  /// Smooth interpolation between values (for numeric values)
  interpolate,
  /// Color shift based on value direction (up = green, down = red)
  directional,
}

/// A widget that animates value changes with visual feedback.
///
/// Use this for real-time data displays like temperatures, coordinates,
/// exposure times, and other frequently updating values.
class AnimatedValue extends StatefulWidget {
  /// The current value to display
  final String value;

  /// Animation style to use
  final ValueAnimationStyle style;

  /// Text style for the value
  final TextStyle? textStyle;

  /// Color for the highlight flash (defaults to primary)
  final Color? highlightColor;

  /// Duration of the highlight animation
  final Duration highlightDuration;

  /// For directional style: color when value increases
  final Color? increaseColor;

  /// For directional style: color when value decreases
  final Color? decreaseColor;

  /// Whether to use monospace font features
  final bool useTabularFigures;

  const AnimatedValue({
    super.key,
    required this.value,
    this.style = ValueAnimationStyle.flash,
    this.textStyle,
    this.highlightColor,
    this.highlightDuration = NightshadeTokens.durationNormal,
    this.increaseColor,
    this.decreaseColor,
    this.useTabularFigures = true,
  });

  @override
  State<AnimatedValue> createState() => _AnimatedValueState();
}

class _AnimatedValueState extends State<AnimatedValue>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _highlightAnimation;
  double? _previousNumericValue;
  int _direction = 0; // -1 = decrease, 0 = no change, 1 = increase

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.highlightDuration,
    );
    _highlightAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _previousNumericValue = double.tryParse(widget.value);
  }

  @override
  void didUpdateWidget(AnimatedValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      // Determine direction for directional style
      final newNumeric = double.tryParse(widget.value);
      if (_previousNumericValue != null && newNumeric != null) {
        if (newNumeric > _previousNumericValue!) {
          _direction = 1;
        } else if (newNumeric < _previousNumericValue!) {
          _direction = -1;
        } else {
          _direction = 0;
        }
        _previousNumericValue = newNumeric;
      }

      // Trigger highlight animation
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Determine highlight color based on style
    Color effectiveHighlightColor;
    switch (widget.style) {
      case ValueAnimationStyle.flash:
        effectiveHighlightColor = widget.highlightColor ?? colors.primary;
      case ValueAnimationStyle.interpolate:
        effectiveHighlightColor = widget.highlightColor ?? colors.primary;
      case ValueAnimationStyle.directional:
        if (_direction > 0) {
          effectiveHighlightColor = widget.increaseColor ?? colors.success;
        } else if (_direction < 0) {
          effectiveHighlightColor = widget.decreaseColor ?? colors.error;
        } else {
          effectiveHighlightColor = widget.highlightColor ?? colors.primary;
        }
    }

    // Build text style with tabular figures for numeric alignment
    final baseStyle = widget.textStyle ?? TextStyle(color: colors.textPrimary);
    final effectiveStyle = widget.useTabularFigures
        ? baseStyle.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          )
        : baseStyle;

    return AnimatedBuilder(
      animation: _highlightAnimation,
      builder: (context, child) {
        // Calculate highlight opacity (flash then fade)
        final highlightOpacity = (1 - _highlightAnimation.value) * 0.3;

        return Container(
          decoration: highlightOpacity > 0.01
              ? BoxDecoration(
                  color: effectiveHighlightColor.withValues(alpha: highlightOpacity),
                  borderRadius: NightshadeTokens.borderRadiusXs,
                )
              : null,
          padding: highlightOpacity > 0.01
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
              : EdgeInsets.zero,
          child: Text(
            widget.value,
            style: effectiveStyle.copyWith(
              color: highlightOpacity > 0.01
                  ? Color.lerp(
                      effectiveStyle.color,
                      effectiveHighlightColor,
                      (1 - _highlightAnimation.value) * 0.5,
                    )
                  : effectiveStyle.color,
            ),
          ),
        );
      },
    );
  }
}

/// A widget that smoothly interpolates between numeric values.
///
/// Unlike [AnimatedValue], this widget smoothly animates the displayed
/// number rather than just flashing on change. Best for monotonic values
/// like temperatures and counts that change gradually.
class InterpolatedValue extends StatefulWidget {
  /// The target value to animate towards
  final double value;

  /// Format function for displaying the value
  final String Function(double value)? formatter;

  /// Text style for the value
  final TextStyle? textStyle;

  /// Duration of the interpolation animation
  final Duration duration;

  /// Whether to use monospace font features
  final bool useTabularFigures;

  const InterpolatedValue({
    super.key,
    required this.value,
    this.formatter,
    this.textStyle,
    this.duration = NightshadeTokens.durationNormal,
    this.useTabularFigures = true,
  });

  @override
  State<InterpolatedValue> createState() => _InterpolatedValueState();
}

class _InterpolatedValueState extends State<InterpolatedValue>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _valueAnimation;
  double _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _valueAnimation = Tween<double>(
      begin: widget.value,
      end: widget.value,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: NightshadeTokens.curvePrecise,
    ));
  }

  @override
  void didUpdateWidget(InterpolatedValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _valueAnimation = Tween<double>(
        begin: _previousValue,
        end: widget.value,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: NightshadeTokens.curvePrecise,
      ));
      _controller.forward(from: 0.0);
      _previousValue = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatValue(double value) {
    if (widget.formatter != null) {
      return widget.formatter!(value);
    }
    // Default formatting: 1 decimal place
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final baseStyle = widget.textStyle ?? TextStyle(color: colors.textPrimary);
    final effectiveStyle = widget.useTabularFigures
        ? baseStyle.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          )
        : baseStyle;

    return AnimatedBuilder(
      animation: _valueAnimation,
      builder: (context, child) {
        return Text(
          _formatValue(_valueAnimation.value),
          style: effectiveStyle,
        );
      },
    );
  }
}

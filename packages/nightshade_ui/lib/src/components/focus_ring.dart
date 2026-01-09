import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// A wrapper that adds a custom focus ring with accent color glow.
///
/// Use this to wrap interactive elements for consistent accessibility
/// styling across the app. The focus ring animates in smoothly and
/// uses the theme's accent color.
class FocusRing extends StatefulWidget {
  /// The child widget to wrap
  final Widget child;

  /// Focus node to track (optional, creates one if not provided)
  final FocusNode? focusNode;

  /// Border radius for the focus ring
  final BorderRadius? borderRadius;

  /// Color for the focus ring (defaults to primary)
  final Color? focusColor;

  /// Whether to show the ring only on keyboard focus
  final bool keyboardOnly;

  /// Padding between the child and the focus ring
  final double ringPadding;

  /// Blur radius of the focus glow
  final double glowRadius;

  const FocusRing({
    super.key,
    required this.child,
    this.focusNode,
    this.borderRadius,
    this.focusColor,
    this.keyboardOnly = true,
    this.ringPadding = 2.0,
    this.glowRadius = 4.0,
  });

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing>
    with SingleTickerProviderStateMixin {
  late FocusNode _focusNode;
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);

    _controller = AnimationController(
      vsync: this,
      duration: NightshadeTokens.durationFast,
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(FocusRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final hasFocus = _focusNode.hasFocus;

    // Check if focus is from keyboard (not mouse/touch)
    if (widget.keyboardOnly) {
      final focusHighlightMode = FocusManager.instance.highlightMode;
      final isKeyboardFocus = focusHighlightMode == FocusHighlightMode.traditional;

      if (hasFocus && isKeyboardFocus) {
        setState(() => _isFocused = true);
        _controller.forward();
      } else {
        _controller.reverse().then((_) {
          if (mounted) setState(() => _isFocused = false);
        });
      }
    } else {
      if (hasFocus) {
        setState(() => _isFocused = true);
        _controller.forward();
      } else {
        _controller.reverse().then((_) {
          if (mounted) setState(() => _isFocused = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final effectiveFocusColor = widget.focusColor ?? colors.primary;
    final effectiveRadius = widget.borderRadius ?? NightshadeTokens.borderRadiusMd;

    return Focus(
      focusNode: _focusNode,
      child: AnimatedBuilder(
        animation: _opacityAnimation,
        builder: (context, child) {
          return Container(
            padding: EdgeInsets.all(widget.ringPadding),
            decoration: _isFocused || _opacityAnimation.value > 0
                ? BoxDecoration(
                    borderRadius: effectiveRadius,
                    border: Border.all(
                      color: effectiveFocusColor.withValues(
                        alpha: _opacityAnimation.value * 0.6,
                      ),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: effectiveFocusColor.withValues(
                          alpha: _opacityAnimation.value * 0.3,
                        ),
                        blurRadius: widget.glowRadius,
                        spreadRadius: 0,
                      ),
                    ],
                  )
                : null,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A builder that provides focus state for custom focus styling.
///
/// Use this when you need more control over focus appearance than
/// [FocusRing] provides.
class FocusBuilder extends StatefulWidget {
  /// Builder that receives focus state and builds the child
  final Widget Function(BuildContext context, bool isFocused) builder;

  /// Focus node to track (optional)
  final FocusNode? focusNode;

  /// Whether to only show focus state for keyboard navigation
  final bool keyboardOnly;

  const FocusBuilder({
    super.key,
    required this.builder,
    this.focusNode,
    this.keyboardOnly = true,
  });

  @override
  State<FocusBuilder> createState() => _FocusBuilderState();
}

class _FocusBuilderState extends State<FocusBuilder> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(FocusBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    final hasFocus = _focusNode.hasFocus;

    if (widget.keyboardOnly) {
      final focusHighlightMode = FocusManager.instance.highlightMode;
      final isKeyboardFocus = focusHighlightMode == FocusHighlightMode.traditional;
      setState(() => _isFocused = hasFocus && isKeyboardFocus);
    } else {
      setState(() => _isFocused = hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: widget.builder(context, _isFocused),
    );
  }
}

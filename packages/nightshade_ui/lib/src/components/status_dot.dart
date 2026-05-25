import 'package:flutter/material.dart';

import '../theme/nightshade_tokens.dart';

/// Visual treatment for [StatusDot].
enum StatusDotVariant {
  /// Solid circle, no animation.
  static,

  /// Single 400ms opacity flash when [StatusDot.color] or [variant] changes.
  attention,

  /// Slow opacity pulse reserved for recovery/error urgency.
  urgent,
}

/// Small status indicator — 8px circle by default.
///
/// Replaces ad-hoc pulsing dots across the app with a consistent, quieter
/// motion language: static by default, a one-shot flash on meaningful
/// transitions, and a slow pulse only for urgent error/recovery states.
class StatusDot extends StatefulWidget {
  final Color color;
  final double size;
  final StatusDotVariant variant;

  const StatusDot({
    super.key,
    required this.color,
    this.size = 8.0,
    this.variant = StatusDotVariant.static,
  });

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  static const _attentionDuration = Duration(milliseconds: 400);

  late AnimationController _controller;
  Animation<double> _opacity = const AlwaysStoppedAnimation(1.0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _applyVariant();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final variantChanged = oldWidget.variant != widget.variant;
    final colorChanged = oldWidget.color != widget.color;

    if (variantChanged) {
      _applyVariant();
    }

    if (widget.variant == StatusDotVariant.attention &&
        (variantChanged || colorChanged)) {
      _flashAttention();
    }
  }

  void _applyVariant() {
    _controller.stop();

    switch (widget.variant) {
      case StatusDotVariant.static:
        _controller.duration = NightshadeTokens.durationNormal;
        _opacity = const AlwaysStoppedAnimation(1.0);
        _controller.value = 0.0;
      case StatusDotVariant.attention:
        _controller.duration = _attentionDuration;
        _opacity = TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.0, end: 0.35),
            weight: 50,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 0.35, end: 1.0),
            weight: 50,
          ),
        ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
        _controller.value = 0.0;
      case StatusDotVariant.urgent:
        _controller.duration = NightshadeTokens.durationPulse;
        _opacity = Tween<double>(begin: 0.55, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        );
        _controller.repeat(reverse: true);
    }
  }

  void _flashAttention() {
    _controller
      ..stop()
      ..value = 0.0
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == StatusDotVariant.static) {
      return _dot(opacity: 1.0);
    }

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => _dot(opacity: _opacity.value),
    );
  }

  Widget _dot({required double opacity}) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

enum StatusPillStatus { active, warning, error, inactive, success }

class StatusPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final StatusPillStatus status;
  final VoidCallback? onTap;

  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.status = StatusPillStatus.inactive,
    this.onTap,
  });

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StatusPillStatus? _previousStatus;

  @override
  void initState() {
    super.initState();
    _setupPulseAnimation();
  }

  @override
  void didUpdateWidget(StatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _previousStatus = oldWidget.status;
      _setupPulseAnimation();
    }
  }

  void _setupPulseAnimation() {
    // Determine animation duration based on status
    final Duration pulseDuration;
    final bool shouldPulse;

    switch (widget.status) {
      case StatusPillStatus.active:
        pulseDuration = NightshadeTokens.durationPulse; // 2s
        shouldPulse = true;
      case StatusPillStatus.warning:
        pulseDuration = const Duration(milliseconds: 2500); // Slow pulse
        shouldPulse = true;
      case StatusPillStatus.error:
        pulseDuration = const Duration(milliseconds: 1000); // Sharp pulse
        shouldPulse = true;
      case StatusPillStatus.success:
        // Brief flash on transition, then steady
        pulseDuration = NightshadeTokens.durationSmooth;
        shouldPulse = _previousStatus != StatusPillStatus.success;
      case StatusPillStatus.inactive:
        pulseDuration = NightshadeTokens.durationPulse;
        shouldPulse = false;
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: pulseDuration,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.4,
      end: 0.7,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    if (shouldPulse) {
      if (widget.status == StatusPillStatus.success) {
        // One-shot flash for success transition
        _pulseController.forward().then((_) {
          if (mounted) _pulseController.reverse();
        });
      } else {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getStatusColor(NightshadeColors colors) {
    switch (widget.status) {
      case StatusPillStatus.active:
        return colors.success;
      case StatusPillStatus.success:
        return colors.success;
      case StatusPillStatus.warning:
        return colors.warning;
      case StatusPillStatus.error:
        return colors.error;
      case StatusPillStatus.inactive:
        return colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final statusColor = _getStatusColor(colors);
    final shouldAnimate = widget.status != StatusPillStatus.inactive;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          curve: NightshadeTokens.curveSnappy,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceHover : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: shouldAnimate
                  ? statusColor.withValues(alpha: 0.3)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated status indicator
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: shouldAnimate
                          ? [
                              BoxShadow(
                                color: statusColor.withValues(
                                  alpha: _pulseAnimation.value,
                                ),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              Icon(
                widget.icon,
                size: NightshadeTokens.iconXs,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.label}: ${widget.value}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}






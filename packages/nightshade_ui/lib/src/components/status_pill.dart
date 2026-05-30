import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

enum StatusPillStatus { active, warning, error, inactive, success }

class StatusPill extends StatefulWidget {
  final IconData icon;

  /// Leading label rendered as `'$label: $value'`. Pass an empty string for a
  /// value-only pill (`'$value'` with no prefix) when the surrounding UI
  /// already names what the value refers to.
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
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;
  StatusPillStatus? _previousStatus;

  @override
  void initState() {
    super.initState();
    // The flash controller is created exactly ONCE for the life of the State.
    // SingleTickerProviderStateMixin allows only one ticker, so recreating the
    // controller on every status change (the old behaviour) threw "multiple
    // tickers were created" and left an orphaned controller ticking with a
    // negative elapsed time. We instead reuse the single controller and only
    // re-trigger the flash animation when the status transitions.
    _flashController = AnimationController(
      vsync: this,
      duration: NightshadeTokens.durationSmooth,
    );
    _flashAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeOut),
    );
    _applyFlashForStatus();
  }

  @override
  void didUpdateWidget(StatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _previousStatus = oldWidget.status;
      _applyFlashForStatus();
    }
  }

  /// Drives the (already-created) flash controller for the current status.
  ///
  /// Flashes once when the pill transitions INTO the success state; otherwise
  /// resets the controller to its rest value. Never creates a new controller.
  void _applyFlashForStatus() {
    final shouldFlash = widget.status == StatusPillStatus.success &&
        _previousStatus != StatusPillStatus.success;

    if (shouldFlash) {
      _flashController.forward(from: 0.0).then((_) {
        if (mounted) _flashController.reverse();
      });
    } else {
      _flashController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
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
    final colors = context.nightshadeColors;
    final statusColor = _getStatusColor(colors);
    final isLive = widget.status != StatusPillStatus.inactive;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          curve: NightshadeTokens.curveSnappy,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceHover : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(
              color: isLive
                  ? statusColor.withValues(alpha: 0.28)
                  : colors.border.withValues(alpha: 0.75),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _flashAnimation,
                builder: (context, child) {
                  return Container(
                    width: 6 * _flashAnimation.value,
                    height: 6 * _flashAnimation.value,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
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
                widget.label.isEmpty
                    ? widget.value
                    : '${widget.label}: ${widget.value}',
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

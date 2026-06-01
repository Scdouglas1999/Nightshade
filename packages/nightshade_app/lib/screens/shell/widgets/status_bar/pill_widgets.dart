part of '../status_bar.dart';

class _StatusPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isConnected;
  final NightshadeColors colors;
  final bool compact;

  const _StatusPillButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.isConnected,
    required this.colors,
    this.compact = false,
  });

  @override
  State<_StatusPillButton> createState() => _StatusPillButtonState();
}

class _StatusPillButtonState extends State<_StatusPillButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final statusDot = Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isConnected
            ? widget.colors.success
            : widget.colors.textMuted.withValues(alpha: 0.5),
      ),
    );

    return Tooltip(
      message: '${widget.label}: ${widget.value}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: ConstrainedBox(
          constraints: widget.compact
              ? const BoxConstraints(
                  minWidth: NightshadeTokens.minTouchTarget,
                  minHeight: NightshadeTokens.minTouchTarget,
                )
              : const BoxConstraints(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 8,
              vertical: widget.compact ? 10 : 4,
            ),
            decoration: BoxDecoration(
              color: _isHovered ? widget.colors.surfaceAlt : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: widget.compact
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        size: 14,
                        color: widget.isConnected
                            ? widget.colors.success
                            : widget.colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      statusDot,
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        size: 12,
                        color: widget.isConnected
                            ? widget.colors.success
                            : widget.colors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              ShellChromeMetrics.scaledStatusPillValueMaxWidth(
                            context,
                          ),
                        ),
                        child: Text(
                          widget.value,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      statusDot,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? tooltip;
  final NightshadeColors colors;

  const _InfoChip({
    required this.icon,
    required this.value,
    this.tooltip,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: colors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return child;
    }

    return Tooltip(message: tooltip!, child: child);
  }
}

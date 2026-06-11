part of '../sequence_toolbar.dart';

class _ToolbarIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_ToolbarIconButton> createState() => _ToolbarIconButtonState();
}

class _ToolbarIconButtonState extends State<_ToolbarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: isDisabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _isHovered && !isDisabled
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: isDisabled
                  ? widget.colors.textMuted
                  : _isHovered
                      ? widget.colors.textPrimary
                      : widget.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final NightshadeColors colors;

  const _Divider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: colors.border,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceExecutionState executionState;

  const _StatusBadge({
    required this.colors,
    required this.executionState,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String label;
    IconData icon;

    switch (executionState) {
      case SequenceExecutionState.idle:
        badgeColor = colors.textMuted;
        label = 'Idle';
        icon = LucideIcons.circleOff;
        break;
      case SequenceExecutionState.running:
        badgeColor = colors.success;
        label = 'Running';
        icon = LucideIcons.activity;
        break;
      case SequenceExecutionState.paused:
        badgeColor = colors.warning;
        label = 'Paused';
        icon = LucideIcons.pauseCircle;
        break;
      case SequenceExecutionState.stopping:
        badgeColor = colors.warning;
        label = 'Stopping';
        icon = LucideIcons.loader;
        break;
      case SequenceExecutionState.completed:
        badgeColor = colors.info;
        label = 'Completed';
        icon = LucideIcons.checkCircle;
        break;
      case SequenceExecutionState.failed:
        badgeColor = colors.error;
        label = 'Failed';
        icon = LucideIcons.xCircle;
        break;
      case SequenceExecutionState.recovering:
        // Recovery is a distinct visible state; toolbar reads
        // "Recovering" with the loop-arrow icon so the operator can see
        // at a glance that the sequence is mid-recovery and not just
        // running normally.
        badgeColor = colors.error;
        label = 'Recovering';
        icon = LucideIcons.rotateCw;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: NightshadeDecorations.emphasisSurface(
        badgeColor,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (executionState == SequenceExecutionState.running)
            StatusDot(color: badgeColor)
          else
            Icon(icon, size: 12, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            label,
            style:
                NightshadeTypography.labelStrongSm.copyWith(color: badgeColor),
          ),
        ],
      ),
    );
  }
}

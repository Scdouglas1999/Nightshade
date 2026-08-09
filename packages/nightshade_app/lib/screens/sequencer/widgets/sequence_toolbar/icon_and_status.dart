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

    // The tooltip string is the ONLY name these thirteen glyph-only actions
    // have. Without an explicit Semantics node a screen reader (and the
    // AT-SPI tree) saw an unnamed tappable box, so New Sequence / Undo /
    // Plan Mosaic and the rest were unreachable and undiscoverable.
    // MergeSemantics folds the annotation and the GestureDetector's tap
    // action into ONE node, so the name and the action live together
    // instead of on a parent/child pair; the Tooltip's own node is dropped
    // to keep that single node from being described twice.
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: !isDisabled,
        label: widget.tooltip,
        child: Tooltip(
          message: widget.tooltip,
          excludeFromSemantics: true,
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
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
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
    // Single source of truth for color/label/icon so the toolbar badge stays
    // in lockstep with the mobile playback bar and the recovery LED.
    final visuals =
        SequenceStatusVisuals.of(executionState, colors, context.l10n);
    final badgeColor = visuals.color;
    final label = visuals.label;
    final icon = visuals.icon;

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

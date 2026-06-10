part of '../preflight_validation_dialog.dart';

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final IconData icon;

  const _CountBadge({
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        bordered: false,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom start sequence button with solid fill styling
class _StartSequenceButton extends StatefulWidget {
  final bool canStart;
  final bool hasWarningsOnly;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _StartSequenceButton({
    required this.canStart,
    required this.hasWarningsOnly,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_StartSequenceButton> createState() => _StartSequenceButtonState();
}

class _StartSequenceButtonState extends State<_StartSequenceButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final baseColor = widget.canStart
        ? widget.colors.success
        : widget.hasWarningsOnly
            ? widget.colors.warning
            : widget.colors.textMuted;
    final buttonColors = NightshadeDecorations.filledButtonColors(
      baseColor,
      isHovered: _isHovered,
      isDisabled: !isEnabled,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor:
          isEnabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: buttonColors.background,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(color: buttonColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.canStart ? LucideIcons.play : LucideIcons.alertTriangle,
                size: 16,
                color: onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.hasWarningsOnly ? 'Start Anyway' : 'Start Sequence',
                style:
                    NightshadeTypography.labelStrong.copyWith(color: onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Wave 5 Agent 3 — Pre-flight category section
// =============================================================================
//
// Compact collapsible-style group for the new pre-flight categories.
// Renders an icon + title + (optional) trailing action button (e.g.
// "Capture missing darks") and the issue cards beneath.

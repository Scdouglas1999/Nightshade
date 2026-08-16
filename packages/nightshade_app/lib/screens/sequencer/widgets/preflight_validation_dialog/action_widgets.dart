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

  /// Why the run cannot start, or null when it can. Travels into the
  /// accessible NAME via [GatedAction.announce] so a blocked primary cannot
  /// read like a live one.
  final String? blockedReason;

  const _StartSequenceButton({
    required this.canStart,
    required this.hasWarningsOnly,
    required this.colors,
    this.blockedReason,
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

    final label = widget.hasWarningsOnly ? 'Start Anyway' : 'Start Sequence';

    // This is the green primary of the whole pre-flight dialog. A bare
    // GestureDetector publishes no role and no state — a `panel:` beside its
    // own `button: Re-check` and `button: Cancel` siblings — and cannot be
    // reached from the keyboard. Declaring the role + enabled state and routing
    // Enter/Space through an ActivateIntent puts it on the same footing as
    // every NightshadeButton.
    //
    // The refusal REASON travels in the NAME: without it an AT-SPI probe of
    // the blocked dialog reads `Start Sequence` with `sensitive` and no
    // `enabled`, indistinguishable from the live button beside it. That is the
    // discriminator `GatedAction` provides everywhere else.
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: GatedAction.announce(label, widget.blockedReason),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor:
            isEnabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: FocusableActionDetector(
          enabled: isEnabled,
          actions: <Type, Action<Intent>>{
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
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: buttonColors.background,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(color: buttonColors.border),
              ),
              // The visible label is excluded so it cannot be appended to the
              // annotated name: without this the node announced itself twice
              // ("Start Anyway\nStart Anyway"), and with a blocked reason it
              // would have read the reason and then contradicted it with the
              // bare label.
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.canStart
                          ? LucideIcons.play
                          : LucideIcons.alertTriangle,
                      size: 16,
                      color: onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: NightshadeTypography.labelStrong
                          .copyWith(color: onPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Pre-flight category section
//
// Compact collapsible-style group for the new pre-flight categories.
// Renders an icon + title + (optional) trailing action button (e.g.
// "Capture missing darks") and the issue cards beneath.

part of '../status_bar.dart';

class _StatusPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isConnected;
  final NightshadeColors colors;
  final bool compact;

  /// Narrow-desktop density: keeps the desktop pill's height, but shows only
  /// ONE of the two words — whichever one is not the same on every pill.
  ///
  /// Dropping the label unconditionally was worse than the crowding it fixed:
  /// with nothing connected, the value of the Camera, Mount and Guider pills is
  /// the identical word "Disconnected", so a 900 px window read
  /// "Disconnected  Disconnected  Disconnected" and the only thing telling the
  /// three apart was a 12 px monochrome glyph. Disconnected is already carried
  /// by the dot and by the muted icon, so the device NAME is what earns the
  /// space; once a device is connected its value (profile name, focuser
  /// position, Guiding/Ready) is the part that changes and it wins instead.
  ///
  /// This is not [compact]: that variant is sized for touch (44 px minimum) and
  /// would overflow the 36 px desktop status bar, and it hides all text.
  final bool dense;

  const _StatusPillButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.isConnected,
    required this.colors,
    this.compact = false,
    this.dense = false,
  });

  @override
  State<_StatusPillButton> createState() => _StatusPillButtonState();
}

class _StatusPillButtonState extends State<_StatusPillButton> {
  bool _isHovered = false;

  /// Widest a dense pill's value may be (WE-EQ-N5).
  ///
  /// Chosen so four device pills plus the sequence indicator, the equipment
  /// indicator and the save-path chip fit a 1000 px bar without the strip
  /// overflowing into the fade. Long names still say they are truncated — with
  /// an ellipsis, inside the pill, above their own state dot.
  static const double _denseValueMaxWidth = 88.0;

  /// The one word a dense pill can afford: the device name while nothing is
  /// connected (every pill's value is "Disconnected" then), the live value
  /// once it is.
  String get _denseText =>
      widget.dense && !widget.isConnected ? widget.label : widget.value;

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
              borderRadius: NightshadeTokens.borderRadiusMd,
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
                      // Both words only when there is room for both; the
                      // tooltip still spells out "Mount: Disconnected" either
                      // way.
                      if (!widget.dense) ...[
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize11,
                            color: widget.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          // WE-EQ-N5: at 1000 px the pill strip overflows and
                          // the scroll viewport's fade cut a pill THROUGH its
                          // value — "Simulate" dissolving into the next pill's
                          // icon, with no ellipsis and the state dot lost off
                          // the edge. An ellipsis inside the pill is a truncation
                          // the reader can see; a viewport slice is not. The
                          // dense cap is tight enough that the whole strip fits
                          // at that width, so the cut stops happening at all.
                          maxWidth: widget.dense
                              ? _denseValueMaxWidth
                              : ShellChromeMetrics
                                  .scaledStatusPillValueMaxWidth(context),
                        ),
                        child: Text(
                          _denseText,
                          overflow: TextOverflow.ellipsis,
                          style: NightshadeTypography.labelStrongSm.copyWith(
                            color: widget.dense && !widget.isConnected
                                ? widget.colors.textSecondary
                                : widget.colors.textPrimary,
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
            fontSize: NightshadeTypography.fontSize11,
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

/// The "there is more equipment this way" control at the right edge of the
/// scrolling pill group.
///
/// WD-COL-N4: at 900 px the group scrolled silently. The last visible pill was
/// cut mid-word against the temperature chip and Mount / Guider / Focus simply
/// were not there, with nothing on screen saying they existed — a disconnected
/// mount and no mount at all looked identical. The 24 px alpha fade was the
/// only hint, and a fade is not a control: with a mouse there was nothing to
/// click. This is.
class _PillsOverflowAffordance extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _PillsOverflowAffordance({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: 'More equipment status',
      child: Tooltip(
        message: 'More equipment status — scroll',
        child: InkWell(
          onTap: onTap,
          borderRadius: NightshadeTokens.borderRadiusMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Icon(
              NightshadeIcons.chevronRight,
              size: NightshadeTokens.iconXs,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

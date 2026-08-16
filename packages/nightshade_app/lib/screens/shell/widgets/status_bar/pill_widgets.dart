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
  /// Whichever word differs is the one that earns the space. With nothing
  /// connected the Camera, Mount and Guider pills all read "Disconnected", so
  /// the device NAME wins — the disconnected state is already carried by the
  /// dot and the muted icon. Once a device is connected its value (profile
  /// name, focuser position, Guiding/Ready) is the part that changes, so that
  /// wins instead.
  ///
  /// This is not [compact]: that variant is sized for touch (44 px minimum),
  /// would overflow the 36 px desktop status bar, and hides all text.
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

  /// Widest a dense pill's value may be.
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
                          // Uncapped at 1000 px the pill strip overflows and
                          // the scroll viewport's fade cuts a pill THROUGH its
                          // value — "Simulate" dissolving into the next pill's
                          // icon, with no ellipsis and the state dot lost off
                          // the edge. An ellipsis inside the pill is a
                          // truncation the reader can see; a viewport slice is
                          // not. The dense cap is tight enough that the whole
                          // strip fits at that width.
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
/// Without it the group scrolls silently: at 900 px the last visible pill is
/// cut mid-word against the temperature chip and Mount / Guider / Focus are
/// simply absent, with nothing on screen saying they exist — a disconnected
/// mount and no mount at all look identical. The 24 px alpha fade is the only
/// hint, and a fade is not a control: with a mouse there is nothing to click.
/// This is.
/// The truncation mark drawn where the pill strip is cut by its viewport.
///
/// Capping a dense pill's value is not enough on its own: at 1000x800 with four
/// devices connected the strip still scrolls, with the pill at the cut reading
/// "Si", sliced mid-word and dissolved by the edge fade. A viewport slice is
/// not a truncation the reader can recognise; an ellipsis is, and it is what
/// every other truncation in this app uses.
///
/// It lives OUTSIDE the scroll viewport, flush against its right edge: inside,
/// it would scroll away with the very text it describes. Decorative for
/// assistive tech — the scroll affordance beside it carries the meaning as a
/// real, named control.
class _PillsCutMarker extends StatelessWidget {
  final NightshadeColors colors;

  const _PillsCutMarker({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Text(
        '…',
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize11,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

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

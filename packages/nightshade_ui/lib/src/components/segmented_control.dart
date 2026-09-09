import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// A second-level switch INSIDE a panel — Sequencer's Nodes / Snippets / Queue.
///
/// Never in a page header: that is [AdaptiveTabBar]'s job and the app has one
/// tab style. A segmented control has no outer container and no border either;
/// the selected segment is a `surfaceHover` fill and the rest are muted labels,
/// which is as much weight as a switch inside a panel is allowed.
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// The segment labels, in display order.
  final List<String> segments;

  /// Index of the selected segment.
  final int selectedIndex;

  /// Called with the tapped segment's index.
  final ValueChanged<int> onSelected;

  /// A segment's height in logical pixels.
  static const double segmentHeight = 30;

  /// A segment's horizontal padding.
  static const double segmentPadding = 10;

  /// Gap between segments.
  static const double gap = 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < segments.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: gap),
          _Segment(
            label: segments[i],
            selected: i == selectedIndex,
            colors: colors,
            onTap: () => onSelected(i),
          ),
        ],
      ],
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (!mounted || _hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final foreground = widget.selected
        ? colors.textPrimary
        : (_hovered ? colors.textSecondary : colors.textMuted);

    return Semantics(
      button: true,
      // Semantics publishes isEnabled only when the field is given; a segment
      // without it announces as dimmed while being perfectly operable.
      enabled: true,
      selected: widget.selected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: ExcludeSemantics(
            child: AnimatedContainer(
              duration: NightshadeTokens.durationFast,
              curve: NightshadeTokens.curveStandard,
              height: SegmentedControl.segmentHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: SegmentedControl.segmentPadding,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.selected || _hovered
                    ? colors.surfaceHover
                    : Colors.transparent,
                borderRadius: NightshadeTokens.borderRadiusSm,
              ),
              child: Text(
                widget.label,
                style: NightshadeTypography.buttonSm.copyWith(
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

part of '../sequence_tree.dart';

// Sticky ancestors (spec §5).
//
// Thirty rows into a night the operator can no longer tell which target and
// which loop the rows on screen belong to. The ancestors of the topmost
// visible row pin to the top of the viewport once their own row has scrolled
// out of it, so the answer is always on screen.
//
// The stack is an OVERLAY on the scroll view, not a row in it: it must not
// change the tree's layout, must not duplicate a row in the accessibility
// traversal order, and must not swallow the scroll gesture of a pointer that
// happens to be over it.

/// Identifies the pinned stack for tests and for tooling that has to tell a
/// pinned row from the real one (they carry the same name).
const Key sequenceStickyAncestorsKey = Key('sequence-tree-sticky-ancestors');

/// At most three ancestors pin. Deeper than that and the stack eats the
/// viewport it exists to explain.
const int _maxPinnedAncestors = 3;

/// How far a newly pinned row travels as it fades in (spec §9).
const double _pinSlideDistance = 6.0;

/// The hairline the stack draws along its bottom edge to separate itself from
/// the rows scrolling under it. Named because the reserved height has to
/// include it exactly.
const double _stickyStackBorderWidth = 1.0;

/// Clearance a row gets below the stack when the operator clicks a pin to
/// reach it — flush with the pin above would read as a fourth pinned row.
const double _pinLandingMargin = NightshadeTokens.spaceXs;

/// Height a stack of [count] pinned rows occupies, and therefore the height
/// the scroll content reserves at its top so the stack covers nothing.
///
/// Computed, not measured: every pinned row is exactly one [_ledgerRowHeight]
/// in both densities the stack draws (the ledger row is fixed-height by
/// definition, and [_PinnedCompactRow] is built to match it), so the figure is
/// exact and — unlike a render-box measurement — available on the same frame
/// the pin appears.
double pinnedStackHeight(int count) =>
    count == 0 ? 0 : count * _ledgerRowHeight + _stickyStackBorderWidth;

/// The ancestors of [anchorId] that are currently pinned, outermost first.
///
/// [isRowAbove] answers "has this row's own box scrolled clear of the viewport
/// top?" — the caller owns it because only it can measure the live render
/// boxes. An ancestor whose row is still on screen is NOT pinned; pinning it
/// would draw the same row twice.
///
/// The returned depth is the row's depth in the tree (the root container is
/// not drawn, so its children are depth 1), which is what a ledger row needs
/// to draw its guide columns.
List<VisibleNode> pinnedAncestorsOf(
  Sequence sequence,
  String anchorId,
  bool Function(String nodeId) isRowAbove,
) {
  final chain = sequenceAncestorIds(sequence, anchorId);
  final pinned = <VisibleNode>[
    for (var i = 0; i < chain.length; i++)
      if (isRowAbove(chain[i])) (id: chain[i], depth: i + 1),
  ];
  if (pinned.length <= _maxPinnedAncestors) return pinned;
  // Keep the NEAREST ancestors: "which loop am I in" is a more pressing
  // question than "which of the two targets", and the nearest ones are the
  // rows that just left the screen.
  return pinned.sublist(pinned.length - _maxPinnedAncestors);
}

/// The pinned ancestor rows, stacked in depth order over the tree's viewport.
class _StickyAncestorStack extends StatelessWidget {
  final NightshadeColors colors;
  final Sequence sequence;
  final SequenceProgress progress;
  final List<VisibleNode> pinned;
  final SequencerDensity density;

  /// The scroll view's own horizontal padding, so a pinned row sits exactly
  /// over the column of the row it stands for.
  final EdgeInsets padding;

  final void Function(String nodeId) onTap;

  const _StickyAncestorStack({
    super.key,
    required this.colors,
    required this.sequence,
    required this.progress,
    required this.pinned,
    required this.density,
    required this.padding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final entry in pinned)
        if (sequence.nodes[entry.id] case final node?)
          _PinEntrance(
            key: ValueKey<String>(entry.id),
            child: GestureDetector(
              // Translucent, not opaque: the stack floats over the scroll
              // view, and an opaque hit box would kill the wheel and the drag
              // scroll of a pointer that happens to be in the top 84 px.
              behavior: HitTestBehavior.translucent,
              // The pin is a shortcut to a row that is already in the
              // traversal order, and its own contents are excluded from
              // semantics. Left to announce itself the detector would add an
              // anonymous tappable node per pin — three unlabelled "buttons"
              // ahead of the whole tree.
              excludeFromSemantics: true,
              onTap: () => onTap(entry.id),
              // The row itself takes no pointer: the chevron, the kebab and
              // the drag handle belong to the real row, and a drag started
              // here must reach the scroll view under it.
              child: IgnorePointer(
                child: density == SequencerDensity.ledger
                    ? _LedgerRow(
                        colors: colors,
                        sequence: sequence,
                        node: node,
                        depth: entry.depth,
                        isSelected: false,
                        isContainer: isSequenceContainer(node),
                        isCollapsed: false,
                        nodeStatus: progress.nodeStatuses[node.id],
                        progressPercent: progress.nodeProgressPercent[node.id],
                        pinned: true,
                      )
                    : _PinnedCompactRow(
                        colors: colors,
                        node: node,
                        depth: entry.depth,
                      ),
              ),
            ),
          ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(left: padding.left, right: padding.right),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          border: Border(
            bottom: BorderSide(
              color: colors.border,
              width: _stickyStackBorderWidth,
            ),
          ),
          // The design system casts a shadow on exactly two things, and both
          // are surfaces genuinely floating above the page. The pinned stack
          // is the third: without the lift it reads as a row that refuses to
          // scroll.
          boxShadow: NightshadeDecorations.popover(colors).boxShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// Slides a newly pinned row down into the stack as it fades in (spec §9).
class _PinEntrance extends StatelessWidget {
  final Widget child;

  const _PinEntrance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: _ledgerMotion(context, NightshadeTokens.durationQuick),
      curve: NightshadeTokens.curveStandard,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -_pinSlideDistance * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The pinned form of a Compact row.
///
/// Compact keeps today's cards, which are far too tall to stack three deep
/// over the viewport, so a pinned ancestor there is a single line: the same
/// height, glyph and name treatment a ledger row gives it, minus the readout
/// columns Compact does not draw anywhere.
class _PinnedCompactRow extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;
  final int depth;

  const _PinnedCompactRow({
    required this.colors,
    required this.node,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    // A target card titles itself with its target, not with the node's own
    // name; the pin must name the row it stands for.
    final label = node is TargetHeaderNode ? node.displayName : node.name;
    return ExcludeSemantics(
      child: SizedBox(
        height: _ledgerRowHeight,
        child: Row(
          children: [
            SizedBox(width: (depth - 1) * _ledgerGuideWidth),
            Icon(
              sequenceNodeIcon(node.iconName),
              size: _ledgerIconSize,
              color: nodeCategoryTint(node.category, colors),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                label,
                style: NightshadeTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

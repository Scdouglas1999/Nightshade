part of '../sequence_tree.dart';

// The Ledger-mode row: one fixed-height line per step, with four aligned
// readout columns on the right (spec §2).
//
// It carries EVERYTHING the comfortable row does — selection with modifiers,
// the context menu, the row focus node the screen shortcuts act through, drag
// reorder, the drop zones around it, the collapsed-container drop target, the
// tutorial anchors and the validation badge. The mode changes how a step is
// drawn, never what can be done to it.

/// Fixed row height. The whole point of the mode: 40 steps in ~1120 px instead
/// of the ~3500 px the comfortable cards take.
const double _ledgerRowHeight = 28.0;

/// The column header's height.
const double _ledgerHeaderHeight = 26.0;

/// One depth level's guide column, and the hairline it draws down its left.
const double _ledgerGuideWidth = 18.0;
const double _ledgerGuideLineWidth = 1.0;

/// The primary marker down the left edge of the running row. Reserved on every
/// row (as blank space when the row is not running) so switching rows cannot
/// shift the name by two pixels.
const double _ledgerRunningMarkerWidth = 2.0;

/// The chevron's hit box and glyph. The box is the full row height so a 12 px
/// glyph is still a comfortable pointer target (18 × 28), matching the 24 × 24
/// of the comfortable row's action chips.
const double _ledgerChevronWidth = 18.0;
const double _ledgerChevronGlyph = 12.0;

/// The node's own glyph, in its category tint.
const double _ledgerIconSize = 13.0;

/// The progress bar along the row's bottom edge.
const double _ledgerProgressHeight = 2.0;

/// The kebab's footprint on a pointer platform.
const double _ledgerKebabWidth = 24.0;

/// One hover chip's footprint: `_NodeActionButton`'s 24 px box plus its 4 px
/// leading margin.
const double _ledgerActionChipWidth = 28.0;

/// Width permanently reserved for the actions block on a pointer platform —
/// the eye/duplicate/delete trio plus the kebab. Reserved rather than inserted
/// on hover: appearing actions that push the columns sideways make a ledger
/// unreadable exactly when the pointer is in it. On touch the trio folds into
/// the kebab and the reservation becomes the touch-target floor.
const double _ledgerActionsWidth =
    3 * _ledgerActionChipWidth + _ledgerKebabWidth;

/// Trailing gutter. `_NodeValidationWrapper` positions its 18 px badge at the
/// row's top-right, so without this the badge would sit on top of the ETA
/// digits of every invalid row.
const double _ledgerBadgeGutter = 22.0;

/// Width of the row a drag carries in the feedback layer.
///
/// The columns (266), the badge gutter (22), the reserved actions (108) and
/// the running marker (2) account for 398 of it, which leaves the name ~146 px
/// — what it has in a canvas of ordinary width. A narrower feedback row would
/// ellipsise a name that is perfectly readable in the tree it came from.
const double _ledgerDragFeedbackWidth = 544.0;

/// The four column widths, in order (spec §2).
const List<double> _ledgerColumnWidths = <double>[70.0, 60.0, 74.0, 62.0];

/// The four column headings, in the same order.
const List<String> _ledgerColumnLabels = <String>[
  'Filter / exp',
  'Count',
  'Duration',
  'ETA',
];

/// The narrowest canvas that can hold the four columns AND a usable name.
///
/// Marker (2) + chevron (18) + icon (13) + the icon gap (8) + the reserved
/// actions (108) + the columns (266) + the badge gutter (22) already cost
/// 437 px at depth 1 and grow 18 px a level, so this leaves the name ~63 px
/// there and proportionally less deeper in. `SequenceTree` reads it once —
/// below it the whole tree falls back to compact rows rather than shipping a
/// ledger with its columns stripped, so a ledger row itself never has to
/// decide whether it can afford them.
const double _ledgerColumnsMinWidth = 500.0;

/// Zero when the platform asks for no animation, so every ledger animation is
/// gated in one place.
Duration _ledgerMotion(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// The width every ledger row — and the header above it — reserves for its
/// actions block: the trio + kebab on a pointer platform, the touch-target
/// floor on touch (where the trio folds into the kebab).
double _ledgerActionsSlotWidth(BuildContext context) =>
    NightshadeTouchTarget.isTouch(context)
        ? NightshadeTouchTarget.minExtent(context)
        : _ledgerActionsWidth;

/// The column header, rendered once above the tree in Ledger mode.
///
/// Lives INSIDE the tree's scroll view so it takes the same horizontal padding
/// the rows do and its labels sit over the columns they name. It only exists
/// at or above [_ledgerColumnsMinWidth] — the tree falls back to compact rows
/// below it, header and all.
class _LedgerColumnHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _LedgerColumnHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    final style =
        NightshadeTypography.eyebrow.copyWith(color: colors.textMuted);
    return ExcludeSemantics(
      child: SizedBox(
        height: _ledgerHeaderHeight,
        child: Row(
          children: [
            const SizedBox(width: _ledgerRunningMarkerWidth),
            Expanded(
              child: Text(
                'Step',
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: _ledgerActionsSlotWidth(context)),
            for (var i = 0; i < _ledgerColumnLabels.length; i++)
              SizedBox(
                width: _ledgerColumnWidths[i],
                child: Text(
                  _ledgerColumnLabels[i],
                  style: style,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(width: _ledgerBadgeGutter),
          ],
        ),
      ),
    );
  }
}

class _LedgerRow extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence sequence;
  final SequenceNode node;

  /// Render depth. Depth 1 is a top-level step (the root container is not
  /// drawn), so a row draws `depth - 1` guide columns.
  final int depth;

  /// True when this row is the primary selection OR part of the multi-select
  /// set — the two paint identically, as they do in every density.
  final bool isSelected;

  /// Whether the node can hold children, and so gets a chevron.
  final bool isContainer;
  final bool isCollapsed;

  final NodeStatus? nodeStatus;
  final double? progressPercent;

  /// True in a drag's feedback layer: no hover, no actions, no selection.
  final bool isDragging;

  /// True in the sticky-ancestor stack (spec §5). A pinned row is a READOUT of
  /// a row that has scrolled away, so it drops everything that makes the real
  /// row a target: the focus node the shortcuts act through, the tap/hover
  /// gestures, the hover actions, and its place in the accessibility traversal
  /// order — the real row is still there and still reachable. It draws on
  /// `surfaceElevated` because the stack it sits in floats over the tree.
  final bool pinned;

  final VoidCallback? onSelect;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _LedgerRow({
    required this.colors,
    required this.sequence,
    required this.node,
    required this.depth,
    required this.isSelected,
    required this.isContainer,
    required this.isCollapsed,
    required this.nodeStatus,
    this.progressPercent,
    this.isDragging = false,
    this.pinned = false,
    this.onSelect,
    this.onToggleEnabled,
    this.onDelete,
    this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  ConsumerState<_LedgerRow> createState() => _LedgerRowState();
}

class _LedgerRowState extends ConsumerState<_LedgerRow> {
  // Hover lives in a ValueNotifier, not setState, so moving the pointer down a
  // 40-row ledger repaints two islands per row (the background and the kebab)
  // instead of rebuilding every row's content.
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  // Selecting a row takes keyboard focus, so the screen's Delete / Ctrl+D /
  // Ctrl+Z bindings start applying to it. Rows are click targets, not tab
  // stops (`skipTraversal`). Same contract — and the same debug label — as
  // the comfortable row: focus tests and any tooling that identifies "the
  // tree row has keyboard focus" must not have to know which density drew it.
  final FocusNode _rowFocusNode = FocusNode(debugLabel: 'sequence-tree-row');

  @override
  void dispose() {
    _isHovered.dispose();
    _rowFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final node = widget.node;

    // Columns and the collapsed summary come from the sequence-keyed maps
    // rather than being computed here: `ledgerColumnsFor` walks the node's
    // subtree via `plannedCaptureUnder`, and a row rebuilds on every progress
    // tick, so per-row computation pays O(N·depth) per tick for values that
    // only move when the sequence does.
    final base = ref.watch(
            ledgerColumnsMapProvider.select((columns) => columns[node.id])) ??
        LedgerColumns.empty;
    final eta =
        ref.watch(ledgerEtaProvider.select((starts) => starts[node.id]));
    final columns = LedgerColumns(
      filterExp: base.filterExp,
      count: base.count,
      duration: base.duration,
      eta: eta == null ? '' : formatLedgerClock(eta.start),
    );
    // A projected ETA for a node the run has already passed is stale — once
    // the run's NodeStarted events arrive they replace the projection, but
    // before they do the column shows the prediction muted rather than as
    // fact.
    final status = widget.nodeStatus;
    final etaMuted = eta != null &&
        !eta.isActual &&
        status != null &&
        status != NodeStatus.pending;
    // A collapsed container has to say what it is standing in for; an expanded
    // one has its children on screen and needs no summary.
    final summary = widget.isCollapsed && widget.isContainer
        ? ref.watch(rollupSummaryMapProvider
                .select((summaries) => summaries[node.id])) ??
            ''
        : '';

    final isRunning = status == NodeStatus.running;
    final isSuccess = status == NodeStatus.success;
    final isFailed = status == NodeStatus.failure;
    final isSkipped = status == NodeStatus.skipped;
    final isCancelled = status == NodeStatus.cancelled;
    final isDisabled = !node.isEnabled;
    final isStruckThrough = isDisabled || isSkipped || isCancelled;
    // Done, skipped and cancelled all recede; a FAILURE does not — it is the
    // one outcome the operator has to find, so it keeps the error colour the
    // comfortable row gives it.
    final isMuted = isSuccess || isSkipped || isCancelled || isDisabled;

    final content = _buildContent(
      context: context,
      columns: columns,
      summary: summary,
      etaMuted: etaMuted,
      isRunning: isRunning,
      isFailed: isFailed,
      isMuted: isMuted,
      isStruckThrough: isStruckThrough,
    );

    final progressBar = _buildProgressBar(
      isRunning: isRunning,
      isSuccess: isSuccess,
      isFailed: isFailed,
    );

    final row = SizedBox(
      height: _ledgerRowHeight,
      child: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _isHovered,
            // The content is built ONCE and handed over via `child`, so a
            // hover only recomputes the fill.
            child: content,
            builder: (context, hovered, child) => AnimatedContainer(
              duration: _ledgerMotion(context, NightshadeTokens.durationFast),
              curve: NightshadeTokens.curveStandard,
              decoration: BoxDecoration(
                color: _fill(isRunning: isRunning, hovered: hovered),
              ),
              // A foreground border, not a real one: a border in the
              // decoration insets the child by its width, so selecting a row
              // would nudge its name and every column by a pixel.
              foregroundDecoration: widget.isSelected
                  ? BoxDecoration(
                      border: Border.all(
                        color: colors.primary.withValues(
                          alpha: NightshadeTokens.opacitySelectedRing,
                        ),
                      ),
                    )
                  : null,
              child: child,
            ),
          ),
          if (progressBar != null)
            Positioned(left: 0, right: 0, bottom: 0, child: progressBar),
        ],
      ),
    );

    // A pinned row keeps the row's LOOK and nothing else: no focus node, no
    // gestures, and out of the traversal order so a screen reader hears each
    // step once (spec §5).
    if (widget.pinned) return ExcludeSemantics(child: row);

    final semanticsRow = Semantics(
      button: true,
      selected: widget.isSelected,
      enabled: node.isEnabled,
      // Containers announce their state so a screen-reader user knows whether
      // the rows below belong to this one.
      expanded: widget.isContainer ? !widget.isCollapsed : null,
      label:
          _semanticsLabel(columns: columns, summary: summary, status: status),
      hint: 'Select node. More actions include reorder and wrap commands.',
      child: Focus(
        focusNode: _rowFocusNode,
        skipTraversal: true,
        child: GestureDetector(
          onTap: () {
            // Take focus FIRST: the click that selects a node is also the
            // moment the keyboard shortcuts must start applying to it.
            _rowFocusNode.requestFocus();
            widget.onSelect?.call();
          },
          child: row,
        ),
      ),
    );

    if (widget.isDragging) return semanticsRow;
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      child: semanticsRow,
    );
  }

  /// The row's fill. Running wins over selection, which wins over hover: the
  /// run's position is the most urgent fact on the canvas, and a selected row
  /// still carries its ring on top of whichever fill it gets.
  Color? _fill({required bool isRunning, required bool hovered}) {
    final colors = widget.colors;
    // The pinned stack is one elevated surface; a running ancestor still says
    // so through its left marker and its Running chip, which are content.
    if (widget.pinned) return colors.surfaceElevated;
    if (isRunning) {
      return colors.primary.withValues(
        alpha: NightshadeTokens.opacityAccentTint,
      );
    }
    if (widget.isSelected) return colors.surfaceElevated;
    if (hovered) return colors.surfaceHover;
    return null;
  }

  Widget _buildContent({
    required BuildContext context,
    required LedgerColumns columns,
    required String summary,
    required bool etaMuted,
    required bool isRunning,
    required bool isFailed,
    required bool isMuted,
    required bool isStruckThrough,
  }) {
    final colors = widget.colors;
    final node = widget.node;
    final guides = widget.depth - 1;

    final nameColor = isFailed
        ? colors.error
        : isMuted
            ? colors.textMuted
            : colors.textPrimary;
    final columnColor = isMuted ? colors.textMuted : colors.textSecondary;

    return Row(
      children: [
        SizedBox(
          width: _ledgerRunningMarkerWidth,
          height: _ledgerRowHeight,
          child: isRunning ? ColoredBox(color: colors.primary) : null,
        ),
        ..._ledgerDepthGuides(guides, colors),
        _buildChevron(context),
        ExcludeSemantics(
          child: Icon(
            sequenceNodeIcon(node.iconName),
            size: _ledgerIconSize,
            color: isMuted
                ? colors.textMuted
                : nodeCategoryTint(node.category, colors),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: ExcludeSemantics(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    node.name,
                    style: NightshadeTypography.bodySm.copyWith(
                      fontWeight: widget.isContainer
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: nameColor,
                      decoration:
                          isStruckThrough ? TextDecoration.lineThrough : null,
                      decorationColor: isStruckThrough ? nameColor : null,
                    ),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isRunning) ...[
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Flexible(
                    child: _LedgerChip(
                      colors: colors,
                      label: 'Running',
                      tone: colors.primary,
                    ),
                  ),
                ],
                // A target's pointing is what distinguishes it from every
                // other target, and Ledger has no card to put it on.
                //
                // Flexible, because the chips are fixed-width and the name is
                // not: at the canvas's narrow floor the name shrinks to nothing
                // and the two coordinates then run past the row's edge. They
                // give ground the same way the name does instead.
                if (node is TargetHeaderNode)
                  for (final chip in _targetCoordinateChips(node, colors)) ...[
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    Flexible(child: chip),
                  ],
                if (node.category == NodeCategory.trigger) ...[
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  _WatchdogBadge(colors: colors),
                ],
                if (summary.isNotEmpty) ...[
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Flexible(
                    child: Text(
                      summary,
                      style: NightshadeTypography.labelQuiet.copyWith(
                        color: colors.textMuted,
                      ),
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _buildActions(context),
        _LedgerColumnCells(
          values: columns.values,
          color: columnColor,
          // The ETA cell mutes when it is still quoting the prediction for a
          // node the run already passed.
          etaColor: etaMuted ? colors.textMuted : null,
        ),
        const SizedBox(width: _ledgerBadgeGutter),
      ],
    );
  }

  Widget _buildChevron(BuildContext context) {
    if (!widget.isContainer) {
      return const SizedBox(width: _ledgerChevronWidth);
    }
    return _LedgerChevron(
      colors: widget.colors,
      isCollapsed: widget.isCollapsed,
      onToggle: () =>
          ref.read(collapsedNodeIdsProvider.notifier).toggle(widget.node.id),
    );
  }

  /// The hover-revealed actions block, in permanently reserved width.
  ///
  /// On a pointer platform it is the eye / duplicate / delete trio plus the
  /// kebab — the same three mutations the comfortable row shows on hover.
  /// A touch pointer has no hover, so there the block is simply the always-on
  /// kebab (the trio's entries live inside it), padded out to the platform's
  /// minimum tap target — a 24 × 28 hit box is not a legal touch target.
  Widget _buildActions(BuildContext context) {
    final isTouch = NightshadeTouchTarget.isTouch(context);
    final slotWidth = _ledgerActionsSlotWidth(context);
    if (widget.isDragging || widget.pinned) {
      return SizedBox(width: slotWidth);
    }
    final menu = _NodeOverflowMenu(
      colors: widget.colors,
      node: widget.node,
      onToggleEnabled: widget.onToggleEnabled,
      onDuplicate: widget.onDuplicate,
      onDelete: widget.onDelete,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
    );
    final actions = isTouch
        // OverflowBox lets the kebab's 48×48 hit area spill the row's 28 px
        // height symmetrically instead of clipping the slot down to the
        // visual. This is the padding `NightshadeTouchTarget` prescribes,
        // applied where a fixed-height row cannot grow to fit it.
        ? OverflowBox(
            minWidth: slotWidth,
            maxWidth: slotWidth,
            minHeight: slotWidth,
            maxHeight: slotWidth,
            child: menu,
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _NodeActionChips(
                colors: widget.colors,
                node: widget.node,
                onToggleEnabled: widget.onToggleEnabled,
                onDuplicate: widget.onDuplicate,
                onDelete: widget.onDelete,
              ),
              // PopupMenuButton's IconButton enforces a 48 px interactive
              // minimum of its own; the tight slot clamps it back to the
              // dense footprint the reservation was sized for.
              SizedBox(
                width: _ledgerKebabWidth,
                height: _ledgerRowHeight,
                child: menu,
              ),
            ],
          );
    return SizedBox(
      width: slotWidth,
      height: _ledgerRowHeight,
      child: ValueListenableBuilder<bool>(
        valueListenable: _isHovered,
        child: actions,
        builder: (context, hovered, child) {
          final visible = isTouch || hovered;
          return IgnorePointer(
            ignoring: !visible,
            // A hidden button must not be announced or focusable, or a
            // screen-reader user lands on a control they cannot operate.
            child: ExcludeSemantics(
              excluding: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: _ledgerMotion(
                  context,
                  NightshadeTokens.durationFast,
                ),
                curve: NightshadeTokens.curveStandard,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  /// The 2 px bar along the bottom edge: primary while running, success when
  /// complete, error when failed, and nothing at all before the node has run.
  ///
  /// The failure case is not in the spec's list, but Ledger rows have no status
  /// stripe of their own, so leaving a failed row unmarked would lose the one
  /// outcome the operator most needs to spot.
  Widget? _buildProgressBar({
    required bool isRunning,
    required bool isSuccess,
    required bool isFailed,
  }) {
    final colors = widget.colors;
    final Color fill;
    final double fraction;
    if (isRunning) {
      fill = colors.primary;
      fraction = ((widget.progressPercent ?? 0) / 100.0).clamp(0.0, 1.0);
    } else if (isSuccess) {
      fill = colors.success;
      fraction = 1.0;
    } else if (isFailed) {
      fill = colors.error;
      fraction = 1.0;
    } else {
      return null;
    }

    return SizedBox(
      height: _ledgerProgressHeight,
      child: Stack(
        children: [
          // The track only exists while a run is in flight; a finished row is
          // a solid line, not a line inside a groove. It must be POSITIONED —
          // a bare ColoredBox in a loose Stack lays out at 0×0 and the groove
          // never paints.
          if (isRunning)
            Positioned.fill(child: ColoredBox(color: colors.surfaceHover)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 1,
              child: ColoredBox(color: fill),
            ),
          ),
        ],
      ),
    );
  }

  /// The row's announced phrase: its name, then the four column values it
  /// shows, then its collapsed summary and its run state. The columns are the
  /// row's content, so a reader that cannot see them has to hear them.
  String _semanticsLabel({
    required LedgerColumns columns,
    required String summary,
    required NodeStatus? status,
  }) {
    final stateWord = switch (status) {
      NodeStatus.running => 'running',
      NodeStatus.success => 'done',
      NodeStatus.failure => 'failed',
      NodeStatus.skipped => 'skipped',
      NodeStatus.cancelled => 'cancelled',
      _ => widget.node.isEnabled ? '' : 'disabled',
    };
    return <String>[
      widget.node.name,
      if (summary.isNotEmpty) summary,
      ...columns.values.where((value) => value.isNotEmpty),
      if (stateWord.isNotEmpty) stateWord,
    ].join(' · ');
  }
}

/// The RA / Dec chips a target header row carries in place of the coordinate
/// row of its (comfortable-only) card.
///
/// `HHhMMm` / `±DD°MM'` — arcminute precision, which is all a 28 px line has
/// room for and all a plan review needs; the arcsecond figure lives in the
/// inspector. An unset pointing says so in `warning`, exactly as
/// [TargetHeaderCard] does, because exactly 0h/+0° is a real point in Pisces
/// and printing it as a settled pointing is the bug
/// [targetCoordinatesUnset] exists to prevent.
List<Widget> _targetCoordinateChips(
  TargetHeaderNode node,
  NightshadeColors colors,
) {
  if (targetCoordinatesUnset(node)) {
    return <Widget>[
      _LedgerChip(colors: colors, label: 'Not set', tone: colors.warning),
    ];
  }
  return <Widget>[
    _LedgerChip(
      colors: colors,
      label: CoordinateFormat.raHm(
        node.raHours,
        style: SexagesimalStyle.compactLetters,
        wrapHours: true,
      ),
    ),
    _LedgerChip(
      colors: colors,
      label: CoordinateFormat.decDm(
        node.decDegrees,
        style: SexagesimalStyle.compactLetters,
      ),
    ),
  ];
}

/// A chip on a ledger row.
///
/// [tone] null is the neutral chip — a fact about the node (a coordinate).
/// A toned chip carries STATE, and it takes the same colour the rest of the
/// row uses for that state: the running chip is `primary` to match the row's
/// tint and its left marker, rather than adding a second colour for one fact.
class _LedgerChip extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final Color? tone;

  const _LedgerChip({required this.colors, required this.label, this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: NightshadeTokens.paddingXs,
      decoration: NightshadeDecorations.chip(colors, tone: tone),
      child: Text(
        label,
        style: NightshadeTypography.overline.copyWith(
          color: tone ?? colors.textSecondary,
        ),
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The depth guides a row draws to its left: one 18 px column per ancestor
/// level, each with a hairline down its leading edge.
///
/// Shared by [_LedgerRow] and [_LedgerFoldRow] so a folded run sits on exactly
/// the same indent grid as the rows around it — a run that indented by even a
/// pixel more would read as nested inside its own siblings.
List<Widget> _ledgerDepthGuides(int count, NightshadeColors colors) {
  return <Widget>[
    for (var i = 0; i < count; i++)
      ExcludeSemantics(
        child: SizedBox(
          width: _ledgerGuideWidth,
          height: _ledgerRowHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: _ledgerGuideLineWidth,
              height: _ledgerRowHeight,
              child: ColoredBox(color: colors.border),
            ),
          ),
        ),
      ),
  ];
}

/// The row's chevron: a full-height hit box around a 12 px glyph that rotates
/// a quarter turn between the two states.
///
/// One widget for both callers because the two states have to look identical
/// whether they belong to a container or to a folded run — the chevron IS the
/// tree's only "there is more under this line" affordance. [_LedgerFoldRow]
/// only ever mounts it collapsed (an expanded run is its member rows, with no
/// header of its own), so the rotation tween is exercised by containers.
class _LedgerChevron extends StatelessWidget {
  final NightshadeColors colors;
  final bool isCollapsed;
  final VoidCallback onToggle;

  /// Announced name and tooltip for the collapsed state. Defaults to the
  /// container wording; a folded run says what it expands into instead.
  final String? expandLabel;

  const _LedgerChevron({
    required this.colors,
    required this.isCollapsed,
    required this.onToggle,
    this.expandLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = isCollapsed ? (expandLabel ?? 'Expand') : 'Collapse';
    return Semantics(
      button: true,
      enabled: true,
      label: label,
      child: NightshadeTooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: SizedBox(
            width: _ledgerChevronWidth,
            height: _ledgerRowHeight,
            child: Center(
              child: AnimatedRotation(
                turns: isCollapsed ? -0.25 : 0,
                duration: _ledgerMotion(
                  context,
                  NightshadeTokens.durationQuick,
                ),
                curve: NightshadeTokens.curveStandard,
                child: Icon(
                  LucideIcons.chevronDown,
                  size: _ledgerChevronGlyph,
                  color: colors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The four right-aligned readout cells, in column order.
///
/// Shared so the folded row's cells sit on the same 70 / 60 / 74 / 62 grid as
/// every other row's — the ledger's whole promise is that a column means the
/// same thing all the way down, which requires the cells to be laid out by one
/// piece of code.
class _LedgerColumnCells extends StatelessWidget {
  final List<String> values;
  final Color color;

  /// Overrides [color] for the ETA cell only, for the case where the row is
  /// still quoting a prediction the run has already overtaken.
  final Color? etaColor;

  const _LedgerColumnCells({
    required this.values,
    required this.color,
    this.etaColor,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < _ledgerColumnWidths.length; i++)
            SizedBox(
              width: _ledgerColumnWidths[i],
              child: Text(
                values[i],
                style: NightshadeTypography.readoutXs.copyWith(
                  color: i == _ledgerColumnWidths.length - 1
                      ? (etaColor ?? color)
                      : color,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

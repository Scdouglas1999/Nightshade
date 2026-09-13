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

/// Width reserved for the hover-revealed kebab. Reserved rather than inserted
/// on hover: appearing actions that push the columns sideways make a ledger
/// unreadable exactly when the pointer is in it.
const double _ledgerActionsWidth = 24.0;

/// Trailing gutter. `_NodeValidationWrapper` positions its 18 px badge at the
/// row's top-right, so without this the badge would sit on top of the ETA
/// digits of every invalid row.
const double _ledgerBadgeGutter = 22.0;

/// Width of the row a drag carries in the feedback layer.
///
/// The columns (266), the badge gutter, the reserved kebab and the running
/// marker account for 314 of it, which leaves the name the same ~146 px it has
/// in a canvas of ordinary width — a narrower feedback row would ellipsise a
/// name that is perfectly readable in the tree it came from.
const double _ledgerDragFeedbackWidth = 460.0;

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
/// Marker + guides + chevron + icon + the reserved kebab + the columns
/// themselves + the badge gutter already cost ~350 px at depth 1 and grow 18
/// px a level, so below this the readout block would leave no room for the
/// step's own name. Past it the rows degrade to the same line minus the
/// columns — a narrow pane hides data but must never overflow — and the
/// header drops its labels to match.
const double _ledgerColumnsMinWidth = 420.0;

/// Zero when the platform asks for no animation, so every ledger animation is
/// gated in one place.
Duration _ledgerMotion(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// The column header, rendered once above the tree in Ledger mode.
///
/// Lives INSIDE the tree's scroll view so it takes the same horizontal padding
/// the rows do and its labels sit over the columns they name.
class _LedgerColumnHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _LedgerColumnHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    final style =
        NightshadeTypography.eyebrow.copyWith(color: colors.textMuted);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Same all-or-nothing tier as the rows: labels for columns that
          // are not drawn would be noise.
          final showColumns = constraints.maxWidth >= _ledgerColumnsMinWidth;
          return SizedBox(
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
                const SizedBox(width: _ledgerActionsWidth),
                if (showColumns)
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
          );
        },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // The column block is all-or-nothing: a row that kept Duration but
        // dropped ETA would read as misaligned, and rows disagreeing about
        // whether the columns exist would break the ledger's one promise.
        final showColumns = constraints.maxWidth >= _ledgerColumnsMinWidth;
        return _buildRow(context, showColumns: showColumns);
      },
    );
  }

  Widget _buildRow(BuildContext context, {required bool showColumns}) {
    final colors = widget.colors;
    final node = widget.node;

    final rollup = ref.watch(nodeRollupDurationProvider(node.id));
    final eta =
        ref.watch(ledgerEtaProvider.select((starts) => starts[node.id]));
    final columns = ledgerColumnsFor(
      node,
      widget.sequence,
      rollup: rollup,
      eta: eta,
    );
    // A collapsed container has to say what it is standing in for; an expanded
    // one has its children on screen and needs no summary.
    final summary = widget.isCollapsed && widget.isContainer
        ? rollupSummary(node, widget.sequence)
        : '';

    final status = widget.nodeStatus;
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
      showColumns: showColumns,
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
    required bool showColumns,
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
        for (var i = 0; i < guides; i++)
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
                  _LedgerChip(
                    colors: colors,
                    label: 'Running',
                    tone: colors.primary,
                  ),
                ],
                // A target's pointing is what distinguishes it from every
                // other target, and Ledger has no card to put it on.
                if (node is TargetHeaderNode)
                  for (final chip in _targetCoordinateChips(node, colors)) ...[
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    chip,
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
        if (showColumns)
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < _ledgerColumnWidths.length; i++)
                  SizedBox(
                    width: _ledgerColumnWidths[i],
                    child: Text(
                      columns.values[i],
                      style: NightshadeTypography.readoutXs.copyWith(
                        color: columnColor,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(width: _ledgerBadgeGutter),
      ],
    );
  }

  Widget _buildChevron(BuildContext context) {
    if (!widget.isContainer) {
      return const SizedBox(width: _ledgerChevronWidth);
    }
    final label = widget.isCollapsed ? 'Expand' : 'Collapse';
    return Semantics(
      button: true,
      enabled: true,
      label: label,
      child: NightshadeTooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref
              .read(collapsedNodeIdsProvider.notifier)
              .toggle(widget.node.id),
          child: SizedBox(
            width: _ledgerChevronWidth,
            height: _ledgerRowHeight,
            child: Center(
              child: AnimatedRotation(
                turns: widget.isCollapsed ? -0.25 : 0,
                duration: _ledgerMotion(
                  context,
                  NightshadeTokens.durationQuick,
                ),
                curve: NightshadeTokens.curveStandard,
                child: Icon(
                  LucideIcons.chevronDown,
                  size: _ledgerChevronGlyph,
                  color: widget.colors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The hover-revealed kebab, in permanently reserved width.
  ///
  /// A touch pointer has no hover, so on a touch screen the kebab is simply
  /// always there — an invisible menu is not an affordance.
  Widget _buildActions(BuildContext context) {
    if (widget.isDragging) {
      return const SizedBox(width: _ledgerActionsWidth);
    }
    final alwaysVisible = NightshadeTouchTarget.isTouch(context);
    final menu = _NodeOverflowMenu(
      colors: widget.colors,
      node: widget.node,
      onToggleEnabled: widget.onToggleEnabled,
      onDuplicate: widget.onDuplicate,
      onDelete: widget.onDelete,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
    );
    return SizedBox(
      width: _ledgerActionsWidth,
      height: _ledgerRowHeight,
      child: ValueListenableBuilder<bool>(
        valueListenable: _isHovered,
        child: menu,
        builder: (context, hovered, child) {
          final visible = alwaysVisible || hovered;
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
          // a solid line, not a line inside a groove.
          if (isRunning) ColoredBox(color: colors.surfaceHover),
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
      ),
    );
  }
}

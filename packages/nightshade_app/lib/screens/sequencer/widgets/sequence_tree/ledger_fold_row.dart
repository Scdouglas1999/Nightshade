part of '../sequence_tree.dart';

// The folded row: one 28 px line standing in for a whole run of sibling steps
// (spec §6). Same anatomy as [_LedgerRow] — the columns have to line up
// through it — but everything it shows is an aggregate of its members.
//
// It exists only while the run is folded. Unfolding removes this row and
// renders the members as ordinary [_LedgerRow]s, which is why the chevron here
// is always the collapsed one: an expanded run has no header of its own.

/// Selection for a folded row: the run is one row, so it selects as one.
///
/// Plain tap replaces the selection with the whole run and points the
/// inspector at the FIRST member — the properties panel edits nodes, not
/// groups, and a panel showing nothing while three rows are highlighted reads
/// as a broken selection. Ctrl adds or removes the run as a unit (a run
/// half-in the batch set would make the batch bar's count disagree with what
/// is highlighted — the defect `_handleNodeSelect` already guards against for
/// single rows). Shift extends from the anchor through the run's LAST member,
/// so the range covers everything the row draws.
void _handleFoldSelect(WidgetRef ref, FoldGroup group) {
  final keyboard = HardwareKeyboard.instance;
  final multi = ref.read(multiSelectedNodeIdsProvider.notifier);

  if (keyboard.isControlPressed || keyboard.isMetaPressed) {
    final selection = ref.read(multiSelectedNodeIdsProvider);
    final next = Set<String>.of(selection);
    // The first Ctrl+click folds the existing primary selection into the set
    // for the same reason a single row does: the primary row is painted
    // selected, so leaving it out makes every batch action skip a row the
    // user can see is selected.
    final primaryId = ref.read(selectedNodeIdProvider);
    if (selection.isEmpty &&
        primaryId != null &&
        !group.memberIds.contains(primaryId)) {
      next.add(primaryId);
    }
    if (group.memberIds.every(selection.contains)) {
      next.removeAll(group.memberIds);
    } else {
      next.addAll(group.memberIds);
    }
    multi.selectAll(next);
    return;
  }

  if (keyboard.isShiftPressed) {
    multi.rangeSelect(group.memberIds.last);
    return;
  }

  multi.selectAll(group.memberIds);
  ref.read(selectedNodeIdProvider.notifier).state = group.memberIds.first;
}

class _LedgerFoldRow extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final FoldGroup group;
  final SequenceProgress progress;

  /// Render depth of the run's members — the depth their own rows would draw
  /// at, so folding and unfolding does not shift the indent.
  final int depth;

  /// True in a drag's feedback layer: no hover, no actions, no selection.
  final bool isDragging;

  final VoidCallback? onSelect;
  final VoidCallback? onDisableAll;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _LedgerFoldRow({
    required this.colors,
    required this.group,
    required this.progress,
    required this.depth,
    this.isDragging = false,
    this.onSelect,
    this.onDisableAll,
    this.onDuplicate,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  ConsumerState<_LedgerFoldRow> createState() => _LedgerFoldRowState();
}

class _LedgerFoldRowState extends ConsumerState<_LedgerFoldRow> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  // Same contract and debug label as every other tree row: selecting the row
  // takes keyboard focus so the screen's Delete / Ctrl+Z bindings apply to it,
  // and tooling that asks "does a tree row have focus" must not have to know
  // whether the row stands for one step or five.
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
    final group = widget.group;

    final state = _aggregateState();
    final columns = _columns();
    final summary = foldProgressText(group, widget.progress);
    final isSelected = ref.watch(
      multiSelectedNodeIdsProvider
          .select((ids) => group.memberIds.every(ids.contains)),
    );

    final content = _buildContent(
      context: context,
      columns: columns,
      summary: summary,
      state: state,
    );

    final row = SizedBox(
      height: _ledgerRowHeight,
      child: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _isHovered,
            child: content,
            builder: (context, hovered, child) => AnimatedContainer(
              duration: _ledgerMotion(context, NightshadeTokens.durationFast),
              curve: NightshadeTokens.curveStandard,
              decoration: BoxDecoration(
                color: _fill(
                  isRunning: state.isRunning,
                  isSelected: isSelected,
                  hovered: hovered,
                ),
              ),
              foregroundDecoration: isSelected
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
          if (state.hasBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildProgressBar(state),
            ),
        ],
      ),
    );

    final semanticsRow = Semantics(
      button: true,
      selected: isSelected,
      // A folded run is never "expanded" — expanding it replaces this row with
      // its members, so the state a reader hears here is always the folded one.
      expanded: false,
      label: _semanticsLabel(columns: columns, summary: summary, state: state),
      hint: 'Select the whole run. More actions apply to every step in it.',
      child: Focus(
        focusNode: _rowFocusNode,
        skipTraversal: true,
        child: GestureDetector(
          onTap: () {
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

  /// Running wins over selection, which wins over hover — the same precedence
  /// [_LedgerRow] paints with, so a folded run reads as the same kind of row.
  Color? _fill({
    required bool isRunning,
    required bool isSelected,
    required bool hovered,
  }) {
    final colors = widget.colors;
    if (isRunning) {
      return colors.primary.withValues(
        alpha: NightshadeTokens.opacityAccentTint,
      );
    }
    if (isSelected) return colors.surfaceElevated;
    if (hovered) return colors.surfaceHover;
    return null;
  }

  Widget _buildContent({
    required BuildContext context,
    required LedgerColumns columns,
    required String summary,
    required _FoldRowState state,
  }) {
    final colors = widget.colors;
    final group = widget.group;

    final nameColor = state.hasFailure
        ? colors.error
        : state.isDone
            ? colors.textMuted
            : colors.textPrimary;
    final columnColor = state.isDone ? colors.textMuted : colors.textSecondary;

    return Row(
      children: [
        SizedBox(
          width: _ledgerRunningMarkerWidth,
          height: _ledgerRowHeight,
          child: state.isRunning ? ColoredBox(color: colors.primary) : null,
        ),
        ..._ledgerDepthGuides(widget.depth - 1, colors),
        _LedgerChevron(
          colors: colors,
          isCollapsed: true,
          expandLabel: 'Expand run',
          onToggle: () =>
              ref.read(unfoldedGroupIdsProvider.notifier).toggle(group.id),
        ),
        ExcludeSemantics(
          child: Icon(
            // A filter run is a stack of exposures, so it keeps the exposure
            // glyph; the acquire quartet is four different instructions and
            // gets the "several things in one" glyph instead.
            group.kind == FoldKind.filterRun
                ? sequenceNodeIcon('camera')
                : LucideIcons.layers,
            size: _ledgerIconSize,
            color: state.isDone ? colors.textMuted : state.tint(colors),
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: ExcludeSemantics(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    group.label,
                    style: NightshadeTypography.bodySm.copyWith(
                      // A folded row stands for several steps, so it carries
                      // the container weight even though its members are
                      // leaves.
                      fontWeight: FontWeight.w600,
                      color: nameColor,
                    ),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.isRunning) ...[
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  _LedgerChip(
                    colors: colors,
                    label: 'Running',
                    tone: colors.primary,
                  ),
                ],
                const SizedBox(width: NightshadeTokens.spaceSm),
                _LedgerChip(colors: colors, label: group.chipText),
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
        _LedgerColumnCells(values: columns.values, color: columnColor),
        const SizedBox(width: _ledgerBadgeGutter),
      ],
    );
  }

  /// The hover-revealed actions block, in the same permanently reserved width
  /// [_LedgerRow] uses so the columns do not shift between a folded row and
  /// the rows above and below it.
  Widget _buildActions(BuildContext context) {
    final isTouch = NightshadeTouchTarget.isTouch(context);
    final slotWidth = _ledgerActionsSlotWidth(context);
    if (widget.isDragging) {
      return SizedBox(width: slotWidth);
    }
    final menu = _FoldOverflowMenu(
      colors: widget.colors,
      group: widget.group,
      onDisableAll: widget.onDisableAll,
      onDuplicate: widget.onDuplicate,
      onDelete: widget.onDelete,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
    );
    final actions = isTouch
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
              _FoldActionChips(
                colors: widget.colors,
                onDisableAll: widget.onDisableAll,
                onDuplicate: widget.onDuplicate,
                onDelete: widget.onDelete,
              ),
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

  /// The 2 px bar: the run's aggregate progress, not any one member's.
  Widget _buildProgressBar(_FoldRowState state) {
    final colors = widget.colors;
    final Color fill;
    if (state.isRunning) {
      fill = colors.primary;
    } else if (state.hasFailure) {
      fill = colors.error;
    } else {
      fill = colors.success;
    }

    return SizedBox(
      height: _ledgerProgressHeight,
      child: Stack(
        children: [
          if (state.isRunning)
            Positioned.fill(child: ColoredBox(color: colors.surfaceHover)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: state.fraction,
              heightFactor: 1,
              child: ColoredBox(color: fill),
            ),
          ),
        ],
      ),
    );
  }

  /// The run's aggregate status and how far through it the night is.
  _FoldRowState _aggregateState() {
    final group = widget.group;
    final progress = widget.progress;
    var running = false;
    var failed = false;
    var finished = 0;
    var done = 0;
    var completion = 0.0;
    for (final memberId in group.memberIds) {
      final status = progress.nodeStatuses[memberId];
      switch (status) {
        case NodeStatus.running:
          running = true;
          completion += ((progress.nodeProgressPercent[memberId] ?? 0) / 100.0)
              .clamp(0.0, 1.0);
        case NodeStatus.success:
          finished++;
          done++;
          completion += 1.0;
        case NodeStatus.failure:
          failed = true;
          finished++;
          completion += 1.0;
        case NodeStatus.skipped || NodeStatus.cancelled:
          finished++;
          done++;
          completion += 1.0;
        case NodeStatus.pending || null:
          break;
      }
    }
    final memberCount = group.memberIds.length;
    return _FoldRowState(
      isRunning: running,
      hasFailure: failed,
      // "Done" recedes the row's text. A run with a failure in it does not
      // recede — that is the one outcome the operator has to be able to find.
      isDone: !running && !failed && done == memberCount,
      hasBar: running || finished > 0,
      fraction: (completion / memberCount).clamp(0.0, 1.0),
    );
  }

  /// The four columns for the run.
  ///
  /// Filter / exp carries the shared sub length only: the filters themselves
  /// are the row's NAME, and repeating them in a 70 px cell would just
  /// ellipsise them. Count multiplies the shared frame count by the number of
  /// members, Duration sums the members' own rollups, and ETA is the earliest
  /// member start — the moment the run begins.
  LedgerColumns _columns() {
    final group = widget.group;

    var total = Duration.zero;
    for (final memberId in group.memberIds) {
      total += ref.watch(nodeRollupDurationProvider(memberId));
    }

    LedgerEta? earliest;
    for (final memberId in group.memberIds) {
      final eta = ref.watch(
        ledgerEtaProvider.select((etas) => etas[memberId]),
      );
      if (eta == null) continue;
      if (earliest == null || eta.start.isBefore(earliest.start)) {
        earliest = eta;
      }
    }

    final durationSecs = group.durationSecs;
    final count = group.count;
    return LedgerColumns(
      filterExp: durationSecs == null ? '' : '${_fmtFoldSecs(durationSecs)}s',
      count: count == null ? '' : '${count * group.memberIds.length}',
      duration: total.inSeconds <= 0 ? '' : formatRollupDuration(total),
      eta: earliest == null ? '' : formatLedgerClock(earliest.start),
    );
  }

  /// What the run announces: its name, its chip, whatever progress line it is
  /// showing, its four column values, and the fact that it stands for several
  /// steps. The progress line is in there because it is on the row — a reader
  /// that cannot see `Ha 6/12 · OIII 0/12` would otherwise hear a run with no
  /// indication of how far through it the night is.
  String _semanticsLabel({
    required LedgerColumns columns,
    required String summary,
    required _FoldRowState state,
  }) {
    final stateWord = state.isRunning
        ? 'running'
        : state.hasFailure
            ? 'failed'
            : state.isDone
                ? 'done'
                : '';
    return <String>[
      widget.group.label,
      widget.group.chipText,
      if (summary.isNotEmpty) summary,
      ...columns.values.where((value) => value.isNotEmpty),
      if (stateWord.isNotEmpty) stateWord,
      'folded group of ${widget.group.memberIds.length} steps',
    ].join(' · ');
  }
}

/// The aggregate the folded row paints from: one run's worth of member
/// statuses reduced to the handful of facts a 28 px line can show.
class _FoldRowState {
  final bool isRunning;
  final bool hasFailure;
  final bool isDone;

  /// Whether the 2 px bar renders at all — a run nothing has touched shows no
  /// bar, exactly as an untouched [_LedgerRow] does.
  final bool hasBar;

  /// Share of the run that is complete, counting a running member by its own
  /// percentage.
  final double fraction;

  const _FoldRowState({
    required this.isRunning,
    required this.hasFailure,
    required this.isDone,
    required this.hasBar,
    required this.fraction,
  });

  /// The glyph tint: a filter run is imaging (instruction category), the
  /// acquire quartet is the mount/focus work that sets a target up (also
  /// instruction) — both take the same family the member rows would.
  Color tint(NightshadeColors colors) =>
      nodeCategoryTint(NodeCategory.instruction, colors);
}

/// The eye / duplicate / delete trio for a run. Same chips, same reserved
/// footprint and same hover reveal as [_NodeActionChips]; every label says
/// "all" so a click cannot be mistaken for a single-step edit.
class _FoldActionChips extends ConsumerWidget {
  final NightshadeColors colors;
  final VoidCallback? onDisableAll;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  const _FoldActionChips({
    required this.colors,
    required this.onDisableAll,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canEditSequenceProvider);
    const lockedSuffix = ' (locked while sequence is running)';
    final lockedTail = canEdit ? '' : lockedSuffix;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NodeActionButton(
          // Every member of a folded run is enabled — a disabled step is not
          // part of a run — so this chip only ever offers the one direction.
          icon: LucideIcons.eye,
          tooltip: 'Disable all$lockedTail',
          colors: colors,
          onPressed: canEdit ? onDisableAll : null,
        ),
        _NodeActionButton(
          icon: LucideIcons.copy,
          tooltip: 'Duplicate all$lockedTail',
          colors: colors,
          onPressed: canEdit ? onDuplicate : null,
        ),
        _NodeActionButton(
          icon: LucideIcons.trash2,
          tooltip: 'Delete all$lockedTail',
          colors: colors,
          color: colors.error,
          onPressed: canEdit ? onDelete : null,
        ),
      ],
    );
  }
}

/// The folded row's kebab.
///
/// It is [_NodeOverflowMenu] minus the entries that have no meaning for a run:
/// "Save as Template" promotes ONE subtree to the library and a run is not a
/// subtree, and the touch trio's labels all gain "all". Move Up / Move Down
/// stay — they move the whole block by one slot — and are shown disabled with
/// the reason rather than hidden, so the menu is never empty and the user
/// learns why the block cannot go further.
class _FoldOverflowMenu extends ConsumerWidget {
  final NightshadeColors colors;
  final FoldGroup group;
  final VoidCallback? onDisableAll;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _FoldOverflowMenu({
    required this.colors,
    required this.group,
    this.onDisableAll,
    this.onDuplicate,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canEditSequenceProvider);
    return _treeMenuSurface(
      context,
      colors,
      child: PopupMenuButton<String>(
        icon: Icon(LucideIcons.moreVertical, size: 14, color: colors.textMuted),
        tooltip: 'More Actions',
        padding: EdgeInsets.zero,
        itemBuilder: (context) => [
          if (NightshadeTouchTarget.isTouch(context)) ...[
            _entry(
              value: 'disable_all',
              label: 'Disable all',
              enabled: canEdit,
              height: 40,
            ),
            _entry(
              value: 'duplicate',
              label: 'Duplicate all',
              enabled: canEdit,
              height: 40,
            ),
            _entry(
              value: 'delete',
              label: 'Delete all',
              enabled: canEdit,
              height: 40,
              labelColor: colors.error,
            ),
            const PopupMenuDivider(height: 8),
          ],
          _entry(
            value: 'move_up',
            label: 'Move Up',
            enabled: canEdit && onMoveUp != null,
            tooltip: onMoveUp == null
                ? 'Already the first steps in their container.'
                : null,
          ),
          _entry(
            value: 'move_down',
            label: 'Move Down',
            enabled: canEdit && onMoveDown != null,
            tooltip: onMoveDown == null
                ? 'Already the last steps in their container.'
                : null,
          ),
        ],
        onSelected: (value) {
          switch (value) {
            case 'disable_all':
              onDisableAll?.call();
            case 'duplicate':
              onDuplicate?.call();
            case 'delete':
              onDelete?.call();
            case 'move_up':
              onMoveUp?.call();
            case 'move_down':
              onMoveDown?.call();
          }
        },
      ),
    );
  }

  PopupMenuItem<String> _entry({
    required String value,
    required String label,
    required bool enabled,
    double height = 32,
    Color? labelColor,
    String? tooltip,
  }) {
    final text = Text(
      label,
      style: NightshadeTypography.bodySm.copyWith(
        color: enabled ? (labelColor ?? colors.textPrimary) : colors.textMuted,
      ),
    );
    return PopupMenuItem<String>(
      value: value,
      height: height,
      enabled: enabled,
      child: tooltip == null ? text : Tooltip(message: tooltip, child: text),
    );
  }
}

/// `300` not `300.0`, `1.5` not `1.50` — the compact-second spelling the
/// Filter / exp column uses on every other row (`ledger_columns.dart`), so the
/// folded run's cell reads as the same quantity as the cells above it.
String _fmtFoldSecs(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

part of '../sequence_tree.dart';

class _NodeItem extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final SequenceNode node;
  final bool isSelected;
  final NodeStatus? nodeStatus;
  final bool hasChildren;
  final int depth;
  final VoidCallback? onSelect;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool isDragging;
  final double? progressPercent;
  final String? progressDetail;
  final InstructionProgressDetail? structuredProgressDetail;
  final bool isMobile;

  /// The filter the RUN is using, from `SequenceProgress.currentFilter`.
  ///
  /// An exposure node with no filter of its own still images through whatever
  /// is in the wheel, and the run names that filter everywhere else — the
  /// telemetry strip, the thumbnails, the FITS filenames and the session
  /// report all said `R` while this card's own header said "No Filter"
  /// (Wave D, SEQ-19).
  final String? runFilter;

  /// Whether this node is collapsed in the tree (children hidden). Drives the
  /// chevron rotation; kept in sync with [collapsedNodeIdsProvider] which the
  /// chevron tap toggles. Computed by [_NodeTreeView] so the two stay
  /// consistent. Only meaningful for containers ([hasChildren] / target).
  final bool isCollapsed;

  const _NodeItem({
    super.key,
    required this.colors,
    required this.node,
    required this.isSelected,
    required this.nodeStatus,
    required this.hasChildren,
    required this.depth,
    this.onSelect,
    this.onToggleEnabled,
    this.onDelete,
    this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
    this.isDragging = false,
    this.progressPercent,
    this.progressDetail,
    this.structuredProgressDetail,
    this.runFilter,
    this.isMobile = false,
    this.isCollapsed = false,
  });

  @override
  ConsumerState<_NodeItem> createState() => _NodeItemState();
}

class _NodeItemState extends ConsumerState<_NodeItem> {
  // Hover state lives in a ValueNotifier (not setState) so moving the mouse
  // over the row doesn't rebuild the whole _NodeItem subtree — only the two
  // hover-dependent islands (background color + action cluster) listen.
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  // Selecting a row takes keyboard focus. The screen's Delete / Ctrl+D /
  // Ctrl+Z bindings are a `CallbackShortcuts` subtree, so they only fire
  // while primary focus is inside it — and the palette's search field, which
  // is where a user is typing moments before they click the node they want to
  // delete, holds focus and swallows those keys. Rows are click targets, not
  // tab stops (`skipTraversal`), so this changes what the keys act on without
  // inserting a stop per node into the tab order.
  final FocusNode _rowFocusNode = FocusNode(debugLabel: 'sequence-tree-row');

  // For progress panel persistence
  bool _showProgressPanel = false;
  DateTime? _lastRunningTime;
  Timer? _panelPersistTimer;
  static const _panelPersistDuration = Duration(seconds: 20);

  // The last live progress this row was handed, kept for as long as its panel
  // outlives the run.
  //
  // The panel is deliberately shown for 20s AFTER a node stops running, but it
  // was rendered from whatever the progress maps held *at that moment*. On the
  // success path those per-node entries are gone by then, so the card fell all
  // the way back to its defaults and announced "0 / 4 frames" with four empty
  // boxes directly above the four thumbnails it had just captured, while the
  // Session Report on the same screen said "Frames accepted 4/4" (Wave D,
  // SEQ-18). A run stopped at frame 1 kept its detail and read "1 / 4", which
  // is what made the zeroing look specific to success.
  //
  // Remembering the last non-null value makes the card independent of WHEN the
  // maps are cleared: it keeps showing the last thing that was true instead of
  // inventing a zero. Cleared when the node starts running again so one run
  // can never show the previous run's frames.
  NodeStatus? _lastKnownStatus;
  double? _lastKnownPercent;
  String? _lastKnownDetail;
  InstructionProgressDetail? _lastKnownStructuredDetail;
  String? _lastKnownRunFilter;

  void _rememberLiveProgress() {
    if (widget.nodeStatus != null) _lastKnownStatus = widget.nodeStatus;
    if (widget.progressPercent != null) {
      _lastKnownPercent = widget.progressPercent;
    }
    if (widget.progressDetail != null) {
      _lastKnownDetail = widget.progressDetail;
    }
    if (widget.structuredProgressDetail != null) {
      _lastKnownStructuredDetail = widget.structuredProgressDetail;
    }
    if (widget.runFilter != null) _lastKnownRunFilter = widget.runFilter;
  }

  void _forgetLiveProgress() {
    _lastKnownStatus = null;
    _lastKnownPercent = null;
    _lastKnownDetail = null;
    _lastKnownStructuredDetail = null;
    _lastKnownRunFilter = null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.nodeStatus == NodeStatus.running) {
      _showProgressPanel = true;
      _lastRunningTime = DateTime.now();
    }
    _rememberLiveProgress();
  }

  @override
  void didUpdateWidget(_NodeItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nodeStatus == NodeStatus.running &&
        oldWidget.nodeStatus != NodeStatus.running) {
      // A fresh pass over this node: last run's frames are no longer its story.
      _forgetLiveProgress();
    }
    _rememberLiveProgress();
    if (widget.nodeStatus == NodeStatus.running) {
      _showProgressPanel = true;
      _lastRunningTime = DateTime.now();
    } else {
      // Keep panel visible for 20 seconds after node stops running. Owned so
      // we can cancel on dispose — a teardown mid-delay would otherwise leak
      // a pending Timer past the widget tree.
      if (oldWidget.nodeStatus == NodeStatus.running && _showProgressPanel) {
        _panelPersistTimer?.cancel();
        _panelPersistTimer = Timer(_panelPersistDuration, () {
          if (mounted && widget.nodeStatus != NodeStatus.running) {
            setState(() => _showProgressPanel = false);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _panelPersistTimer?.cancel();
    _isHovered.dispose();
    _rowFocusNode.dispose();
    super.dispose();
  }

  bool get _shouldShowProgressPanel {
    // Show panel whenever node is running
    if (widget.nodeStatus == NodeStatus.running) {
      return true;
    }

    // Show panel during persistence period after node stops running
    if (_showProgressPanel && _lastRunningTime != null) {
      final elapsed = DateTime.now().difference(_lastRunningTime!);
      return elapsed < _panelPersistDuration;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor();
    final statusColor = _getStatusColor();
    // An Autofocus node in defaults mode runs the AppSettings method, not its
    // own `method` field, so the row (and the screen-reader phrase built from
    // it) has to be told what that global method is.
    final node = widget.node;
    final globalAfMethod = node is AutofocusNode && node.useSettingsDefaults
        ? ref.watch(autofocusSettingsProvider).method
        : null;
    final summaryFragments =
        nodeSummary(node, globalAutofocusMethod: globalAfMethod);
    final summaryA11yText = _summaryA11yText(summaryFragments);
    final isDisabled = !widget.node.isEnabled;
    final isRunning = widget.nodeStatus == NodeStatus.running;
    final isSuccess = widget.nodeStatus == NodeStatus.success;
    final isFailed = widget.nodeStatus == NodeStatus.failure;
    final isSkipped = widget.nodeStatus == NodeStatus.skipped;
    final isCancelled = widget.nodeStatus == NodeStatus.cancelled;
    final isTargetHeader = widget.node is TargetHeaderNode;
    final isMobile = widget.isMobile;

    // Mobile-optimized sizes
    final verticalMargin = isMobile ? 4.0 : 2.0;
    final horizontalPadding = isMobile ? 14.0 : 12.0;
    final verticalPadding = isMobile ? 14.0 : 10.0;
    final iconBoxSize = isMobile ? 40.0 : 32.0;
    final iconSize = isMobile ? 20.0 : 16.0;
    final borderRadius = isMobile ? 12.0 : 10.0;
    final titleFontSize = isMobile ? 14.0 : 12.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => _isHovered.value = true,
          onExit: (_) => _isHovered.value = false,
          child: Semantics(
            button: true,
            selected: widget.isSelected,
            enabled: widget.node.isEnabled,
            label: widget.node.name,
            value: summaryA11yText.isNotEmpty ? summaryA11yText : null,
            hint:
                'Select node. More actions include reorder and wrap commands.',
            child: Focus(
              focusNode: _rowFocusNode,
              skipTraversal: true,
              child: GestureDetector(
                onTap: () {
                  // Take focus FIRST: the click that selects a node is also
                  // the moment the keyboard shortcuts must start applying to
                  // it. Without this the palette's search field keeps primary
                  // focus and Delete / Ctrl+D / Ctrl+Z silently do nothing.
                  _rowFocusNode.requestFocus();
                  widget.onSelect?.call();
                },
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isHovered,
                  // The container's heavy child (icon / name / summary) is built
                  // ONCE and passed via `child`, so hover only recomputes the
                  // background color, not the whole row.
                  child: _buildRowBody(
                    context: context,
                    categoryColor: categoryColor,
                    statusColor: statusColor,
                    summaryFragments: summaryFragments,
                    isDisabled: isDisabled,
                    isRunning: isRunning,
                    isSuccess: isSuccess,
                    isFailed: isFailed,
                    isSkipped: isSkipped,
                    isCancelled: isCancelled,
                    isTargetHeader: isTargetHeader,
                    isMobile: isMobile,
                    iconBoxSize: iconBoxSize,
                    iconSize: iconSize,
                    titleFontSize: titleFontSize,
                  ),
                  builder: (context, hovered, child) => AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.symmetric(vertical: verticalMargin),
                    padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding),
                    decoration: BoxDecoration(
                      color: widget.isDragging
                          ? categoryColor.withValues(alpha: 0.2)
                          : widget.isSelected
                              ? NightshadeDecorations.selectedSurface(
                                      categoryColor)
                                  .color
                              : isSuccess
                                  ? widget.colors.success
                                      .withValues(alpha: 0.06)
                                  : isFailed
                                      ? widget.colors.error
                                          .withValues(alpha: 0.06)
                                      : (isSkipped || isCancelled)
                                          ? widget.colors.textMuted
                                              .withValues(alpha: 0.04)
                                          : isTargetHeader
                                              ? categoryColor.withValues(
                                                  alpha: 0.08)
                                              : hovered
                                                  ? widget.colors.surfaceAlt
                                                  : widget.colors.surface,
                      borderRadius: BorderRadius.circular(borderRadius),
                      border: Border.all(
                        color: widget.isSelected
                            ? categoryColor
                            : isRunning
                                ? widget.colors.info.withValues(alpha: 0.65)
                                : isTargetHeader
                                    ? categoryColor.withValues(alpha: 0.3)
                                    : widget.colors.border,
                        width: widget.isSelected || isTargetHeader ? 2 : 1,
                      ),
                      boxShadow: null,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Progress panel for expanded details
        if (_shouldShowProgressPanel)
          getProgressPanelForNode(
                node: widget.node,
                colors: widget.colors,
                progressPercent:
                    widget.progressPercent ?? _lastKnownPercent ?? 0,
                progressDetail: widget.progressDetail ?? _lastKnownDetail,
                structuredProgressDetail: widget.structuredProgressDetail ??
                    _lastKnownStructuredDetail,
                nodeStatus: widget.nodeStatus ?? _lastKnownStatus,
                runFilter: widget.runFilter ?? _lastKnownRunFilter,
              ) ??
              const SizedBox.shrink(),
      ],
    );
  }

  /// The static (hover-independent) body of the row: status bar, icon, name,
  /// summary, and the action cluster. Built once and handed to the
  /// background [ValueListenableBuilder] via its `child` slot.
  Widget _buildRowBody({
    required BuildContext context,
    required Color categoryColor,
    required Color statusColor,
    required List<SummaryFragment> summaryFragments,
    required bool isDisabled,
    required bool isRunning,
    required bool isSuccess,
    required bool isFailed,
    required bool isSkipped,
    required bool isCancelled,
    required bool isTargetHeader,
    required bool isMobile,
    required double iconBoxSize,
    required double iconSize,
    required double titleFontSize,
  }) {
    return Opacity(
      opacity: isDisabled
          ? 0.5
          : (isSkipped || isCancelled)
              ? 0.6
              : 1.0,
      child: Row(
        children: [
          // Status indicator
          if (widget.nodeStatus != null &&
              widget.nodeStatus != NodeStatus.pending)
            Container(
              width: 4,
              height: iconBoxSize,
              margin: EdgeInsets.only(right: isMobile ? 12 : 10),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline2),
              ),
            ),

          // Icon
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: NightshadeDecorations.tintedBadge(
              categoryColor,
              borderRadius: BorderRadius.circular(isMobile
                  ? NightshadeTokens.radiusLg
                  : NightshadeTokens.radiusInline8),
            ),
            child: isRunning
                ? _SpinningIcon(
                    icon: _getIcon(),
                    color: categoryColor,
                    size: iconSize,
                  )
                : Icon(
                    _getIcon(),
                    size: iconSize,
                    color: categoryColor,
                  ),
          ),
          SizedBox(width: isMobile ? 14 : 12),

          // Name and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row: the node name, followed inline by
                // the watchdog badge for trigger-category nodes
                // (e.g. Meridian Flip). The badge sits after the
                // title and before any trailing row-level status
                // indicator so it reads as a property of the
                // node, not of the run.
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.node.name,
                        style: TextStyle(
                          fontSize: isTargetHeader
                              ? titleFontSize + 1
                              : titleFontSize,
                          fontWeight: FontWeight.w600,
                          color: isSuccess
                              ? widget.colors.success
                              : isFailed
                                  ? widget.colors.error
                                  : (isSkipped || isCancelled)
                                      ? widget.colors.textMuted
                                      : widget.colors.textPrimary,
                          decoration: isDisabled || isSkipped || isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: isSkipped || isCancelled
                              ? widget.colors.textMuted
                              : null,
                        ),
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (widget.node.category == NodeCategory.trigger) ...[
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      _WatchdogBadge(colors: widget.colors),
                    ],
                  ],
                ),
                if (summaryFragments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                        top: NightshadeTokens.spaceXs / 2),
                    child: NodeSummaryLine(
                      node: widget.node,
                      colors: widget.colors,
                      isMobile: isMobile,
                      mutedColorOverride: (isSkipped || isCancelled)
                          ? widget.colors.textMuted
                          : null,
                    ),
                  ),
                // Show node comment as gray italic text
                if (widget.node.comment != null &&
                    widget.node.comment!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.node.comment!,
                      style: TextStyle(
                        fontSize: isMobile
                            ? NightshadeTypography.fontSize12
                            : NightshadeTypography.fontSize10,
                        color: widget.colors.textMuted.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                // Show progress bar for running instructions
                if (isRunning &&
                    widget.progressPercent != null &&
                    widget.progressPercent! > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.progressDetail != null &&
                            widget.progressDetail!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              widget.progressDetail!,
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10,
                                color: widget.colors.info,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline2),
                          child: LinearProgressIndicator(
                            value: widget.progressPercent! / 100.0,
                            minHeight: 4,
                            backgroundColor: widget.colors.surfaceAlt,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                widget.colors.info),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Actions — visibility tracks hover (or always on
          // mobile). Scoped to its own ValueListenableBuilder so
          // hovering only rebuilds this cluster, not the whole row.
          ValueListenableBuilder<bool>(
            valueListenable: _isHovered,
            builder: (context, hovered, _) {
              if (!((isMobile || hovered) && !widget.isDragging)) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Trust-patch §B: per-row action icons mutate
                  // the tree (toggle enabled, duplicate, delete)
                  // and must be disabled when a sequence is
                  // running. The kebab below already gated
                  // move_up/move_down; this is the matching
                  // gate for the inline icons.
                  Builder(builder: (context) {
                    final canEdit = ref.watch(canEditSequenceProvider);
                    const lockedSuffix = ' (locked while sequence is running)';
                    final lockedTail = canEdit ? '' : lockedSuffix;
                    final toggleLabel =
                        widget.node.isEnabled ? 'Disable' : 'Enable';
                    // On touch these fold into the kebab instead of sitting
                    // inline. Three 24dp chips are not legal Android tap
                    // targets, and padding each one up to 48 adds 72dp to a
                    // row that then overflows a 360dp phone by 30 — measured,
                    // not guessed. Moving them behind the kebab gives the same
                    // three actions a single already-compliant 48dp target and
                    // hands 84dp back to the row.
                    if (NightshadeTouchTarget.isTouch(context)) {
                      return const SizedBox.shrink();
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NodeActionButton(
                          icon: widget.node.isEnabled
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                          tooltip: '$toggleLabel$lockedTail',
                          colors: widget.colors,
                          onPressed: canEdit ? widget.onToggleEnabled : null,
                        ),
                        _NodeActionButton(
                          icon: LucideIcons.copy,
                          tooltip: 'Duplicate$lockedTail',
                          colors: widget.colors,
                          onPressed: canEdit ? widget.onDuplicate : null,
                        ),
                        _NodeActionButton(
                          icon: LucideIcons.trash2,
                          tooltip: 'Delete$lockedTail',
                          colors: widget.colors,
                          color: widget.colors.error,
                          onPressed: canEdit ? widget.onDelete : null,
                        ),
                      ],
                    );
                  }),

                  // Inline more-actions menu.
                  //
                  // Reconciliation: the right-click / long-press
                  // context menu (`SequenceTreeContextMenu`) is the
                  // comprehensive surface for tree mutations (Insert,
                  // Move Up/Down, Duplicate, Group, Enable/Disable,
                  // Delete). This kebab repeats:
                  //   * Move Up / Move Down — a visible, tappable
                  //     re-order handle. Touch has no right-click and
                  //     drag-reordering a row inside a scrolling tree
                  //     is fiddly, so the affordance stays on-screen.
                  //     (`sequence_tree_shortcuts.dart` binds
                  //     Shift+Up/Down to EXTEND the selection, not to
                  //     move a node — there is no keyboard reorder.)
                  //   * Save as Template — a "promote-this-subtree-
                  //     to-the-library" action that is not part of
                  //     the per-node edit vocabulary the context
                  //     menu covers.
                  // Items here respect `canEditSequenceProvider` —
                  // when a sequence is Running / Paused / Stopping
                  // the kebab still opens but mutating entries are
                  // disabled (Save as Template is read-only so it
                  // stays enabled).
                  Builder(builder: (context) {
                    final canEdit = ref.watch(canEditSequenceProvider);
                    return Theme(
                      data: Theme.of(context).copyWith(
                        popupMenuTheme: PopupMenuThemeData(
                          color: widget.colors.surfaceAlt,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                NightshadeTokens.radiusInline8),
                            side: BorderSide(color: widget.colors.border),
                          ),
                        ),
                      ),
                      child: PopupMenuButton<String>(
                        icon: Icon(LucideIcons.moreVertical,
                            size: 14, color: widget.colors.textMuted),
                        tooltip: 'More Actions',
                        padding: EdgeInsets.zero,
                        itemBuilder: (context) => [
                          // The inline eye / duplicate / delete chips are not
                          // rendered on touch (see above) — they live here so
                          // the actions stay reachable through one compliant
                          // target instead of three illegal ones.
                          if (NightshadeTouchTarget.isTouch(context)) ...[
                            PopupMenuItem<String>(
                              value: 'toggle_enabled',
                              height: 40,
                              enabled: canEdit,
                              child: Text(
                                widget.node.isEnabled ? 'Disable' : 'Enable',
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize13,
                                  color: canEdit
                                      ? widget.colors.textPrimary
                                      : widget.colors.textMuted,
                                ),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'duplicate',
                              height: 40,
                              enabled: canEdit,
                              child: Text(
                                'Duplicate',
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize13,
                                  color: canEdit
                                      ? widget.colors.textPrimary
                                      : widget.colors.textMuted,
                                ),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              height: 40,
                              enabled: canEdit,
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize13,
                                  color: canEdit
                                      ? widget.colors.error
                                      : widget.colors.textMuted,
                                ),
                              ),
                            ),
                            const PopupMenuDivider(height: 8),
                          ],
                          if (widget.onMoveUp != null)
                            PopupMenuItem<String>(
                              value: 'move_up',
                              height: 32,
                              enabled: canEdit,
                              child: Text('Move Up',
                                  style: TextStyle(
                                    fontSize: NightshadeTypography.fontSize13,
                                    color: canEdit
                                        ? widget.colors.textPrimary
                                        : widget.colors.textMuted,
                                  )),
                            ),
                          if (widget.onMoveDown != null)
                            PopupMenuItem<String>(
                              value: 'move_down',
                              height: 32,
                              enabled: canEdit,
                              child: Text('Move Down',
                                  style: TextStyle(
                                    fontSize: NightshadeTypography.fontSize13,
                                    color: canEdit
                                        ? widget.colors.textPrimary
                                        : widget.colors.textMuted,
                                  )),
                            ),
                          if (widget.onMoveUp != null ||
                              widget.onMoveDown != null)
                            const PopupMenuDivider(height: 8),
                          // Save as Template is read-only (it
                          // copies the subtree to the snippet
                          // library; it does not mutate the
                          // current sequence), so it stays enabled
                          // even while the sequence is running.
                          PopupMenuItem<String>(
                            value: 'save_snippet',
                            height: 32,
                            child: Text('Save as Template',
                                style: TextStyle(
                                    fontSize: NightshadeTypography.fontSize13,
                                    color: widget.colors.textPrimary)),
                          ),
                        ],
                        onSelected: (value) {
                          switch (value) {
                            case 'toggle_enabled':
                              widget.onToggleEnabled?.call();
                              break;
                            case 'duplicate':
                              widget.onDuplicate?.call();
                              break;
                            case 'delete':
                              widget.onDelete?.call();
                              break;
                            case 'move_up':
                              widget.onMoveUp?.call();
                              break;
                            case 'move_down':
                              widget.onMoveDown?.call();
                              break;
                            case 'save_snippet':
                              _showSaveAsSnippetDialog(
                                  context, ref, widget.node);
                              break;
                          }
                        },
                      ),
                    );
                  }),
                ],
              );
            },
          ),

          // Expand/collapse chevron for containers. Tapping it
          // toggles collapse via collapsedNodeIdsProvider; the
          // rotation follows widget.isCollapsed (kept in sync by
          // _NodeTreeView). Always shown for containers even when
          // empty to hint at nesting.
          if (widget.hasChildren || isTargetHeader)
            Tooltip(
              message: widget.isCollapsed ? 'Expand' : 'Collapse',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref
                    .read(collapsedNodeIdsProvider.notifier)
                    .toggle(widget.node.id),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AnimatedRotation(
                    turns: widget.isCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 14,
                      color: widget.colors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

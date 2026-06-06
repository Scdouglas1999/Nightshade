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
    this.isMobile = false,
  });

  @override
  ConsumerState<_NodeItem> createState() => _NodeItemState();
}

class _NodeItemState extends ConsumerState<_NodeItem> {
  bool _isHovered = false;

  // For progress panel persistence
  bool _showProgressPanel = false;
  DateTime? _lastRunningTime;
  Timer? _panelPersistTimer;
  static const _panelPersistDuration = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    if (widget.nodeStatus == NodeStatus.running) {
      _showProgressPanel = true;
      _lastRunningTime = DateTime.now();
    }
  }

  @override
  void didUpdateWidget(_NodeItem oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  void _showSaveAsSnippetDialog(
      BuildContext context, WidgetRef ref, SequenceNode node) {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;

    final nameController = TextEditingController(text: node.name);
    final descController = TextEditingController();
    SnippetCategory selectedCategory = SnippetCategory.custom;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: widget.colors.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          ),
          title: Row(
            children: [
              Icon(LucideIcons.bookmark,
                  size: 20, color: widget.colors.primary),
              const SizedBox(width: 12),
              Text(
                'Save as Template',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize18,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: AdaptiveDialogConstraints.hybrid(
              dialogContext,
              designMaxWidth: 360,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Name',
                    style: NightshadeTypography.labelSm.copyWith(color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style:
                      TextStyle(fontSize: NightshadeTypography.fontSize14, color: widget.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Template name',
                    hintStyle:
                        TextStyle(fontSize: NightshadeTypography.fontSize14, color: widget.colors.textMuted),
                    filled: true,
                    fillColor: widget.colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Description',
                    style: NightshadeTypography.labelSm.copyWith(color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  style:
                      TextStyle(fontSize: NightshadeTypography.fontSize14, color: widget.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'What does this template do?',
                    hintStyle:
                        TextStyle(fontSize: NightshadeTypography.fontSize14, color: widget.colors.textMuted),
                    filled: true,
                    fillColor: widget.colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                      borderSide: BorderSide(color: widget.colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Category',
                    style: NightshadeTypography.labelSm.copyWith(color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SnippetCategory>(
                      value: selectedCategory,
                      isExpanded: true,
                      dropdownColor: widget.colors.surfaceOverlay,
                      style: TextStyle(
                          fontSize: NightshadeTypography.fontSize14, color: widget.colors.textPrimary),
                      items: SnippetCategory.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(cat.name[0].toUpperCase() +
                              cat.name.substring(1)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedCategory = value);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a template name'),
                      backgroundColor: widget.colors.error,
                    ),
                  );
                  return;
                }

                try {
                  final snippet = createSnippetFromSelection(
                    name: name,
                    description: descController.text.trim().isEmpty
                        ? 'Custom template from ${node.nodeType}'
                        : descController.text.trim(),
                    category: selectedCategory,
                    iconName: node.iconName,
                    nodeIds: [node.id],
                    sequence: sequence,
                  );

                  ref.read(customSnippetsProvider.notifier).addSnippet(snippet);

                  Navigator.of(dialogContext).pop();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Template "$name" created successfully'),
                        backgroundColor: widget.colors.success,
                      ),
                    );
                  }
                } catch (e) {
                  Navigator.of(dialogContext).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to create template: $e'),
                        backgroundColor: widget.colors.error,
                      ),
                    );
                  }
                }
              },
              label: 'Save',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (widget.node.iconName) {
      case 'target':
        return LucideIcons.target;
      case 'camera':
        return LucideIcons.camera;
      case 'circle':
        return LucideIcons.circle;
      case 'shuffle':
        return LucideIcons.shuffle;
      case 'compass':
        return LucideIcons.compass;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'parking-circle':
        return LucideIcons.parkingCircle;
      case 'unlock':
        return LucideIcons.unlock;
      case 'focus':
        return LucideIcons.focus;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'flame':
        return LucideIcons.flame;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'repeat':
        return LucideIcons.repeat;
      case 'git-merge':
        return LucideIcons.gitMerge;
      case 'git-branch':
        return LucideIcons.gitBranch;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'clock':
        return LucideIcons.clock;
      case 'timer':
        return LucideIcons.timer;
      case 'bell':
        return LucideIcons.bell;
      case 'code':
        return LucideIcons.code;
      case 'list':
        return LucideIcons.list;
      // Wave 3 Agent 2: SmartExposure uses the layered-stack glyph.
      case 'layers':
        return LucideIcons.layers;
      default:
        return LucideIcons.box;
    }
  }

  Color _getCategoryColor() {
    switch (widget.node.category) {
      case NodeCategory.instruction:
        return widget.colors.primary;
      case NodeCategory.trigger:
        return widget.colors.warning;
      case NodeCategory.logic:
        return widget.colors.accent;
      case NodeCategory.target:
        return widget.colors.warning;
    }
  }

  Color _getStatusColor() {
    switch (widget.nodeStatus) {
      case NodeStatus.running:
        return widget.colors.info;
      case NodeStatus.success:
        return widget.colors.success;
      case NodeStatus.failure:
        return widget.colors.error;
      case NodeStatus.skipped:
        return widget.colors.textMuted;
      case NodeStatus.cancelled:
        return widget.colors.warning;
      default:
        return Colors.transparent;
    }
  }

  /// Build the plain-text accessibility string for the at-a-glance summary by
  /// joining each fragment's user-visible value. [EditableFragment]s expose
  /// their current [EditableFragment.displayValue]; [StaticFragment]s expose
  /// their text. Fragments are separated by a middle dot so screen readers
  /// announce a single, scannable phrase (e.g. "10 · × · 120s · Ha").
  String _summaryA11yText(List<SummaryFragment> fragments) {
    return fragments
        .map((f) => switch (f) {
              StaticFragment(text: final t) => t.trim(),
              EditableFragment(displayValue: final v) => v.trim(),
            })
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor();
    final statusColor = _getStatusColor();
    final summaryFragments = nodeSummary(widget.node);
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
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Semantics(
            button: true,
            selected: widget.isSelected,
            enabled: widget.node.isEnabled,
            label: widget.node.name,
            value: summaryA11yText.isNotEmpty ? summaryA11yText : null,
            hint:
                'Select node. More actions include reorder and wrap commands.',
            child: GestureDetector(
              onTap: widget.onSelect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.symmetric(vertical: verticalMargin),
                padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding, vertical: verticalPadding),
                decoration: BoxDecoration(
                  color: widget.isDragging
                      ? categoryColor.withValues(alpha: 0.2)
                      : widget.isSelected
                          ? NightshadeDecorations.selectedSurface(categoryColor)
                              .color
                          : isSuccess
                              ? widget.colors.success.withValues(alpha: 0.06)
                              : isFailed
                                  ? widget.colors.error.withValues(alpha: 0.06)
                                  : (isSkipped || isCancelled)
                                      ? widget.colors.textMuted
                                          .withValues(alpha: 0.04)
                                      : isTargetHeader
                                          ? categoryColor.withValues(
                                              alpha:
                                                  0.08) // Slight tint for target headers
                                          : _isHovered
                                              ? widget.colors.surfaceAlt
                                              : widget.colors.surface,
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: widget.isSelected
                        ? categoryColor
                        : isRunning
                            ? widget.colors.info.withValues(alpha: 0.65)
                            : isTargetHeader
                                ? categoryColor.withValues(
                                    alpha:
                                        0.3) // Stronger border for target headers
                                : widget.colors.border,
                    width: widget.isSelected || isTargetHeader
                        ? 2
                        : 1, // Thicker border for target headers
                  ),
                  boxShadow: null,
                ),
                child: Opacity(
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
                            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
                          ),
                        ),

                      // Icon
                      Container(
                        width: iconBoxSize,
                        height: iconBoxSize,
                        decoration: NightshadeDecorations.tintedBadge(
                          categoryColor,
                          borderRadius:
                              BorderRadius.circular(isMobile ? NightshadeTokens.radiusLg : NightshadeTokens.radiusInline8),
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
                                      decoration:
                                          isDisabled || isSkipped || isCancelled
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
                                if (widget.node.category ==
                                    NodeCategory.trigger) ...[
                                  const SizedBox(
                                      width: NightshadeTokens.spaceSm),
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
                                    fontSize: isMobile ? NightshadeTypography.fontSize12 : NightshadeTypography.fontSize10,
                                    color: widget.colors.textMuted
                                        .withValues(alpha: 0.7),
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
                                        padding:
                                            const EdgeInsets.only(bottom: 2),
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
                                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
                                      child: LinearProgressIndicator(
                                        value: widget.progressPercent! / 100.0,
                                        minHeight: 4,
                                        backgroundColor:
                                            widget.colors.surfaceAlt,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                widget.colors.info),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Actions
                      if ((isMobile || _isHovered) && !widget.isDragging) ...[
                        // Trust-patch §B: per-row action icons mutate
                        // the tree (toggle enabled, duplicate, delete)
                        // and must be disabled when a sequence is
                        // running. The kebab below already gated
                        // move_up/move_down; this is the matching
                        // gate for the inline icons.
                        Builder(builder: (context) {
                          final canEdit = ref.watch(canEditSequenceProvider);
                          const lockedSuffix =
                              ' (locked while sequence is running)';
                          final lockedTail = canEdit ? '' : lockedSuffix;
                          final toggleLabel =
                              widget.node.isEnabled ? 'Disable' : 'Enable';
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _NodeActionButton(
                                icon: widget.node.isEnabled
                                    ? LucideIcons.eye
                                    : LucideIcons.eyeOff,
                                tooltip: '$toggleLabel$lockedTail',
                                colors: widget.colors,
                                onPressed:
                                    canEdit ? widget.onToggleEnabled : null,
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
                        // context menu (`SequenceTreeContextMenu`) is now
                        // the comprehensive surface for tree mutations
                        // (Insert, Duplicate, Group, Enable/Disable,
                        // Delete). This kebab is intentionally limited to
                        // entries that don't belong in a generic
                        // right-click:
                        //   * Move Up / Move Down — a visible, tappable
                        //     re-order handle on touch and as a redundant
                        //     surface alongside the Shift+Up / Shift+Down
                        //     keyboard shortcut wired in
                        //     `sequence_tree_shortcuts.dart`.
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
                                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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

                      // Expand indicator for containers
                      if (widget.hasChildren ||
                          isTargetHeader) // Always show chevron for containers even if empty to hint at nesting
                        Icon(
                          LucideIcons.chevronDown,
                          size: 14,
                          color: widget.colors.textMuted,
                        ),
                    ],
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
                progressPercent: widget.progressPercent ?? 0,
                progressDetail: widget.progressDetail,
                structuredProgressDetail: widget.structuredProgressDetail,
              ) ??
              const SizedBox.shrink(),
      ],
    );
  }
}

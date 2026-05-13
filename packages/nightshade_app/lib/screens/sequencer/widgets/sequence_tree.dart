import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/tutorial_keys/sequencer_keys.dart';
import 'node_progress_panels.dart';
import 'sequence_minimap.dart';
import 'target_header_card.dart';
import 'visual_timeline.dart';

/// Provider to track when a node is being dragged globally
/// This allows all drop zones to become visible when any drag starts
final isDraggingNodeProvider = StateProvider<bool>((ref) => false);

/// Provider for "follow execution" toggle — auto-scrolls tree to current node
final followExecutionProvider = StateProvider<bool>((ref) => true);

/// GlobalKey registry for auto-scroll: maps node IDs to their GlobalKeys.
/// Populated by _NodeTreeView when building, used by auto-scroll logic.
final _nodeKeyRegistry = <String, GlobalKey>{};

/// Handle node selection with modifier key support for multi-select.
/// Ctrl+Click: toggle individual node in multi-selection.
/// Shift+Click: range-select siblings between anchor and clicked node.
/// Plain click: single-select (clears multi-selection).
void _handleNodeSelect(WidgetRef ref, String nodeId) {
  final isCtrlPressed = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight);

  final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight);

  if (isCtrlPressed) {
    // Ctrl+Click: toggle in multi-select
    ref.read(multiSelectedNodeIdsProvider.notifier).toggle(nodeId);
  } else if (isShiftPressed) {
    // Shift+Click: range select
    ref.read(multiSelectedNodeIdsProvider.notifier).rangeSelect(nodeId);
  } else {
    // Plain click: single select, clear multi-select
    ref.read(multiSelectedNodeIdsProvider.notifier).clear();
    ref.read(selectedNodeIdProvider.notifier).state = nodeId;
  }
}

class SequenceTree extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;
  final void Function(String nodeId)? onNodeTap;

  const SequenceTree({
    super.key,
    required this.colors,
    this.isMobile = false,
    this.onNodeTap,
  });

  @override
  ConsumerState<SequenceTree> createState() => _SequenceTreeState();
}

class _SequenceTreeState extends ConsumerState<SequenceTree> {
  final ScrollController _scrollController = ScrollController();
  String? _lastScrolledToNodeId;
  bool _userScrolledManually = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onManualScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onManualScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onManualScroll() {
    // If the user scrolls manually, temporarily suppress auto-scroll
    // until the current node changes again
    if (_scrollController.position.isScrollingNotifier.value) {
      _userScrolledManually = true;
    }
  }

  void _scrollToCurrentNode(String? currentNodeId) {
    if (currentNodeId == null) return;
    if (!ref.read(followExecutionProvider)) return;

    // Don't re-scroll to the same node unless user scrolled away
    if (currentNodeId == _lastScrolledToNodeId && !_userScrolledManually) {
      return;
    }

    final key = _nodeKeyRegistry[currentNodeId];
    if (key == null || key.currentContext == null) return;

    _userScrolledManually = false;
    _lastScrolledToNodeId = currentNodeId;

    Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.3, // show node ~30% from the top
    );
  }

  @override
  Widget build(BuildContext context) {
    final sequence = ref.watch(currentSequenceProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final validation = ref.watch(liveValidationProvider);

    // Auto-scroll whenever the executing node changes
    final followExecution = ref.watch(followExecutionProvider);
    if (followExecution && progress.currentNodeId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToCurrentNode(progress.currentNodeId);
        }
      });
    }

    // Reset manual-scroll flag when the current node changes
    ref.listen(sequenceProgressProvider.select((p) => p.currentNodeId),
        (prev, next) {
      if (prev != next) {
        _userScrolledManually = false;
      }
    });

    if (sequence == null) {
      return _EmptyState(colors: widget.colors);
    }

    final rootNode = sequence.rootNode;
    if (rootNode == null) {
      return _EmptyState(colors: widget.colors);
    }

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is NodePaletteItem || details.data is TemplateSnippet,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is NodePaletteItem) {
          final node = data.createNode();
          final notifier = ref.read(currentSequenceProvider.notifier);
          notifier.addNode(node);
          final children = data.createChildren?.call();
          if (children != null) {
            for (final child in children) {
              notifier.addNode(child, parentId: node.id);
            }
          }
          ref.read(selectedNodeIdProvider.notifier).state = node.id;
        } else if (data is TemplateSnippet) {
          final profile = ref.read(activeEquipmentProfileProvider);
          ref.read(currentSequenceProvider.notifier).insertSnippet(
                data,
                profileFilterNames: profile?.filterNames,
              );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isAccepting = candidateData.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: widget.colors.background,
            border: isAccepting
                ? Border.all(color: widget.colors.primary, width: 2)
                : null,
          ),
          child: Column(
            children: [
              // Sequence header with validation counts
              _SequenceHeader(
                colors: widget.colors,
                sequence: sequence,
                validation: validation,
              ),

              // Tree view
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.all(widget.isMobile ? 12 : 20),
                  child: _NodeTreeView(
                    colors: widget.colors,
                    sequence: sequence,
                    nodeId: rootNode.id,
                    progress: progress,
                    validation: validation,
                    depth: 0,
                    isMobile: widget.isMobile,
                    onNodeTap: widget.onNodeTap,
                  ),
                ),
              ),

              // Visual timeline (toggled via timelineVisibleProvider)
              Consumer(
                builder: (context, ref, child) {
                  final showTimeline = ref.watch(timelineVisibleProvider);
                  if (!showTimeline || widget.isMobile) {
                    return const SizedBox.shrink();
                  }
                  return VisualTimeline(colors: widget.colors);
                },
              ),

              // Mini-map (toggled via minimapVisibleProvider)
              Consumer(
                builder: (context, ref, child) {
                  final showMinimap = ref.watch(minimapVisibleProvider);
                  if (!showMinimap || widget.isMobile) {
                    return const SizedBox.shrink();
                  }
                  return SequenceMinimap(
                    colors: widget.colors,
                    scrollController: _scrollController,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SequenceHeader extends ConsumerWidget {
  final NightshadeColors colors;
  final Sequence sequence;
  final LiveValidationState validation;

  const _SequenceHeader({
    required this.colors,
    required this.sequence,
    required this.validation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = Responsive.isMobile(context);
    final padding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    final iconSize = isMobile ? 14.0 : 16.0;
    final titleFontSize = isMobile ? 13.0 : 14.0;
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isRunning = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused;
    final followExecution = ref.watch(followExecutionProvider);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Hide secondary info on narrow widths
          final showTargetCount = constraints.maxWidth > 280;
          final showNodeCount = constraints.maxWidth > 380;
          final showValidation = constraints.maxWidth > 320;

          return Row(
            children: [
              Icon(
                LucideIcons.workflow,
                size: iconSize,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () {
                    _showRenameDialog(context, ref);
                  },
                  child: Text(
                    sequence.name,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),

              // Validation issue badges
              if (showValidation && validation.totalCount > 0) ...[
                const SizedBox(width: 8),
                _ValidationBadges(
                  colors: colors,
                  errorCount: validation.errorCount,
                  warningCount: validation.warningCount,
                  infoCount: validation.infoCount,
                ),
              ],

              // Follow execution toggle (only shown when running)
              if (isRunning && !isMobile) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: followExecution
                      ? 'Auto-scroll ON (click to disable)'
                      : 'Auto-scroll OFF (click to enable)',
                  child: GestureDetector(
                    onTap: () {
                      ref.read(followExecutionProvider.notifier).state =
                          !followExecution;
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: followExecution
                            ? colors.info.withValues(alpha: 0.15)
                            : colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: followExecution
                              ? colors.info.withValues(alpha: 0.4)
                              : colors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            followExecution
                                ? LucideIcons.locateFixed
                                : LucideIcons.locate,
                            size: 12,
                            color: followExecution
                                ? colors.info
                                : colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Follow',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: followExecution
                                  ? colors.info
                                  : colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              if (showTargetCount) ...[
                const SizedBox(width: 8),
                Text(
                  '${sequence.targetHeaders.length} targets',
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: colors.textMuted,
                  ),
                ),
              ],
              if (showNodeCount) ...[
                const SizedBox(width: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.boxes,
                        size: 12,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${sequence.nodes.length} nodes',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Timeline toggle
              if (!isMobile) ...[
                const SizedBox(width: 8),
                _TimelineToggle(colors: colors),
              ],

              // Mini-map toggle
              if (!isMobile) ...[
                const SizedBox(width: 8),
                _MinimapToggle(colors: colors),
              ],

              // Color legend button
              if (!isMobile) ...[
                const SizedBox(width: 8),
                _NodeColorLegend(colors: colors),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: sequence.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Rename Sequence',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Sequence name',
            hintStyle: TextStyle(color: colors.textMuted),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              ref
                  .read(currentSequenceProvider.notifier)
                  .setName(controller.text);
              Navigator.pop(context);
            },
            label: 'Rename',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}

class _NodeTreeView extends ConsumerWidget {
  final NightshadeColors colors;
  final Sequence sequence;
  final String nodeId;
  final SequenceProgress progress;
  final LiveValidationState validation;
  final int depth;
  final bool isMobile;
  final void Function(String nodeId)? onNodeTap;

  const _NodeTreeView({
    required this.colors,
    required this.sequence,
    required this.nodeId,
    required this.progress,
    required this.validation,
    required this.depth,
    this.isMobile = false,
    this.onNodeTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = sequence.nodes[nodeId];
    if (node == null) return const SizedBox.shrink();

    // Register a GlobalKey for auto-scroll
    final scrollKey = _nodeKeyRegistry.putIfAbsent(nodeId, () => GlobalKey());

    // Watch only whether THIS node is selected, not the entire selectedNodeId.
    // This means only the old and new selected nodes rebuild on selection change,
    // rather than the entire tree.
    final isSelected = ref.watch(
      selectedNodeIdProvider.select((selectedId) => selectedId == nodeId),
    );
    final isMultiSelected = ref.watch(
      multiSelectedNodeIdsProvider.select((ids) => ids.contains(nodeId)),
    );
    final nodeStatus = progress.nodeStatuses[nodeId];
    final nodeValidationSeverity = validation.worstSeverityForNode(nodeId);

    final children = sequence.getChildren(nodeId);
    final hasChildren = children.isNotEmpty;
    final siblingCount =
        node.parentId != null ? sequence.getChildren(node.parentId!).length : 0;
    final canMoveUp = node.parentId != null && node.orderIndex > 0;
    final canMoveDown =
        node.parentId != null && node.orderIndex < siblingCount - 1;

    // Check if node can have children (is a container)
    final isContainer = node is TargetHeaderNode ||
        node is LoopNode ||
        node is InstructionSetNode ||
        node is ParallelNode ||
        node is ConditionalNode ||
        node is RecoveryNode;

    // Use TargetHeaderCard for TargetHeaderNode, otherwise use _NodeItem
    final targetHeaderNode = node is TargetHeaderNode ? node : null;

    // Determine tutorial key based on node type and depth
    GlobalKey? tutorialKey;
    if (depth == 1) {
      // Only apply keys to first-level nodes
      if (targetHeaderNode != null) {
        tutorialKey = SequencerTutorialKeys.targetNode;
      } else if (node is ExposureNode) {
        tutorialKey = SequencerTutorialKeys.captureNode;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node item - wrapped with scroll key for auto-scroll
        KeyedSubtree(
          key: scrollKey,
          child: _NodeValidationWrapper(
            colors: colors,
            validationSeverity: nodeValidationSeverity,
            validationIssues: validation.issuesByNodeId[nodeId],
            child: targetHeaderNode != null
                ? TargetHeaderCard(
                    key: tutorialKey,
                    node: targetHeaderNode,
                    colors: colors,
                    isSelected: isSelected || isMultiSelected,
                    nodeStatus: nodeStatus,
                    isMobile: isMobile,
                    onSelect: () {
                      _handleNodeSelect(ref, nodeId);
                      onNodeTap?.call(nodeId);
                    },
                    onToggleEnabled: () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .toggleNodeEnabled(nodeId);
                    },
                    onDelete: () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .removeNode(nodeId);
                      if (isSelected) {
                        ref.read(selectedNodeIdProvider.notifier).state = null;
                      }
                    },
                  )
                : _NodeItem(
                    key: tutorialKey,
                    colors: colors,
                    node: node,
                    isSelected: isSelected || isMultiSelected,
                    nodeStatus: nodeStatus,
                    hasChildren: hasChildren,
                    depth: depth,
                    progressPercent: progress.nodeProgressPercent[nodeId],
                    progressDetail: progress.nodeProgressDetail[nodeId],
                    isMobile: isMobile,
                    onSelect: () {
                      _handleNodeSelect(ref, nodeId);
                      onNodeTap?.call(nodeId);
                    },
                    onToggleEnabled: () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .toggleNodeEnabled(nodeId);
                    },
                    onDelete: () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .removeNode(nodeId);
                      if (isSelected) {
                        ref.read(selectedNodeIdProvider.notifier).state = null;
                      }
                    },
                    onDuplicate: () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .duplicateNode(nodeId);
                    },
                    onMoveUp: canMoveUp
                        ? () {
                            ref.read(currentSequenceProvider.notifier).moveNode(
                                  nodeId,
                                  node.parentId!,
                                  node.orderIndex - 1,
                                );
                          }
                        : null,
                    onMoveDown: canMoveDown
                        ? () {
                            ref.read(currentSequenceProvider.notifier).moveNode(
                                  nodeId,
                                  node.parentId!,
                                  node.orderIndex + 1,
                                );
                          }
                        : null,
                  ),
          ),
        ),

        // Children area
        if (hasChildren || isContainer)
          Padding(
            padding: EdgeInsets.only(left: isMobile ? 16 : 24),
            child: DragTarget<Object>(
              onWillAcceptWithDetails: (data) =>
                  data is String ||
                  data is NodePaletteItem ||
                  data is TemplateSnippet,
              onAcceptWithDetails: (details) {
                final data = details.data;
                if (data is String) {
                  ref.read(currentSequenceProvider.notifier).moveNode(
                        data,
                        nodeId,
                        children.length,
                      );
                } else if (data is NodePaletteItem) {
                  final newNode = data.createNode();
                  final notifier = ref.read(currentSequenceProvider.notifier);
                  notifier.addNode(
                    newNode,
                    parentId: nodeId,
                    // No index = append
                  );
                  final children = data.createChildren?.call();
                  if (children != null) {
                    for (final child in children) {
                      notifier.addNode(child, parentId: newNode.id);
                    }
                  }
                  ref.read(selectedNodeIdProvider.notifier).state = newNode.id;
                } else if (data is TemplateSnippet) {
                  final profile = ref.read(activeEquipmentProfileProvider);
                  ref.read(currentSequenceProvider.notifier).insertSnippet(
                        data,
                        parentId: nodeId,
                        profileFilterNames: profile?.filterNames,
                      );
                }
              },
              builder: (context, candidateData, rejectedData) {
                final isContainerHovered = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: isContainerHovered
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          color: colors.primary.withValues(alpha: 0.04),
                        )
                      : const BoxDecoration(),
                  padding: isContainerHovered
                      ? const EdgeInsets.all(4)
                      : EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < children.length; i++) ...[
                        if (!isMobile)
                          _DropZone(
                            colors: colors,
                            parentId: nodeId,
                            index: i,
                            isActive: candidateData.isNotEmpty,
                          ),
                        if (isMobile)
                          // On mobile, use simpler rendering without drag
                          _NodeTreeView(
                            colors: colors,
                            sequence: sequence,
                            nodeId: children[i].id,
                            progress: progress,
                            validation: validation,
                            depth: depth + 1,
                            isMobile: isMobile,
                            onNodeTap: onNodeTap,
                          )
                        else
                          LongPressDraggable<String>(
                            data: children[i].id,
                            delay: const Duration(milliseconds: 150),
                            onDragStarted: () {
                              ref.read(isDraggingNodeProvider.notifier).state =
                                  true;
                            },
                            onDragEnd: (_) {
                              ref.read(isDraggingNodeProvider.notifier).state =
                                  false;
                            },
                            onDraggableCanceled: (_, __) {
                              ref.read(isDraggingNodeProvider.notifier).state =
                                  false;
                            },
                            feedback: Material(
                              color: Colors.transparent,
                              child: Opacity(
                                opacity: 0.8,
                                child: SizedBox(
                                  width: children[i] is TargetHeaderNode
                                      ? 400
                                      : 300,
                                  child: children[i] is TargetHeaderNode
                                      ? TargetHeaderCard(
                                          node: children[i] as TargetHeaderNode,
                                          colors: colors,
                                          isSelected: false,
                                          nodeStatus: null,
                                        )
                                      : _NodeItem(
                                          colors: colors,
                                          node: children[i],
                                          isSelected: false,
                                          nodeStatus: null,
                                          hasChildren: false,
                                          depth: depth + 1,
                                          isDragging: true,
                                        ),
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: _NodeTreeView(
                                colors: colors,
                                sequence: sequence,
                                nodeId: children[i].id,
                                progress: progress,
                                validation: validation,
                                depth: depth + 1,
                              ),
                            ),
                            child: _NodeTreeView(
                              colors: colors,
                              sequence: sequence,
                              nodeId: children[i].id,
                              progress: progress,
                              validation: validation,
                              depth: depth + 1,
                            ),
                          ),
                      ],
                      // Always show a drop zone at the end on desktop, even if empty
                      if (!isMobile)
                        _DropZone(
                          colors: colors,
                          parentId: nodeId,
                          index: children.length,
                          isActive: candidateData.isNotEmpty,
                        ),

                      // If empty, show a hint
                      if (!hasChildren && isContainer)
                        Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: isMobile ? 12 : 8),
                          child: Text(
                            isMobile
                                ? 'Tap + to add instructions'
                                : 'Drop instructions here',
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 11,
                              color: colors.textMuted.withValues(alpha: 0.5),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

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
    this.isMobile = false,
  });

  @override
  ConsumerState<_NodeItem> createState() => _NodeItemState();
}

class _NodeItemState extends ConsumerState<_NodeItem>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;

  // For progress panel persistence
  bool _showProgressPanel = false;
  DateTime? _lastRunningTime;
  Timer? _panelPersistTimer;
  static const _panelPersistDuration = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.nodeStatus == NodeStatus.running) {
      _pulseController.repeat();
      _showProgressPanel = true;
      _lastRunningTime = DateTime.now();
    }
  }

  @override
  void didUpdateWidget(_NodeItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nodeStatus == NodeStatus.running) {
      _pulseController.repeat();
      _showProgressPanel = true;
      _lastRunningTime = DateTime.now();
    } else {
      _pulseController.stop();
      _pulseController.reset();

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
    _pulseController.dispose();
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
            borderRadius: BorderRadius.circular(8),
          ),
          title: Row(
            children: [
              Icon(LucideIcons.bookmark,
                  size: 20, color: widget.colors.primary),
              const SizedBox(width: 12),
              Text(
                'Save as Template',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Name',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style:
                      TextStyle(fontSize: 14, color: widget.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Template name',
                    hintStyle:
                        TextStyle(fontSize: 14, color: widget.colors.textMuted),
                    filled: true,
                    fillColor: widget.colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Description',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  style:
                      TextStyle(fontSize: 14, color: widget.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'What does this template do?',
                    hintStyle:
                        TextStyle(fontSize: 14, color: widget.colors.textMuted),
                    filled: true,
                    fillColor: widget.colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.colors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Category',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: widget.colors.textSecondary)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SnippetCategory>(
                      value: selectedCategory,
                      isExpanded: true,
                      dropdownColor: widget.colors.surfaceOverlay,
                      style: TextStyle(
                          fontSize: 14, color: widget.colors.textPrimary),
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

  String _getSubtitle() {
    if (widget.node is ExposureNode) {
      final exp = widget.node as ExposureNode;
      return '${exp.count}x ${exp.durationSecs}s${exp.filter != null ? ' (${exp.filter})' : ''}';
    }
    if (widget.node is TargetHeaderNode) {
      final target = widget.node as TargetHeaderNode;
      return target.displayName;
    }
    if (widget.node is LoopNode) {
      final loop = widget.node as LoopNode;
      return '${loop.repeatCount ?? '∞'} iterations';
    }
    if (widget.node is AutofocusNode) {
      final af = widget.node as AutofocusNode;
      return '${af.method.name} method';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor();
    final statusColor = _getStatusColor();
    final subtitle = _getSubtitle();
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
    final subtitleFontSize = isMobile ? 12.0 : 10.0;

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
            value: subtitle.isNotEmpty ? subtitle : null,
            hint:
                'Select node. More actions include reorder and wrap commands.',
            child: GestureDetector(
              onTap: widget.onSelect,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.symmetric(vertical: verticalMargin),
                    padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding),
                    decoration: BoxDecoration(
                      color: widget.isDragging
                          ? categoryColor.withValues(alpha: 0.2)
                          : widget.isSelected
                              ? categoryColor.withValues(alpha: 0.15)
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
                                ? Color.lerp(
                                    widget.colors.info.withValues(alpha: 0.3),
                                    widget.colors.info,
                                    _pulseController.value,
                                  )!
                                : isTargetHeader
                                    ? categoryColor.withValues(
                                        alpha:
                                            0.3) // Stronger border for target headers
                                    : widget.colors.border,
                        width: widget.isSelected || isTargetHeader
                            ? 2
                            : 1, // Thicker border for target headers
                      ),
                      boxShadow: widget.isDragging
                          ? [
                              BoxShadow(
                                color: categoryColor.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
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
                              margin:
                                  EdgeInsets.only(right: isMobile ? 12 : 10),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),

                          // Icon
                          Container(
                            width: iconBoxSize,
                            height: iconBoxSize,
                            decoration: BoxDecoration(
                              color: categoryColor.withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(isMobile ? 10 : 8),
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
                                Text(
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
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: subtitleFontSize,
                                      color: widget.colors.textMuted,
                                    ),
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                // Show node comment as gray italic text
                                if (widget.node.comment != null &&
                                    widget.node.comment!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      widget.node.comment!,
                                      style: TextStyle(
                                        fontSize: subtitleFontSize,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.progressDetail != null &&
                                            widget.progressDetail!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 2),
                                            child: Text(
                                              widget.progressDetail!,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: widget.colors.info,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(2),
                                          child: LinearProgressIndicator(
                                            value:
                                                widget.progressPercent! / 100.0,
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
                          if ((isMobile || _isHovered) &&
                              !widget.isDragging) ...[
                            _NodeActionButton(
                              icon: widget.node.isEnabled
                                  ? LucideIcons.eye
                                  : LucideIcons.eyeOff,
                              tooltip:
                                  widget.node.isEnabled ? 'Disable' : 'Enable',
                              colors: widget.colors,
                              onPressed: widget.onToggleEnabled,
                            ),
                            _NodeActionButton(
                              icon: LucideIcons.copy,
                              tooltip: 'Duplicate',
                              colors: widget.colors,
                              onPressed: widget.onDuplicate,
                            ),
                            _NodeActionButton(
                              icon: LucideIcons.trash2,
                              tooltip: 'Delete',
                              colors: widget.colors,
                              color: widget.colors.error,
                              onPressed: widget.onDelete,
                            ),

                            // Wrap / More Actions Menu
                            Theme(
                              data: Theme.of(context).copyWith(
                                popupMenuTheme: PopupMenuThemeData(
                                  color: widget.colors.surfaceAlt,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side:
                                        BorderSide(color: widget.colors.border),
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
                                    const PopupMenuItem(
                                      value: 'move_up',
                                      height: 32,
                                      child: Text('Move Up',
                                          style: TextStyle(fontSize: 13)),
                                    ),
                                  if (widget.onMoveDown != null)
                                    const PopupMenuItem(
                                      value: 'move_down',
                                      height: 32,
                                      child: Text('Move Down',
                                          style: TextStyle(fontSize: 13)),
                                    ),
                                  if (widget.onMoveUp != null ||
                                      widget.onMoveDown != null)
                                    const PopupMenuDivider(height: 8),
                                  if (widget.hasChildren) ...[
                                    const PopupMenuItem(
                                      value: 'wrap_children_target',
                                      height: 32,
                                      child: Text(
                                          'Wrap Children in Target Header',
                                          style: TextStyle(fontSize: 13)),
                                    ),
                                    const PopupMenuItem(
                                      value: 'wrap_children_loop',
                                      height: 32,
                                      child: Text('Wrap Children in Loop',
                                          style: TextStyle(fontSize: 13)),
                                    ),
                                    const PopupMenuItem(
                                      value: 'wrap_children_set',
                                      height: 32,
                                      child: Text(
                                          'Wrap Children in Instruction Set',
                                          style: TextStyle(fontSize: 13)),
                                    ),
                                    const PopupMenuDivider(height: 8),
                                  ],
                                  const PopupMenuItem(
                                    value: 'wrap_loop',
                                    height: 32,
                                    child: Text('Wrap in Loop',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                  const PopupMenuItem(
                                    value: 'wrap_set',
                                    height: 32,
                                    child: Text('Wrap in Instruction Set',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                  const PopupMenuDivider(height: 8),
                                  const PopupMenuItem(
                                    value: 'save_snippet',
                                    height: 32,
                                    child: Text('Save as Template',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                ],
                                onSelected: (value) {
                                  final notifier = ref
                                      .read(currentSequenceProvider.notifier);
                                  switch (value) {
                                    case 'move_up':
                                      widget.onMoveUp?.call();
                                      break;
                                    case 'move_down':
                                      widget.onMoveDown?.call();
                                      break;
                                    case 'wrap_children_target':
                                      notifier.wrapChildren(
                                          widget.node.id,
                                          TargetHeaderNode(
                                              targetName: 'New Target',
                                              raHours: 0,
                                              decDegrees: 0));
                                      break;
                                    case 'wrap_children_loop':
                                      notifier.wrapChildren(
                                          widget.node.id, LoopNode());
                                      break;
                                    case 'wrap_children_set':
                                      notifier.wrapChildren(
                                          widget.node.id, InstructionSetNode());
                                      break;
                                    case 'wrap_loop':
                                      notifier.wrapNode(
                                          widget.node.id, LoopNode());
                                      break;
                                    case 'wrap_set':
                                      notifier.wrapNode(
                                          widget.node.id, InstructionSetNode());
                                      break;
                                    case 'save_snippet':
                                      _showSaveAsSnippetDialog(
                                          context, ref, widget.node);
                                      break;
                                  }
                                },
                              ),
                            ),
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
                  );
                },
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
              ) ??
              const SizedBox.shrink(),
      ],
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _SpinningIcon({
    required this.icon,
    required this.color,
    this.size = 16,
  });

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Icon(
            widget.icon,
            size: widget.size,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _NodeActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final Color? color;
  final VoidCallback? onPressed;

  const _NodeActionButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.color,
    this.onPressed,
  });

  @override
  State<_NodeActionButton> createState() => _NodeActionButtonState();
}

class _NodeActionButtonState extends State<_NodeActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? widget.colors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? color.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 12,
              color: _isHovered ? color : widget.colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _DropZone extends ConsumerWidget {
  final NightshadeColors colors;
  final String parentId;
  final int index;
  final bool isActive; // kept for backwards compat but we use global provider

  const _DropZone({
    required this.colors,
    required this.parentId,
    required this.index,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch global drag state for all drop zones to react together
    final isDragging = ref.watch(isDraggingNodeProvider);

    return DragTarget<Object>(
      onWillAcceptWithDetails: (data) =>
          data.data is String ||
          data.data is NodePaletteItem ||
          data.data is TemplateSnippet,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is String) {
          ref.read(currentSequenceProvider.notifier).moveNode(
                data,
                parentId,
                index,
              );
        } else if (data is NodePaletteItem) {
          final node = data.createNode();
          final notifier = ref.read(currentSequenceProvider.notifier);
          notifier.addNode(
            node,
            parentId: parentId,
            index: index,
          );
          final children = data.createChildren?.call();
          if (children != null) {
            for (final child in children) {
              notifier.addNode(child, parentId: node.id);
            }
          }
          ref.read(selectedNodeIdProvider.notifier).state = node.id;
        } else if (data is TemplateSnippet) {
          final profile = ref.read(activeEquipmentProfileProvider);
          ref.read(currentSequenceProvider.notifier).insertSnippet(
                data,
                parentId: parentId,
                index: index,
                profileFilterNames: profile?.filterNames,
              );
        }
        // Reset drag state after drop
        ref.read(isDraggingNodeProvider.notifier).state = false;
      },
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        // Show larger drop zone when any drag is active globally
        final showDropZone = isDragging || isActive || isOver;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: isOver ? 48 : (showDropZone ? 28 : 4),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: isOver
              ? BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.primary, width: 2),
                )
              : showDropZone
                  ? _dashedDropDecoration(colors)
                  : const BoxDecoration(),
          child: isOver
              ? Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.arrowDown,
                        size: 12,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Insert here',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : showDropZone
                  ? CustomPaint(
                      painter: _DashedLinePainter(
                          color: colors.primary.withValues(alpha: 0.5)),
                      child: Center(
                        child: Icon(
                          Icons.add_circle_outline,
                          size: 12,
                          color: colors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : null,
        );
      },
    );
  }
}

/// Creates a dashed-border-style decoration for drop zone indicators.
BoxDecoration _dashedDropDecoration(NightshadeColors colors) {
  return BoxDecoration(
    color: colors.primary.withValues(alpha: 0.06),
    borderRadius: BorderRadius.circular(6),
  );
}

/// Paints a horizontal dashed line across the center of the widget,
/// acting as an insertion point indicator during drag operations.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final y = size.height / 2;

    // Draw left dashes (up to center minus icon space)
    final leftEnd = size.width / 2 - 12;
    var x = 4.0;
    while (x < leftEnd) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dashWidth).clamp(0, leftEnd), y),
        paint,
      );
      x += dashWidth + dashSpace;
    }

    // Draw right dashes (from center plus icon space)
    final rightStart = size.width / 2 + 12;
    x = rightStart;
    while (x < size.width - 4) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dashWidth).clamp(0, size.width - 4), y),
        paint,
      );
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Collapsible legend showing node category colors.
/// Shown as a "?" icon that opens a popup overlay.
class _NodeColorLegend extends StatelessWidget {
  final NightshadeColors colors;

  const _NodeColorLegend({required this.colors});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Node color legend',
      offset: const Offset(0, 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border),
      ),
      color: colors.surface,
      icon: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.border),
        ),
        child: Icon(
          LucideIcons.helpCircle,
          size: 12,
          color: colors.textMuted,
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Node Colors',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _legendRow(colors.warning, 'Target / Trigger'),
              const SizedBox(height: 6),
              _legendRow(colors.primary, 'Imaging (Expose, Filter, Dither)'),
              const SizedBox(height: 6),
              _legendRow(colors.primary, 'Mount (Slew, Center, Park)'),
              const SizedBox(height: 6),
              _legendRow(colors.accent, 'Logic (Loop, Parallel, Conditional)'),
              const SizedBox(height: 6),
              _legendRow(colors.accent, 'Focus / Recovery'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final iconSize = isMobile ? 36.0 : 48.0;
    final titleSize = isMobile ? 16.0 : 18.0;
    final subtitleSize = isMobile ? 12.0 : 13.0;
    final tipSize = isMobile ? 11.0 : 12.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 18 : 24),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
              ),
              child: Icon(
                LucideIcons.workflow,
                size: iconSize,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Build Your Sequence',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            const SizedBox(height: 8),
            Text(
              isMobile
                  ? 'Tap + to add nodes'
                  : 'Drag nodes from the palette to start building',
              style: TextStyle(
                fontSize: subtitleSize,
                color: colors.textMuted,
              ),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            const SizedBox(height: 24),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.lightbulb,
                    size: isMobile ? 12 : 14,
                    color: colors.warning,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Tip: Start with a Target Header',
                      style: TextStyle(
                        fontSize: tipSize,
                        color: colors.textSecondary,
                      ),
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a node widget with a validation badge overlay.
/// Shows a small warning/error indicator in the top-right corner when the node
/// has validation issues.
class _NodeValidationWrapper extends StatelessWidget {
  final NightshadeColors colors;
  final LiveValidationSeverity? validationSeverity;
  final List<LiveValidationIssue>? validationIssues;
  final Widget child;

  const _NodeValidationWrapper({
    required this.colors,
    required this.validationSeverity,
    required this.validationIssues,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (validationSeverity == null ||
        validationIssues == null ||
        validationIssues!.isEmpty) {
      return child;
    }

    final Color badgeColor;
    final IconData badgeIcon;
    switch (validationSeverity!) {
      case LiveValidationSeverity.error:
        badgeColor = colors.error;
        badgeIcon = LucideIcons.xCircle;
        break;
      case LiveValidationSeverity.warning:
        badgeColor = colors.warning;
        badgeIcon = LucideIcons.alertTriangle;
        break;
      case LiveValidationSeverity.info:
        badgeColor = colors.info;
        badgeIcon = LucideIcons.info;
        break;
    }

    final badgeForeground =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: Tooltip(
            richMessage: TextSpan(
              children: [
                for (int i = 0; i < validationIssues!.length; i++) ...[
                  if (i > 0) const TextSpan(text: '\n'),
                  TextSpan(
                    text: validationIssues![i].title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: ': ${validationIssues![i].description}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ],
            ),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Center(
                child: validationIssues!.length > 1
                    ? Text(
                        '${validationIssues!.length}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: badgeForeground,
                        ),
                      )
                    : Icon(
                        badgeIcon,
                        size: 10,
                        color: badgeForeground,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact validation summary badges for the sequence header toolbar.
class _ValidationBadges extends StatelessWidget {
  final NightshadeColors colors;
  final int errorCount;
  final int warningCount;
  final int infoCount;

  const _ValidationBadges({
    required this.colors,
    required this.errorCount,
    required this.warningCount,
    required this.infoCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorCount > 0)
          _MiniCountBadge(
            count: errorCount,
            color: colors.error,
            icon: LucideIcons.xCircle,
          ),
        if (warningCount > 0) ...[
          if (errorCount > 0) const SizedBox(width: 4),
          _MiniCountBadge(
            count: warningCount,
            color: colors.warning,
            icon: LucideIcons.alertTriangle,
          ),
        ],
        if (infoCount > 0) ...[
          if (errorCount > 0 || warningCount > 0) const SizedBox(width: 4),
          _MiniCountBadge(
            count: infoCount,
            color: colors.info,
            icon: LucideIcons.info,
          ),
        ],
      ],
    );
  }
}

class _MiniCountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final IconData icon;

  const _MiniCountBadge({
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MinimapToggle extends ConsumerWidget {
  final NightshadeColors colors;

  const _MinimapToggle({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(minimapVisibleProvider);

    return Tooltip(
      message: isVisible ? 'Hide mini-map' : 'Show mini-map',
      child: GestureDetector(
        onTap: () {
          ref.read(minimapVisibleProvider.notifier).state = !isVisible;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isVisible
                ? colors.primary.withValues(alpha: 0.15)
                : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isVisible
                  ? colors.primary.withValues(alpha: 0.4)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.map,
                size: 12,
                color: isVisible ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Map',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isVisible ? colors.primary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineToggle extends ConsumerWidget {
  final NightshadeColors colors;

  const _TimelineToggle({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(timelineVisibleProvider);

    return Tooltip(
      message: isVisible ? 'Hide timeline' : 'Show timeline',
      child: GestureDetector(
        onTap: () {
          ref.read(timelineVisibleProvider.notifier).state = !isVisible;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isVisible
                ? colors.primary.withValues(alpha: 0.15)
                : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isVisible
                  ? colors.primary.withValues(alpha: 0.4)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.ganttChart,
                size: 12,
                color: isVisible ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Timeline',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isVisible ? colors.primary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

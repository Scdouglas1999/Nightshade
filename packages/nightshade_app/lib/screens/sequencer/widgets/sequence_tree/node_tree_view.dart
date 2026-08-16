part of '../sequence_tree.dart';

class _NodeTreeView extends ConsumerWidget {
  final NightshadeColors colors;
  final Sequence sequence;
  final String nodeId;
  final SequenceProgress progress;
  final LiveValidationState validation;
  final int depth;
  final bool isMobile;
  final void Function(String nodeId)? onNodeTap;

  /// Lifecycle-scoped key registry handed down from [_SequenceTreeState].
  /// Treat as read-write: this view inserts new keys for nodes it draws,
  /// and the state-level pruner removes keys for nodes that disappear.
  final Map<String, GlobalKey> keyRegistry;

  const _NodeTreeView({
    required this.colors,
    required this.sequence,
    required this.nodeId,
    required this.progress,
    required this.validation,
    required this.depth,
    required this.keyRegistry,
    this.isMobile = false,
    this.onNodeTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = sequence.nodes[nodeId];
    if (node == null) return const SizedBox.shrink();

    // Register a GlobalKey for auto-scroll
    final scrollKey = keyRegistry.putIfAbsent(nodeId, () => GlobalKey());

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

    // Determine tutorial key based on node type and depth. The anchors are
    // static GlobalKeys, so only the FIRST depth-1 node of each type may
    // carry one: handing the key to every sibling of that type makes Flutter
    // steal the element from the first holder, and in a release build the
    // second card silently vanishes from the tree (live: waveH-final
    // 38-two-siblings.png, two sibling Take Exposures rendered one card).
    GlobalKey? tutorialKey;
    if (depth == 1 && node.parentId != null) {
      final siblings = sequence.getChildren(node.parentId!);
      if (targetHeaderNode != null) {
        final anchor = siblings.where((n) => n is TargetHeaderNode).firstOrNull;
        if (anchor?.id == nodeId) {
          tutorialKey = SequencerTutorialKeys.targetNode;
        }
      } else if (node is ExposureNode) {
        final anchor = siblings.where((n) => n is ExposureNode).firstOrNull;
        if (anchor?.id == nodeId) {
          tutorialKey = SequencerTutorialKeys.captureNode;
        }
      }
    }

    // Per-node "is collapsed in the tree" state for Left-arrow / Right-
    // arrow keyboard nav. Watched here so a collapse toggle rebuilds the
    // children-area below (without re-rendering siblings).
    final isCollapsed = ref.watch(
      collapsedNodeIdsProvider.select((s) => s.contains(nodeId)),
    );

    // Shared "append into this container" accept logic, used by both the
    // expanded children DragTarget and the collapsed-header DragTarget so a
    // collapsed container is still a valid drop destination (the dropped
    // node appends at the end of its hidden children).
    void acceptIntoContainer(Object data) {
      if (data is String) {
        ref.read(currentSequenceProvider.notifier).moveNode(
              data,
              nodeId,
              children.length,
            );
      } else if (data is NodePaletteItem) {
        final newNode = data.createNode();
        final notifier = ref.read(currentSequenceProvider.notifier);
        notifier.addNode(newNode, parentId: nodeId);
        final created = data.createChildren?.call();
        if (created != null) {
          for (final child in created) {
            notifier.addNode(child, parentId: newNode.id);
          }
        }
        ref.read(selectedNodeIdProvider.notifier).state = newNode.id;
      } else if (data is TemplateSnippet) {
        insertSnippetGuarded(context, ref, data, parentId: nodeId);
      } else if (data is TargetQueueDragPayload) {
        final notifier = ref.read(currentSequenceProvider.notifier);
        notifier.addNode(data.node, parentId: nodeId);
        ref.read(selectedNodeIdProvider.notifier).state = data.node.id;
      }
    }

    // The header row. When the container is collapsed its children DragTarget
    // is not rendered, so wrap the header itself in a DragTarget (desktop
    // only — mobile has no drag) so drops still land inside it.
    //
    // `baseRow` is `final` on purpose. The collapsed-container wrapper below
    // builds its child from a CLOSURE, and a closure captures the VARIABLE,
    // not the value it held when the closure was written. Reassigning
    // `headerRow` to the DragTarget and then reading `headerRow` inside that
    // DragTarget's builder made the row its own descendant: every build
    // nested another DragTarget → AnimatedContainer → DragTarget … until the
    // element tree blows the stack (~30k frames). In a release build a
    // subtree that throws is replaced by ErrorWidget, which paints a bare grey
    // rectangle over the rest of the tree. Only collapsed containers take that
    // branch, so it shows on Collapse-all and vanishes on Expand-all.
    final Widget baseRow = SequenceTreeContextMenu(
      nodeId: nodeId,
      colors: colors,
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
                  // Why: target headers usually own a non-trivial
                  // subtree; route through the confirm helper so a
                  // misclick can't nuke a fully-authored target.
                  confirmAndDeleteSequenceNode(
                    context: context,
                    ref: ref,
                    nodeId: nodeId,
                  );
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
                isCollapsed: isCollapsed,
                progressPercent: progress.nodeProgressPercent[nodeId],
                progressDetail: progress.nodeProgressDetail[nodeId],
                structuredProgressDetail:
                    progress.nodeProgressStructuredDetail[nodeId],
                // The filter the run is actually imaging through — see
                // [_NodeItem.runFilter].
                runFilter: progress.currentFilter,
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
                  // Why: a node may be a container (Loop, Parallel,
                  // InstructionSet) holding many children; the helper
                  // gates with "Delete N nodes?" when descendants > 0.
                  confirmAndDeleteSequenceNode(
                    context: context,
                    ref: ref,
                    nodeId: nodeId,
                  );
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
    );

    // A collapsed container hides its children DragTarget, so wrap the
    // header in a DragTarget that appends into the container. Desktop only —
    // the mobile branch has no drag affordance.
    Widget headerRow = baseRow;
    if (isCollapsed && isContainer && !isMobile) {
      headerRow = DragTarget<Object>(
        onWillAcceptWithDetails: (data) =>
            data.data is String ||
            data.data is NodePaletteItem ||
            data.data is TemplateSnippet ||
            data.data is TargetQueueDragPayload,
        onAcceptWithDetails: (details) => acceptIntoContainer(details.data),
        builder: (context, candidateData, rejectedData) {
          final isOver = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: isOver
                ? BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    color: colors.primary.withValues(alpha: 0.04),
                  )
                : const BoxDecoration(),
            child: baseRow,
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node item - wrapped with scroll key for auto-scroll. The
        // context menu lives on the outside of the validation wrapper so
        // its hit-test rect covers the whole row including the warning
        // badge.
        KeyedSubtree(
          key: scrollKey,
          child: headerRow,
        ),

        // Per-container duration rollup chip ("~2h 14m"). Shown for
        // container node types only — leaves already display their
        // own per-node detail. Lives below the row so a wide row name
        // doesn't get squeezed.
        if (isContainer)
          Padding(
            padding: EdgeInsets.only(left: isMobile ? 16 : 24, bottom: 2),
            child: Align(
              alignment: Alignment.centerRight,
              child: NodeDurationChip(
                nodeId: nodeId,
                colors: colors,
                compact: isMobile,
              ),
            ),
          ),

        // Inline strip of captured frames produced
        // by this ExposureNode. The strip lives directly under the
        // ExposureNode row so the user sees frames appear in real time
        // beneath the instruction that produced them. ThumbnailStrip
        // collapses silently when no frames exist for the node, when
        // the user has turned thumbnails off, or when prefs haven't
        // loaded yet — so adding it here doesn't bloat empty trees.
        if (node is ExposureNode)
          Padding(
            padding: EdgeInsets.only(left: isMobile ? 24 : 36, right: 8),
            child: ExposureNodeThumbnailStrip(nodeId: nodeId),
          ),

        // Children area
        if ((hasChildren || isContainer) && !isCollapsed)
          Padding(
            padding: EdgeInsets.only(left: isMobile ? 16 : 24),
            child: DragTarget<Object>(
              onWillAcceptWithDetails: (data) =>
                  data.data is String ||
                  data.data is NodePaletteItem ||
                  data.data is TemplateSnippet ||
                  data.data is TargetQueueDragPayload,
              onAcceptWithDetails: (details) {
                final data = details.data;
                if (data is TemplateSnippet) {
                  // Snippet inserts route through the guarded helper so a
                  // locked-state / unknown-node-type failure surfaces a
                  // snackbar instead of an uncaught throw.
                  insertSnippetGuarded(context, ref, data, parentId: nodeId);
                  return;
                }
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
                } else if (data is TargetQueueDragPayload) {
                  // Drop a queued target into a container — appends
                  // a fresh TargetHeaderNode at the end. Targets are
                  // top-level by convention, but the tree allows
                  // nesting under InstructionSet/RootContainer too.
                  final notifier = ref.read(currentSequenceProvider.notifier);
                  notifier.addNode(data.node, parentId: nodeId);
                  ref.read(selectedNodeIdProvider.notifier).state =
                      data.node.id;
                }
              },
              builder: (context, candidateData, rejectedData) {
                final isContainerHovered = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: isContainerHovered
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline8),
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
                            keyRegistry: keyRegistry,
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
                                keyRegistry: keyRegistry,
                              ),
                            ),
                            child: _NodeTreeView(
                              colors: colors,
                              sequence: sequence,
                              nodeId: children[i].id,
                              progress: progress,
                              validation: validation,
                              depth: depth + 1,
                              keyRegistry: keyRegistry,
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
                              fontSize: isMobile
                                  ? NightshadeTypography.fontSize12
                                  : NightshadeTypography.fontSize11,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/tutorial_keys/sequencer_keys.dart';
import 'node_progress_panels.dart';
import 'target_header_card.dart';

/// Provider to track when a node is being dragged globally
/// This allows all drop zones to become visible when any drag starts
final isDraggingNodeProvider = StateProvider<bool>((ref) => false);

class SequenceTree extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final progress = ref.watch(sequenceProgressProvider);

    if (sequence == null) {
      return _EmptyState(colors: colors);
    }

    final rootNode = sequence.rootNode;
    if (rootNode == null) {
      return _EmptyState(colors: colors);
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
            color: colors.background,
            border: isAccepting
                ? Border.all(color: colors.primary, width: 2)
                : null,
          ),
          child: Column(
            children: [
              // Sequence header
              _SequenceHeader(
                colors: colors,
                sequence: sequence,
              ),

              // Tree view
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 12 : 20),
                  child: _NodeTreeView(
                    colors: colors,
                    sequence: sequence,
                    nodeId: rootNode.id,
                    selectedNodeId: selectedNodeId,
                    progress: progress,
                    depth: 0,
                    isMobile: isMobile,
                    onNodeTap: onNodeTap,
                  ),
                ),
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

  const _SequenceHeader({
    required this.colors,
    required this.sequence,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = Responsive.isMobile(context);
    final padding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    final iconSize = isMobile ? 14.0 : 16.0;
    final titleFontSize = isMobile ? 13.0 : 14.0;

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
              if (showTargetCount) ...[
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              ref.read(currentSequenceProvider.notifier).setName(controller.text);
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
  final String? selectedNodeId;
  final SequenceProgress progress;
  final int depth;
  final bool isMobile;
  final void Function(String nodeId)? onNodeTap;

  const _NodeTreeView({
    required this.colors,
    required this.sequence,
    required this.nodeId,
    required this.selectedNodeId,
    required this.progress,
    required this.depth,
    this.isMobile = false,
    this.onNodeTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = sequence.nodes[nodeId];
    if (node == null) return const SizedBox.shrink();

    final isSelected = selectedNodeId == nodeId;
    final nodeStatus = progress.nodeStatuses[nodeId];

    final children = sequence.getChildren(nodeId);
    final hasChildren = children.isNotEmpty;
    
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
        // Node item - use rich card for target headers
        if (targetHeaderNode != null)
          TargetHeaderCard(
            key: tutorialKey,
            node: targetHeaderNode,
            colors: colors,
            isSelected: isSelected,
            nodeStatus: nodeStatus,
            isMobile: isMobile,
            onSelect: () {
              ref.read(selectedNodeIdProvider.notifier).state = nodeId;
              onNodeTap?.call(nodeId);
            },
            onToggleEnabled: () {
              ref.read(currentSequenceProvider.notifier).toggleNodeEnabled(nodeId);
            },
            onDelete: () {
              ref.read(currentSequenceProvider.notifier).removeNode(nodeId);
              if (isSelected) {
                ref.read(selectedNodeIdProvider.notifier).state = null;
              }
            },
          )
        else
          _NodeItem(
            key: tutorialKey,
            colors: colors,
            node: node,
            isSelected: isSelected,
            nodeStatus: nodeStatus,
            hasChildren: hasChildren,
            depth: depth,
            progressPercent: progress.nodeProgressPercent[nodeId],
            progressDetail: progress.nodeProgressDetail[nodeId],
            isMobile: isMobile,
            onSelect: () {
              ref.read(selectedNodeIdProvider.notifier).state = nodeId;
              onNodeTap?.call(nodeId);
            },
            onToggleEnabled: () {
              ref.read(currentSequenceProvider.notifier).toggleNodeEnabled(nodeId);
            },
            onDelete: () {
              ref.read(currentSequenceProvider.notifier).removeNode(nodeId);
              if (isSelected) {
                ref.read(selectedNodeIdProvider.notifier).state = null;
              }
            },
            onDuplicate: () {
              ref.read(currentSequenceProvider.notifier).duplicateNode(nodeId);
            },
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
                return Column(
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
                          selectedNodeId: selectedNodeId,
                          progress: progress,
                          depth: depth + 1,
                          isMobile: isMobile,
                          onNodeTap: onNodeTap,
                        )
                      else
                        LongPressDraggable<String>(
                          data: children[i].id,
                          delay: const Duration(milliseconds: 150),
                          onDragStarted: () {
                            ref.read(isDraggingNodeProvider.notifier).state = true;
                          },
                          onDragEnd: (_) {
                            ref.read(isDraggingNodeProvider.notifier).state = false;
                          },
                          onDraggableCanceled: (_, __) {
                            ref.read(isDraggingNodeProvider.notifier).state = false;
                          },
                          feedback: Material(
                            color: Colors.transparent,
                            child: Opacity(
                              opacity: 0.8,
                              child: SizedBox(
                                width: children[i] is TargetHeaderNode ? 400 : 300,
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
                              selectedNodeId: selectedNodeId,
                              progress: progress,
                              depth: depth + 1,
                            ),
                          ),
                          child: _NodeTreeView(
                            colors: colors,
                            sequence: sequence,
                            nodeId: children[i].id,
                            selectedNodeId: selectedNodeId,
                            progress: progress,
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
                        padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 8),
                        child: Text(
                          isMobile ? 'Tap + to add instructions' : 'Drop instructions here',
                          style: TextStyle(
                            fontSize: isMobile ? 12 : 11,
                            color: colors.textMuted.withValues(alpha: 0.5),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
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

      // Keep panel visible for 20 seconds after node stops running
      if (oldWidget.nodeStatus == NodeStatus.running && _showProgressPanel) {
        Future.delayed(_panelPersistDuration, () {
          if (mounted && widget.nodeStatus != NodeStatus.running) {
            setState(() => _showProgressPanel = false);
          }
        });
      }
    }
  }

  @override
  void dispose() {
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

  IconData _getIcon() {
    switch (widget.node.iconName) {
      case 'target': return LucideIcons.target;
      case 'camera': return LucideIcons.camera;
      case 'circle': return LucideIcons.circle;
      case 'shuffle': return LucideIcons.shuffle;
      case 'compass': return LucideIcons.compass;
      case 'crosshair': return LucideIcons.crosshair;
      case 'parking-circle': return LucideIcons.parkingCircle;
      case 'unlock': return LucideIcons.unlock;
      case 'focus': return LucideIcons.focus;
      case 'snowflake': return LucideIcons.snowflake;
      case 'flame': return LucideIcons.flame;
      case 'rotate-cw': return LucideIcons.rotateCw;
      case 'repeat': return LucideIcons.repeat;
      case 'git-merge': return LucideIcons.gitMerge;
      case 'git-branch': return LucideIcons.gitBranch;
      case 'shield-check': return LucideIcons.shieldCheck;
      case 'clock': return LucideIcons.clock;
      case 'timer': return LucideIcons.timer;
      case 'bell': return LucideIcons.bell;
      case 'code': return LucideIcons.code;
      case 'list': return LucideIcons.list;
      default: return LucideIcons.box;
    }
  }

  Color _getCategoryColor() {
    switch (widget.node.category) {
      case NodeCategory.instruction: return widget.colors.primary;
      case NodeCategory.trigger: return widget.colors.warning;
      case NodeCategory.logic: return widget.colors.accent;
      case NodeCategory.target: return widget.colors.warning;
    }
  }

  Color _getStatusColor() {
    switch (widget.nodeStatus) {
      case NodeStatus.running: return widget.colors.info;
      case NodeStatus.success: return widget.colors.success;
      case NodeStatus.failure: return widget.colors.error;
      case NodeStatus.skipped: return widget.colors.textMuted;
      case NodeStatus.cancelled: return widget.colors.warning;
      default: return Colors.transparent;
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
          child: GestureDetector(
            onTap: widget.onSelect,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: EdgeInsets.symmetric(vertical: verticalMargin),
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                  decoration: BoxDecoration(
                color: widget.isDragging
                    ? categoryColor.withValues(alpha: 0.2)
                    : widget.isSelected
                        ? categoryColor.withValues(alpha: 0.15)
                        : isTargetHeader
                            ? categoryColor.withValues(alpha: 0.08) // Slight tint for target headers
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
                              ? categoryColor.withValues(alpha: 0.3) // Stronger border for target headers
                              : widget.colors.border,
                  width: widget.isSelected || isTargetHeader ? 2 : 1, // Thicker border for target headers
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
                opacity: isDisabled ? 0.5 : 1.0,
                child: Row(
                  children: [
                    // Status indicator
                    if (widget.nodeStatus != null && widget.nodeStatus != NodeStatus.pending)
                      Container(
                        width: 4,
                        height: iconBoxSize,
                        margin: EdgeInsets.only(right: isMobile ? 12 : 10),
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
                        borderRadius: BorderRadius.circular(isMobile ? 10 : 8),
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
                              fontSize: isTargetHeader ? titleFontSize + 1 : titleFontSize,
                              fontWeight: FontWeight.w600,
                              color: widget.colors.textPrimary,
                              decoration: isDisabled
                                  ? TextDecoration.lineThrough
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
                          // Show progress bar for running instructions
                          if (isRunning && widget.progressPercent != null && widget.progressPercent! > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.progressDetail != null && widget.progressDetail!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
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
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: widget.progressPercent! / 100.0,
                                      minHeight: 4,
                                      backgroundColor: widget.colors.surfaceAlt,
                                      valueColor: AlwaysStoppedAnimation<Color>(widget.colors.info),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Actions
                    if (_isHovered && !widget.isDragging) ...[
                      _NodeActionButton(
                        icon: widget.node.isEnabled
                            ? LucideIcons.eye
                            : LucideIcons.eyeOff,
                        tooltip: widget.node.isEnabled ? 'Disable' : 'Enable',
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
                              side: BorderSide(color: widget.colors.border),
                            ),
                          ),
                        ),
                        child: PopupMenuButton<String>(
                          icon: Icon(LucideIcons.moreVertical, size: 14, color: widget.colors.textMuted),
                          tooltip: 'More Actions',
                          padding: EdgeInsets.zero,
                          itemBuilder: (context) => [
                            if (widget.hasChildren) ...[
                              const PopupMenuItem(
                                value: 'wrap_children_target',
                                height: 32,
                                child: Text('Wrap Children in Target Header', style: TextStyle(fontSize: 13)),
                              ),
                              const PopupMenuItem(
                                value: 'wrap_children_loop',
                                height: 32,
                                child: Text('Wrap Children in Loop', style: TextStyle(fontSize: 13)),
                              ),
                              const PopupMenuItem(
                                value: 'wrap_children_set',
                                height: 32,
                                child: Text('Wrap Children in Instruction Set', style: TextStyle(fontSize: 13)),
                              ),
                              const PopupMenuDivider(height: 8),
                            ],
                            const PopupMenuItem(
                              value: 'wrap_loop',
                              height: 32,
                              child: Text('Wrap in Loop', style: TextStyle(fontSize: 13)),
                            ),
                            const PopupMenuItem(
                              value: 'wrap_set',
                              height: 32,
                              child: Text('Wrap in Instruction Set', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                          onSelected: (value) {
                            final notifier = ref.read(currentSequenceProvider.notifier);
                            switch (value) {
                              case 'wrap_children_target':
                                notifier.wrapChildren(
                                  widget.node.id,
                                  TargetHeaderNode(targetName: 'New Target', raHours: 0, decDegrees: 0)
                                );
                                break;
                              case 'wrap_children_loop':
                                notifier.wrapChildren(
                                  widget.node.id, 
                                  LoopNode()
                                );
                                break;
                              case 'wrap_children_set':
                                notifier.wrapChildren(
                                  widget.node.id, 
                                  InstructionSetNode()
                                );
                                break;
                              case 'wrap_loop':
                                notifier.wrapNode(
                                  widget.node.id, 
                                  LoopNode()
                                );
                                break;
                              case 'wrap_set':
                                notifier.wrapNode(
                                  widget.node.id, 
                                  InstructionSetNode()
                                );
                                break;
                            }
                          },
                        ),
                      ),
                    ],

                    // Expand indicator for containers
                    if (widget.hasChildren || isTargetHeader) // Always show chevron for containers even if empty to hint at nesting
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
    // Progress panel for expanded details
    if (_shouldShowProgressPanel)
      getProgressPanelForNode(
        node: widget.node,
        colors: widget.colors,
        progressPercent: widget.progressPercent ?? 0,
        progressDetail: widget.progressDetail,
      ) ?? const SizedBox.shrink(),
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
              color: _isHovered ? color.withValues(alpha: 0.1) : Colors.transparent,
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
          decoration: BoxDecoration(
            color: isOver
                ? colors.primary.withValues(alpha: 0.25)
                : showDropZone
                    ? colors.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isOver
                ? Border.all(color: colors.primary, width: 2)
                : showDropZone
                    ? Border.all(color: colors.primary.withValues(alpha: 0.4), width: 1, strokeAlign: BorderSide.strokeAlignInside)
                    : null,
          ),
          child: isOver
              ? Center(
                  child: Text(
                    'Drop here',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : showDropZone
                  ? Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 2,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.add_circle_outline,
                            size: 12,
                            color: colors.primary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 20,
                            height: 2,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
        );
      },
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


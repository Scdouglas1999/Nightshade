import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/sequence_mutator_helper.dart';
import '../../../widgets/tutorial_keys/sequencer_keys.dart';
import 'delete_node_confirmation.dart';
import 'exposure_node_thumbnail_strip.dart';
import 'node_duration_chip.dart';
import 'node_progress_panels.dart';
import 'node_summary.dart';
import 'node_summary_line.dart';
import 'palette_icon_map.dart';
import 'sequence_minimap.dart';
import 'sequence_tree_context_menu.dart';
import 'sequence_tree_shortcuts.dart';
import 'target_header_card.dart';
import 'target_queue_panel.dart';
import 'visual_timeline.dart';

part 'sequence_tree/sequence_header.dart';
part 'sequence_tree/node_tree_view.dart';
part 'sequence_tree/node_item.dart';
part 'sequence_tree/support_widgets.dart';

/// Live handle to the tree's GlobalKey registry (node id -> row key).
///
/// [SequenceTree] publishes its registry here so sibling widgets (notably
/// [SequenceMinimap]) can route "navigate to node" through the SAME
/// `Scrollable.ensureVisible` path the auto-follow uses, instead of
/// guessing a scroll offset. Null until the tree mounts. Not autoDispose:
/// the minimap may rebuild independently and must keep resolving keys.
final treeNodeKeyRegistryProvider =
    StateProvider<Map<String, GlobalKey>?>((ref) => null);

/// Provider to track when a node is being dragged globally
/// This allows all drop zones to become visible when any drag starts
// autoDispose: drag state is transient UI — every drag begins from `false`
// and is reset by the matching onDragEnd/Cancel. Disposing on screen
// teardown ensures a stale `true` from an interrupted drag cannot leak
// into the next sequencer session.
final isDraggingNodeProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Tree search query — filters the in-tree "jump to node" results popover in
/// the sequence header. autoDispose so it resets between sequencer visits.
final treeSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Provider for "follow execution" toggle — auto-scrolls tree to current node
// autoDispose: tab/screen-scoped toggle; default (on) is the right initial
// state on each visit to the sequencer.
final followExecutionProvider = StateProvider.autoDispose<bool>((ref) => true);

// Note: confirm-then-delete now lives in `delete_node_confirmation.dart`
// as `confirmAndDeleteSequenceNode`. The tree's inline trash buttons and
// the TargetHeaderCard delete button below route through that helper so
// every user-initiated delete surface shares one policy.

/// Insert a dragged [snippet] into the tree through [withSequenceMutation]
/// so a locked-state or unknown-node-type failure surfaces a snackbar/dialog
/// instead of an uncaught throw. Shared by every drag-drop TemplateSnippet
/// branch (root target, per-container target, inter-row drop zone) so the
/// drop path matches the tap path's error handling.
void insertSnippetGuarded(
  BuildContext context,
  WidgetRef ref,
  TemplateSnippet snippet, {
  String? parentId,
  int? index,
}) {
  final profile = ref.read(activeEquipmentProfileProvider);
  withSequenceMutation(
    context,
    ref,
    operationName: 'Insert template',
    action: () async {
      ref.read(currentSequenceProvider.notifier).insertSnippet(
            snippet,
            parentId: parentId,
            index: index,
            profileFilterNames: profile?.filterNames,
          );
    },
  );
}

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

  /// GlobalKey registry for auto-scroll: maps node IDs to their GlobalKeys.
  /// Scoped to this state so it's torn down with the screen — the previous
  /// module-level map leaked GlobalKeys across hot-reload and screen
  /// transitions.
  final Map<String, GlobalKey> _nodeKeyRegistry = <String, GlobalKey>{};

  /// The sequence id we last reconciled the key registry against. Used by
  /// [didUpdateWidget] / [_pruneKeyRegistry] to detect "the user opened a
  /// different sequence" and clear the registry.
  String? _registryOwnerSequenceId;

  /// FocusNode for the tree-keyboard-shortcut wiring. Owned so the tree
  /// keeps focus across rebuilds — without this, every selection change
  /// reshuffles focus and arrow keys stop working after the first press.
  late final FocusNode _treeFocusNode;

  /// Captured during [initState] so [dispose] can clear the published
  /// registry handle without touching `ref` — Riverpod forbids `ref.read`
  /// after the widget is disposed. The provider is not autoDispose, so the
  /// notifier outlives this widget and is safe to hold.
  late final StateController<Map<String, GlobalKey>?> _registryController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onManualScroll);
    _treeFocusNode = FocusNode(debugLabel: 'sequence-tree');
    _registryController = ref.read(treeNodeKeyRegistryProvider.notifier);
    // Publish the registry handle so the minimap can route navigation
    // through the same ensureVisible path. Done post-frame because provider
    // writes are illegal during the initial build pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _registryController.state = _nodeKeyRegistry;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onManualScroll);
    _scrollController.dispose();
    _treeFocusNode.dispose();
    // Clear the published handle after the current teardown pass. Riverpod
    // forbids provider writes while the widget tree is building/disposing, and
    // this mirrors the post-frame publish in initState.
    final registry = _nodeKeyRegistry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The owning ProviderScope may be torn down before this deferred
      // callback runs (for example when the app/test root is replaced).
      // StateController throws even on a read after disposal, so gate the
      // compare-and-clear operation on the controller's lifetime.
      if (!_registryController.mounted) return;
      if (_registryController.state == registry) {
        _registryController.state = null;
      }
    });
    _nodeKeyRegistry.clear();
    super.dispose();
  }

  /// Drop stale entries from the key registry. Called from build() once the
  /// current set of node ids is known. Without this, replacing a node
  /// (e.g. via wrap/group) leaves its GlobalKey in the map forever; the
  /// next node sharing that id would steal the key and crash with a
  /// "duplicate GlobalKey in widget tree" error.
  void _pruneKeyRegistry(Sequence sequence) {
    // If the active sequence changed entirely, the registry is rebuilt
    // from scratch in the next render — no need to keep any keys.
    if (_registryOwnerSequenceId != sequence.id) {
      _nodeKeyRegistry.clear();
      _registryOwnerSequenceId = sequence.id;
      return;
    }
    final liveIds = sequence.nodes.keys.toSet();
    _nodeKeyRegistry.removeWhere((id, _) => !liveIds.contains(id));
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

  /// Add a starter Target Header from the empty state.
  ///
  /// [addTargetHeader] throws [NoActiveSequenceException] when no sequence is
  /// loaded, so we create one first when [currentSequenceProvider] is null,
  /// then add the target. Routed through [withSequenceMutation] so any editor
  /// failure surfaces as a snackbar rather than an uncaught throw.
  void _addStarterTargetHeader() {
    withSequenceMutation(
      context,
      ref,
      operationName: 'Add target header',
      action: () async {
        final notifier = ref.read(currentSequenceProvider.notifier);
        if (ref.read(currentSequenceProvider) == null) {
          notifier.createSequence();
        }
        final target = TargetHeaderNode(
          name: 'New Target',
          targetName: 'New Target',
          raHours: 0.0,
          decDegrees: 0.0,
        );
        notifier.addTargetHeader(target);
        ref.read(selectedNodeIdProvider.notifier).state = target.id;
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return EmptyState(
      icon: LucideIcons.workflow,
      title: 'Build Your Sequence',
      body: isMobile
          ? 'Tap + to add nodes'
          : 'Drag nodes from the palette to start building',
      action: NightshadeButton(
        onPressed: _addStarterTargetHeader,
        label: 'Add Target Header',
        icon: LucideIcons.target,
        variant: ButtonVariant.primary,
        size: ButtonSize.small,
      ),
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
      return _buildEmptyState(context);
    }

    final rootNode = sequence.rootNode;
    if (rootNode == null) {
      return _buildEmptyState(context);
    }

    // Reconcile the key registry against the current sequence before we
    // hand the registry to the recursive view. Pruning here (instead of
    // in didUpdateWidget) keeps it driven by the same provider snapshot
    // the view will render, so deletions can't race a re-add.
    _pruneKeyRegistry(sequence);

    // Tree-only keyboard shortcuts (arrow navigation, Enter -> properties,
    // Left/Right collapse/expand). Scoped to the tree FocusScope so they
    // don't fight Ctrl+Z/Y, Delete, etc. wired at the screen level. Text
    // fields inside property editors don't see these because Flutter
    // routes keystrokes to the nearest descendant Focus first.
    return Shortcuts(
      shortcuts: kSequenceTreeShortcuts,
      child: Actions(
        actions: buildSequenceTreeActions(ref),
        child: Focus(
          focusNode: _treeFocusNode,
          // The tree panel is the user's primary surface in the Builder
          // tab; auto-focus so arrows work right after switching tabs.
          autofocus: !widget.isMobile,
          child: _buildDragTarget(
              context, sequence, rootNode, progress, validation),
        ),
      ),
    );
  }

  Widget _buildDragTarget(
    BuildContext context,
    Sequence sequence,
    SequenceNode rootNode,
    SequenceProgress progress,
    LiveValidationState validation,
  ) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is NodePaletteItem ||
          details.data is TemplateSnippet ||
          details.data is TargetQueueDragPayload,
      onAcceptWithDetails: (details) {
        if (!ref.read(canEditSequenceProvider)) return;
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
          insertSnippetGuarded(context, ref, data);
        } else if (data is TargetQueueDragPayload) {
          // Drag-drop a queued target → append the prebuilt
          // TargetHeaderNode under the root. Selection follows the
          // drop so the properties panel reveals the new target.
          final notifier = ref.read(currentSequenceProvider.notifier);
          notifier.addNode(data.node);
          ref.read(selectedNodeIdProvider.notifier).state = data.node.id;
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A modal IME can reduce the already-covered backing route to a
              // few pixels after the shared shell consumes its inset. The
              // fixed sequence header cannot be useful there and previously
              // painted a yellow overflow stripe through the dialog scrim.
              if (constraints.hasBoundedHeight && constraints.maxHeight < 80) {
                return const SizedBox.expand();
              }
              return Column(
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
                        keyRegistry: _nodeKeyRegistry,
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
              );
            },
          ),
        );
      },
    );
  }
}

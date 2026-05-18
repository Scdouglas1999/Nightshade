import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Right-click / long-press context menu for nodes in the sequencer tree.
///
/// This widget never *renders* the menu — it only wraps its [child] with a
/// gesture detector that opens a [showMenu] popup at the pointer position
/// when the user secondary-taps (desktop) or long-presses (mobile). The
/// menu visual style mirrors the existing inline `PopupMenuButton` usage
/// in `_NodeItem` so the two surfaces feel like the same control.
class SequenceTreeContextMenu extends ConsumerWidget {
  const SequenceTreeContextMenu({
    super.key,
    required this.nodeId,
    required this.colors,
    required this.child,
  });

  final String nodeId;
  final NightshadeColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) =>
          _open(context, ref, details.globalPosition),
      onLongPressStart: (details) =>
          _open(context, ref, details.globalPosition),
      child: child,
    );
  }

  Future<void> _open(
      BuildContext context, WidgetRef ref, Offset position) async {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;
    final node = sequence.nodes[nodeId];
    if (node == null) return;

    // Selecting the node *before* opening matches OS conventions (right-
    // click also focuses), and the menu actions all run against the
    // selected node so this keeps state consistent.
    ref.read(selectedNodeIdProvider.notifier).state = nodeId;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final canEdit = ref.read(canEditSequenceProvider);

    final selected = await showMenu<_TreeMenuAction>(
      context: context,
      // RelativeRect from the global pointer position so the menu opens
      // exactly under the cursor regardless of where the widget sits in
      // the layout. Width 1×1 because we want a point, not a region.
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      color: colors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      // Wider min-width: the default 112px clips "Group into Sequential
      // Container" and triggers Flex overflow warnings in tests on
      // narrow surfaces.
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
      items: _buildMenuItems(node, canEdit: canEdit),
    );

    if (selected == null) return;
    if (!context.mounted) return;
    await _handleSelection(context, ref, sequence, node, selected);
  }

  List<PopupMenuEntry<_TreeMenuAction>> _buildMenuItems(SequenceNode node,
      {required bool canEdit}) {
    // Same compact style as the existing more-actions menu in _NodeItem.
    // When `canEdit` is false (sequence is running/paused/stopping) we
    // gray out every mutating entry so the user sees them but can't fire
    // them — matches `canEditSequenceProvider` semantics. The notifier
    // still throws SequenceLockedException as a last line of defense.
    PopupMenuItem<_TreeMenuAction> entry(
      _TreeMenuAction action,
      IconData icon,
      String label, {
      Color? labelColor,
      bool mutating = true,
      String? disabledReason,
    }) {
      // `disabledReason` overrides canEdit. We use it for "can't insert a
      // sibling of the root sequence node" — that case is permanent for
      // the node, not gated by execution state.
      final structurallyDisabled = disabledReason != null;
      final lockedByExecution = mutating && !canEdit;
      final disabled = structurallyDisabled || lockedByExecution;

      final effectiveColor = disabled
          ? colors.textMuted
          : (labelColor ?? colors.textSecondary);
      final effectiveLabel = disabled
          ? colors.textMuted
          : (labelColor ?? colors.textPrimary);

      // Tooltip wins for the structural case (more informative than
      // "sequence is running"); falls back to the execution-state hint
      // otherwise.
      final tooltip = structurallyDisabled
          ? disabledReason
          : (lockedByExecution
              ? 'Sequence is running — stop it first.'
              : null);

      final row = Row(
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: 10),
          // Flexible+ellipsis so the wider entries ("Group into
          // Sequential Container") don't overflow the menu's default
          // 256px width — overflow used to throw layout exceptions in
          // tests on narrow surfaces.
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: effectiveLabel),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      );

      return PopupMenuItem<_TreeMenuAction>(
        value: action,
        height: 36,
        enabled: !disabled,
        child: tooltip == null
            ? row
            // Wrap with a Tooltip so the user discovers *why* the entry
            // is grayed out instead of silently no-op-ing on click.
            : Tooltip(message: tooltip, child: row),
      );
    }

    // Insert Above / Insert Below require a parent slot. The root
    // sequence node has no parent, so those entries are permanently
    // disabled on the root with a tooltip explaining why — avoids the
    // pre-Wave 1.5 behaviour where clicking them on the root silently
    // returned without any feedback.
    final isRoot = node.parentId == null;
    const rootDisabledReason =
        'Cannot insert above/below the root sequence node.';

    // Group into ...: forbid grouping the root node itself, same reason.
    // For non-root nodes, the multi-select grouping helper validates that
    // the selection shares a parent; we don't need to pre-check that
    // here because the menu item is being opened on a single node.
    final groupDisabledReason = isRoot
        ? 'Cannot group the root sequence node into a container.'
        : null;

    // Duplicate / Delete also don't make sense for the root — the editor
    // ignores `removeNode(root)` silently which is the same audit
    // complaint. Surface the same way.
    final rootOnlyDisabledReason =
        isRoot ? 'This action is not available on the root sequence node.' : null;

    return [
      entry(
        _TreeMenuAction.insertAbove,
        LucideIcons.arrowUpToLine,
        'Insert Above',
        disabledReason: isRoot ? rootDisabledReason : null,
      ),
      entry(
        _TreeMenuAction.insertBelow,
        LucideIcons.arrowDownToLine,
        'Insert Below',
        disabledReason: isRoot ? rootDisabledReason : null,
      ),
      const PopupMenuDivider(height: 8),
      entry(
        _TreeMenuAction.duplicate,
        LucideIcons.copy,
        'Duplicate',
        disabledReason: rootOnlyDisabledReason,
      ),
      entry(
        _TreeMenuAction.groupSequential,
        LucideIcons.listOrdered,
        'Group into Sequential Container',
        disabledReason: groupDisabledReason,
      ),
      entry(
        _TreeMenuAction.groupParallel,
        LucideIcons.gitBranch,
        'Group into Parallel Container',
        disabledReason: groupDisabledReason,
      ),
      const PopupMenuDivider(height: 8),
      entry(
        node.isEnabled
            ? _TreeMenuAction.disable
            : _TreeMenuAction.enable,
        node.isEnabled ? LucideIcons.eyeOff : LucideIcons.eye,
        node.isEnabled ? 'Disable' : 'Enable',
      ),
      const PopupMenuDivider(height: 8),
      entry(
        _TreeMenuAction.delete,
        LucideIcons.trash2,
        'Delete',
        labelColor: colors.error,
        disabledReason: rootOnlyDisabledReason,
      ),
    ];
  }

  Future<void> _handleSelection(
    BuildContext context,
    WidgetRef ref,
    Sequence sequence,
    SequenceNode node,
    _TreeMenuAction action,
  ) async {
    final notifier = ref.read(currentSequenceProvider.notifier);

    switch (action) {
      case _TreeMenuAction.insertAbove:
        _insertSibling(context, ref, sequence, node, offset: 0);
        break;
      case _TreeMenuAction.insertBelow:
        _insertSibling(context, ref, sequence, node, offset: 1);
        break;
      case _TreeMenuAction.duplicate:
        notifier.duplicateNode(node.id);
        break;
      case _TreeMenuAction.groupSequential:
        await _groupSelection(
          context,
          ref,
          sequence,
          node,
          () => InstructionSetNode(name: 'Sequential'),
        );
        break;
      case _TreeMenuAction.groupParallel:
        await _groupSelection(
          context,
          ref,
          sequence,
          node,
          () => ParallelNode(),
        );
        break;
      case _TreeMenuAction.disable:
      case _TreeMenuAction.enable:
        notifier.toggleNodeEnabled(node.id);
        break;
      case _TreeMenuAction.delete:
        await _confirmAndDelete(context, ref, sequence, node);
        break;
    }
  }

  /// Resolve "group into X" against the current multi-selection.
  ///
  /// Behavior:
  ///   * Selection size 0 or 1 (or the right-clicked node is not part of
  ///     the selection): wrap only the right-clicked [node]. This matches
  ///     pre-multi-select intuition for the single-click case.
  ///   * Selection size > 1, all sharing a parent: wrap the whole
  ///     selection via [CurrentSequenceNotifier.wrapChildrenSubset] so
  ///     every selected sibling lands inside the same container in their
  ///     original tree order.
  ///   * Selection size > 1, spanning multiple parents: refuse with a
  ///     snackbar (no silent partial-wrap). The user must collapse the
  ///     selection or move siblings under one parent first.
  ///   * Selection contiguity is enforced by the notifier, which throws
  ///     [StateError]; we translate that into a snackbar too.
  Future<void> _groupSelection(
    BuildContext context,
    WidgetRef ref,
    Sequence sequence,
    SequenceNode node,
    SequenceNode Function() makeWrapper,
  ) async {
    final notifier = ref.read(currentSequenceProvider.notifier);
    final selected = ref.read(multiSelectedNodeIdsProvider);

    // Trivial cases: 0 or 1 selection, or right-click outside the multi-
    // selection → fall back to single-node wrap of the clicked node.
    if (selected.length < 2 || !selected.contains(node.id)) {
      notifier.wrapNode(node.id, makeWrapper());
      return;
    }

    // All selected nodes must share the same parent.
    String? sharedParent;
    for (final id in selected) {
      final n = sequence.nodes[id];
      if (n == null) continue;
      final p = n.parentId;
      if (p == null) {
        // The root node has no parent — wrapping the root is not a thing
        // we expose. Defensive: surface this rather than no-op.
        _showSnackBar(context,
            "Can't group the root sequence node into a container.");
        return;
      }
      sharedParent ??= p;
      if (sharedParent != p) {
        _showSnackBar(context,
            'Selection spans multiple parents — move the selected nodes '
            'under one container before grouping.');
        return;
      }
    }
    if (sharedParent == null) return;

    try {
      notifier.wrapChildrenSubset(
        sharedParent,
        selected.toList(),
        makeWrapper(),
      );
      // Move selection focus onto the new wrapper so subsequent edits
      // (rename it, drag more into it) act on the new container.
      final current = ref.read(currentSequenceProvider);
      if (current != null) {
        // The new wrapper is the only child of `sharedParent` that wasn't
        // in the original selection set — recover it by diffing.
        final newParent = current.nodes[sharedParent];
        if (newParent != null) {
          for (final childId in newParent.childIds) {
            if (!selected.contains(childId)) {
              ref.read(selectedNodeIdProvider.notifier).state = childId;
              break;
            }
          }
        }
      }
      ref.read(multiSelectedNodeIdsProvider.notifier).clear();
    } on StateError catch (e) {
      // wrapChildrenSubset throws on non-contiguous selection — surface
      // with the message verbatim so the user understands the constraint.
      _showSnackBar(context, e.message);
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Open the node-palette sheet rooted at this node's parent so the new
  /// node lands at the requested sibling slot. We piggy-back on the
  /// existing palette UX rather than inventing a "pick a node type"
  /// dialog inline — that's what `_showNodePaletteSheet` already gives
  /// us in the narrow-desktop / mobile layouts. For Insert Above /
  /// Insert Below we just compute the target index and open the palette
  /// preloaded with an insert callback.
  void _insertSibling(
    BuildContext context,
    WidgetRef ref,
    Sequence sequence,
    SequenceNode node, {
    required int offset,
  }) {
    final parentId = node.parentId;
    // The Insert Above / Insert Below menu items are pre-disabled for
    // root nodes (`_buildMenuItems` sets `disabledReason`), so reaching
    // this method with parentId == null indicates a programmatic call —
    // e.g. a future keyboard shortcut. Bail safely; the menu surface
    // already informs the user this isn't supported.
    if (parentId == null) return;
    final parent = sequence.nodes[parentId];
    if (parent == null) return;
    final targetIndex = parent.childIds.indexOf(node.id) + offset;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        return _InsertNodePicker(
          colors: colors,
          parentId: parentId,
          index: targetIndex,
          onDismiss: () => Navigator.of(sheetContext).pop(),
        );
      },
    );
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    WidgetRef ref,
    Sequence sequence,
    SequenceNode node,
  ) async {
    await confirmAndDeleteNode(
      context: context,
      ref: ref,
      sequence: sequence,
      nodeId: node.id,
      colors: colors,
    );
  }
}

/// Public helper used by the tree context menu *and* the screen-level
/// Delete keyboard shortcut. Shows a confirmation when the node has
/// descendants ("Delete 7 descendants?"), then removes it and clears
/// selection. Returns `true` if the delete went through.
///
/// Why a top-level function instead of an instance method: the screen
/// shortcut handler doesn't have a [SequenceTreeContextMenu] instance to
/// call into; extracting the dialog here lets both surfaces reuse the
/// same wording / safety rail.
Future<bool> confirmAndDeleteNode({
  required BuildContext context,
  required WidgetRef ref,
  required Sequence sequence,
  required String nodeId,
  required NightshadeColors colors,
}) async {
  final node = sequence.nodes[nodeId];
  if (node == null) return false;

  final descendants = sequence.countDescendants(nodeId);

  void clearSelection() {
    final selected = ref.read(selectedNodeIdProvider);
    if (selected == nodeId) {
      ref.read(selectedNodeIdProvider.notifier).state = null;
    }
  }

  // Leaves delete without prompting — matches the inline trash button's
  // behaviour and keeps single-key Delete from feeling sluggish.
  if (descendants == 0) {
    ref.read(currentSequenceProvider.notifier).removeNode(nodeId);
    clearSelection();
    return true;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Delete "${node.name}"?',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Text(
        descendants == 1
            ? 'This will also delete 1 child node.'
            : 'This will also delete $descendants descendant nodes.',
        style: TextStyle(color: colors.textSecondary),
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          label: 'Delete',
          variant: ButtonVariant.destructive,
          size: ButtonSize.small,
        ),
      ],
    ),
  );

  if (confirmed == true) {
    ref.read(currentSequenceProvider.notifier).removeNode(nodeId);
    clearSelection();
    return true;
  }
  return false;
}

enum _TreeMenuAction {
  insertAbove,
  insertBelow,
  duplicate,
  groupSequential,
  groupParallel,
  disable,
  enable,
  delete,
}

/// Lightweight palette wrapper used by Insert Above / Insert Below.
///
/// Implemented inline (not a separate widget file) because it only exists
/// to delegate into the existing palette + carry an "insert at index"
/// callback. We reuse [nodePaletteProvider] as the data source so any
/// node type the user can drag is also reachable from this menu.
class _InsertNodePicker extends ConsumerWidget {
  const _InsertNodePicker({
    required this.colors,
    required this.parentId,
    required this.index,
    required this.onDismiss,
  });

  final NightshadeColors colors;
  final String parentId;
  final int index;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(nodePaletteProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.plus, size: 16, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Insert node',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final category in categories) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Text(
                          category.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.textMuted,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      for (final item in category.items)
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            final newNode = item.createNode();
                            final notifier =
                                ref.read(currentSequenceProvider.notifier);
                            notifier.addNode(
                              newNode,
                              parentId: parentId,
                              index: index,
                            );
                            final children = item.createChildren?.call();
                            if (children != null) {
                              for (final c in children) {
                                notifier.addNode(c, parentId: newNode.id);
                              }
                            }
                            ref
                                .read(selectedNodeIdProvider.notifier)
                                .state = newNode.id;
                            onDismiss();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color:
                                        colors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    LucideIcons.box,
                                    size: 14,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        item.description,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colors.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

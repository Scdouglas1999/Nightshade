import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Keyboard shortcut wiring for the sequencer tree (Builder tab).
///
/// All bindings derive from [kSequenceTreeShortcuts] so they read like a
/// table at the top of the file and are easy to remap from a future
/// shortcuts-settings screen. Add a new accelerator by pairing it with a
/// new [Intent] subclass and an [Action] in [buildSequenceTreeActions].
///
/// Why a separate file: `sequence_tree.dart` is already ~2.5k lines and
/// the keyboard layer is orthogonal to its rendering. Scoping the
/// shortcuts here means widget tests can dispatch [Intent]s directly
/// without spinning up a full tree.

// ---------------------------------------------------------------------------
// Intent types
// ---------------------------------------------------------------------------

/// Move tree selection to the previous visible node.
class TreeMoveSelectionUpIntent extends Intent {
  const TreeMoveSelectionUpIntent({this.extend = false});

  /// `true` for Shift+Up: extend multi-selection instead of replacing it.
  final bool extend;
}

class TreeMoveSelectionDownIntent extends Intent {
  const TreeMoveSelectionDownIntent({this.extend = false});
  final bool extend;
}

/// Collapse the focused node (only meaningful for containers that the
/// user has expanded). Currently a no-op for nodes that don't track an
/// expanded state — leaves and target headers always render their
/// children. Wired here so future collapsible row types pick it up
/// without re-wiring keyboard handling.
class TreeCollapseFocusedIntent extends Intent {
  const TreeCollapseFocusedIntent();
}

class TreeExpandFocusedIntent extends Intent {
  const TreeExpandFocusedIntent();
}

/// Move keyboard focus from the tree to the right-hand properties panel.
/// The panel listens for [propertiesPanelFocusRequestProvider] tick to
/// pull focus onto its first interactive element.
class TreeFocusPropertiesIntent extends Intent {
  const TreeFocusPropertiesIntent();
}

// ---------------------------------------------------------------------------
// Bindings table — read this first
// ---------------------------------------------------------------------------

/// The user-visible keyboard bindings for the sequencer tree.
///
/// Keep this list small and obvious. Anything Ctrl/Shift-modified should
/// reuse the existing top-level shortcuts in `sequencer_screen.dart` so
/// we don't end up with two competing keyboard maps.
const Map<ShortcutActivator, Intent> kSequenceTreeShortcuts =
    <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowUp): TreeMoveSelectionUpIntent(),
  SingleActivator(LogicalKeyboardKey.arrowDown): TreeMoveSelectionDownIntent(),
  SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
      TreeMoveSelectionUpIntent(extend: true),
  SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
      TreeMoveSelectionDownIntent(extend: true),
  SingleActivator(LogicalKeyboardKey.arrowLeft): TreeCollapseFocusedIntent(),
  SingleActivator(LogicalKeyboardKey.arrowRight): TreeExpandFocusedIntent(),
  SingleActivator(LogicalKeyboardKey.enter): TreeFocusPropertiesIntent(),
};

/// One-shot tick: incremented when the user presses Enter in the tree.
/// `NodePropertiesPanel` listens to this and pulls focus onto its first
/// editable field. autoDispose because the channel is transient UI state.
final propertiesPanelFocusRequestProvider =
    StateProvider.autoDispose<int>((ref) => 0);

/// Per-node "collapsed in tree" preference. Used by Left / Right arrow
/// actions. Default is *expanded* (false) so power users don't lose any
/// children to a stale collapse state. autoDispose so the next session
/// starts fresh.
final collapsedNodeIdsProvider =
    StateNotifierProvider.autoDispose<_CollapsedNodeIdsNotifier, Set<String>>(
        (ref) => _CollapsedNodeIdsNotifier());

class _CollapsedNodeIdsNotifier extends StateNotifier<Set<String>> {
  _CollapsedNodeIdsNotifier() : super(const <String>{});

  bool isCollapsed(String nodeId) => state.contains(nodeId);

  void collapse(String nodeId) {
    if (state.contains(nodeId)) return;
    state = {...state, nodeId};
  }

  void expand(String nodeId) {
    if (!state.contains(nodeId)) return;
    final next = Set<String>.from(state)..remove(nodeId);
    state = next;
  }

  void toggle(String nodeId) {
    if (state.contains(nodeId)) {
      expand(nodeId);
    } else {
      collapse(nodeId);
    }
  }
}

// ---------------------------------------------------------------------------
// Action implementations
// ---------------------------------------------------------------------------

/// Build the [Actions] map for the tree's `Focus`/`Shortcuts` widget.
///
/// Factored as a function (rather than a const map) because Actions need
/// closures that close over `WidgetRef`. The caller (sequence_tree.dart)
/// passes its `ref` so we can read/write providers without smuggling
/// `ConsumerStatefulWidget` state in here.
Map<Type, Action<Intent>> buildSequenceTreeActions(WidgetRef ref) {
  return <Type, Action<Intent>>{
    TreeMoveSelectionUpIntent: CallbackAction<TreeMoveSelectionUpIntent>(
      onInvoke: (intent) => _moveSelection(ref, delta: -1, extend: intent.extend),
    ),
    TreeMoveSelectionDownIntent: CallbackAction<TreeMoveSelectionDownIntent>(
      onInvoke: (intent) => _moveSelection(ref, delta: 1, extend: intent.extend),
    ),
    TreeCollapseFocusedIntent: CallbackAction<TreeCollapseFocusedIntent>(
      onInvoke: (_) {
        final id = ref.read(selectedNodeIdProvider);
        if (id == null) return null;
        ref.read(collapsedNodeIdsProvider.notifier).collapse(id);
        return null;
      },
    ),
    TreeExpandFocusedIntent: CallbackAction<TreeExpandFocusedIntent>(
      onInvoke: (_) {
        final id = ref.read(selectedNodeIdProvider);
        if (id == null) return null;
        ref.read(collapsedNodeIdsProvider.notifier).expand(id);
        return null;
      },
    ),
    TreeFocusPropertiesIntent: CallbackAction<TreeFocusPropertiesIntent>(
      onInvoke: (_) {
        // Tick the request counter; NodePropertiesPanel listens via
        // ref.listen and calls FocusScope.requestFocus on its first field.
        final notifier =
            ref.read(propertiesPanelFocusRequestProvider.notifier);
        notifier.state = notifier.state + 1;
        return null;
      },
    ),
  };
}

/// Flatten the tree into the visible-row order (depth-first, skipping
/// children of collapsed nodes) so arrow keys advance one *row* at a
/// time the same way the user sees them. Mirrors how `_NodeTreeView`
/// renders the tree.
List<String> _visibleNodeOrder(Sequence sequence, Set<String> collapsed) {
  final root = sequence.rootNode;
  if (root == null) return const [];

  final out = <String>[];
  void recurse(String nodeId) {
    final n = sequence.nodes[nodeId];
    if (n == null) return;
    // The root itself is not a user-selectable row in the tree view; the
    // tree renders its *children* as the top level. We still recurse so
    // the children show up, but we skip pushing the root.
    final isRoot = sequence.rootNodeId == nodeId;
    if (!isRoot) out.add(nodeId);
    if (collapsed.contains(nodeId)) return;
    for (final childId in n.childIds) {
      recurse(childId);
    }
  }

  recurse(root.id);
  return out;
}

void _moveSelection(
  WidgetRef ref, {
  required int delta,
  required bool extend,
}) {
  final sequence = ref.read(currentSequenceProvider);
  if (sequence == null) return;

  final collapsed = ref.read(collapsedNodeIdsProvider);
  final order = _visibleNodeOrder(sequence, collapsed);
  if (order.isEmpty) return;

  final current = ref.read(selectedNodeIdProvider);
  int currentIdx = current == null ? -1 : order.indexOf(current);
  if (currentIdx < 0) {
    // No selection: snap to the first/last row depending on direction.
    currentIdx = delta > 0 ? -1 : order.length;
  }

  final nextIdx = (currentIdx + delta).clamp(0, order.length - 1);
  if (nextIdx == currentIdx && current != null) return;
  final nextId = order[nextIdx];

  if (extend) {
    // Shift+arrow: extend multi-selection. Reuse the same range-select
    // helper that Shift+Click uses so the behaviour matches mouse input.
    ref.read(multiSelectedNodeIdsProvider.notifier).rangeSelect(nextId);
  } else {
    ref.read(multiSelectedNodeIdsProvider.notifier).clear();
  }
  ref.read(selectedNodeIdProvider.notifier).state = nextId;
}

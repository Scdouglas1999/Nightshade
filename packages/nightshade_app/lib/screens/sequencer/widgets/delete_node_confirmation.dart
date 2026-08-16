import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Canonical confirmation + delete helper for sequencer nodes.
///
/// Every user-initiated delete path in the sequencer MUST funnel through this
/// helper so the confirmation policy stays consistent: it always prompts, even
/// on leaves, and the wording adapts to the descendant count. Without it a
/// misclick can take an entire target subtree silently.
///
/// Returns `true` iff the user confirmed AND the underlying remove completed
/// without throwing.
///
/// IMPORTANT: this helper is for USER-INITIATED deletes only. Do not call it
/// from programmatic flows (import dialogs rejecting a node, undo/redo,
/// executor cleanup, …) — those should call
/// [CurrentSequenceNotifier.removeNode] directly so they don't bounce the user
/// through an irrelevant prompt.
Future<bool> confirmAndDeleteSequenceNode({
  required BuildContext context,
  required WidgetRef ref,
  required String nodeId,
  NightshadeColors? colors,
}) async {
  final sequence = ref.read(currentSequenceProvider);
  if (sequence == null) return false;
  final node = sequence.nodes[nodeId];
  if (node == null) return false;

  final descendants = sequence.countDescendants(nodeId);
  final resolvedColors = colors ?? NightshadeColors.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: resolvedColors.surface,
      title: Text(
        'Delete "${node.name}"?',
        style: TextStyle(color: resolvedColors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          dialogContext,
          designMaxWidth: 440,
        ),
        child: Text(
          // Name the toolbar button first. Ctrl+Z is real but needs keyboard
          // focus inside the builder; the toolbar Undo always works, and a
          // recovery instruction that only sometimes applies is worse than
          // none.
          descendants == 0
              ? 'This node will be removed from the sequence. '
                  'Recover it with Undo in the toolbar (or Ctrl+Z).'
              : descendants == 1
                  ? 'This will also remove its 1 descendant. '
                      'Recover it with Undo in the toolbar (or Ctrl+Z).'
                  : 'This will also remove its $descendants descendants. '
                      'Recover it with Undo in the toolbar (or Ctrl+Z).',
          style: TextStyle(color: resolvedColors.textSecondary),
        ),
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

  if (confirmed != true) return false;

  try {
    ref.read(currentSequenceProvider.notifier).removeNode(nodeId);
  } catch (error) {
    // Surface the failure rather than swallowing it: the node stays in the
    // tree, so a silent catch leaves the user believing it was deleted.
    // SequenceLockedException is the expected case (the sequence started
    // running between dialog open and confirm).
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete "${node.name}": $error'),
          backgroundColor: resolvedColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    return false;
  }

  // Clear stale selection so the Properties panel doesn't redraw on a
  // node that no longer exists.
  if (ref.read(selectedNodeIdProvider) == nodeId) {
    ref.read(selectedNodeIdProvider.notifier).state = null;
  }
  return true;
}

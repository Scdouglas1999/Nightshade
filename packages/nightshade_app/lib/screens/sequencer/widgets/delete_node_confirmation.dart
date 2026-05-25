import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Canonical confirmation + delete helper for sequencer nodes.
///
/// Every user-initiated delete path in the sequencer (Properties-panel
/// "Delete Node" button, targets-tab trash icon, tree row trash icon,
/// tree right-click "Delete", screen-level Delete keyboard shortcut)
/// MUST funnel through this helper so the confirmation policy stays
/// consistent. Prior to consolidation each surface had its own policy
/// (some prompted, some didn't, descendant counts varied), and a
/// misclick on the Properties-panel button could nuke an entire target
/// subtree silently.
///
/// Behaviour:
///   * Reads the current sequence and the target node. Returns `false`
///     immediately if either is missing (e.g. a stale callback for a
///     node that was already removed).
///   * Always prompts the user — even on leaves — so the surfaces feel
///     identical. The wording adapts to the descendant count.
///   * On confirm, removes the node via [CurrentSequenceNotifier.removeNode].
///     If the editor throws (e.g. [SequenceLockedException] while the
///     sequence is running, or any other failure inside the editor),
///     the helper surfaces the error via a SnackBar — never silently
///     swallowed. Errors are a feature.
///   * Clears [selectedNodeIdProvider] when the removed node was the
///     active selection so the Properties panel doesn't keep rendering
///     stale fields.
///
/// Returns `true` iff the user confirmed AND the underlying remove
/// completed without throwing.
///
/// IMPORTANT: this helper is for USER-INITIATED deletes only. Do not
/// call it from programmatic flows (import dialogs rejecting a node,
/// undo/redo, executor cleanup, etc.) — those should call
/// [CurrentSequenceNotifier.removeNode] directly so they don't bounce
/// the user through an irrelevant prompt.
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
          descendants == 0
              ? 'This node will be removed from the sequence. '
                  'This cannot be undone except via Undo (Ctrl+Z).'
              : descendants == 1
                  ? 'This will also remove its 1 descendant. '
                      'This cannot be undone except via Undo (Ctrl+Z).'
                  : 'This will also remove its $descendants descendants. '
                      'This cannot be undone except via Undo (Ctrl+Z).',
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
    // Errors are a feature: surface the failure rather than swallowing.
    // SequenceLockedException is the expected case here (sequence
    // started running between dialog open and confirm); other editor
    // errors are equally important to expose.
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

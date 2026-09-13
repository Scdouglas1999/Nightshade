// Every mutation a folded row offers (spec §6): move the run as a block,
// duplicate it, disable it, delete it.
//
// A separate library rather than a `part` of `sequence_tree.dart` because
// `sequence_tree_context_menu.dart` is its own library and has to reach the
// same four operations — the right-click menu on a folded row must not be
// able to drift from the kebab on the same row.
//
// Every entry point shares one shape: `withSequenceMutation` so a locked
// sequence surfaces a snackbar instead of an uncaught throw, and
// `withUndoGroup` INSIDE it so the N `moveNode` / `duplicateNode` /
// `toggleNodeEnabled` calls a group needs collapse into a single undo entry.
// Without the group, undoing a three-member move would take three Ctrl+Z and
// pass through two states the user never asked for.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../../utils/sequence_mutator_helper.dart';
import '../../sequence_fold_model.dart';

/// Move [memberIds] under [parentId] so the run lands as one contiguous block
/// starting at [index], in one undo step.
///
/// [index] is interpreted exactly as the single-node drop interprets it: the
/// FIRST member goes where a lone `moveNode` of that member would have put it,
/// and every following member is then re-inserted directly after the one
/// before it. `index + k` is only correct when the block changes parent —
/// inside its own parent, removing a member shifts every later slot left, and
/// the run would end up reversed or scattered.
Future<bool> moveFoldGroup(
  BuildContext context,
  WidgetRef ref, {
  required List<String> memberIds,
  required String parentId,
  required int index,
}) {
  return withSequenceMutation(
    context,
    ref,
    operationName: 'move the folded steps',
    action: () async {
      ref.read(currentSequenceProvider.notifier).withUndoGroup(() {
        _relocateBlock(ref,
            memberIds: memberIds, parentId: parentId, index: index);
      });
    },
  );
}

/// Copy every member of the run and leave the copies as a second contiguous
/// block immediately after the original, in one undo step.
///
/// `duplicateNode` inserts each copy directly after ITS original, so calling
/// it member by member interleaves the two runs (`Ha Ha' OIII OIII' …`) —
/// which folds back into one six-member group and reads as a single run with
/// every filter doubled. The copies are collected and relocated as a block so
/// the result is what the user asked for: the same run, twice.
Future<bool> duplicateFoldGroup(
  BuildContext context,
  WidgetRef ref, {
  required FoldGroup group,
}) {
  return withSequenceMutation(
    context,
    ref,
    operationName: 'duplicate the folded steps',
    action: () async {
      final notifier = ref.read(currentSequenceProvider.notifier);
      notifier.withUndoGroup(() {
        final copies = <String>[];
        for (final memberId in group.memberIds) {
          notifier.duplicateNode(memberId);
          final siblings = ref
              .read(currentSequenceProvider)!
              .nodes[group.parentId]!
              .childIds;
          copies.add(siblings[siblings.indexOf(memberId) + 1]);
        }
        final siblings =
            ref.read(currentSequenceProvider)!.nodes[group.parentId]!.childIds;
        _relocateBlock(
          ref,
          memberIds: copies,
          parentId: group.parentId,
          index: siblings.indexOf(group.memberIds.last) + 1,
        );
      });
    },
  );
}

/// Disable every member of the run in one undo step.
///
/// A folded group is all-enabled by construction — `foldChildren` refuses a
/// disabled node as a run member — so a toggle over the members is a disable,
/// and the row only ever offers that direction. Once disabled the members stop
/// qualifying as a run, so the fold row is replaced by its (struck-through)
/// member rows on the next build.
Future<bool> disableFoldGroup(
  BuildContext context,
  WidgetRef ref, {
  required List<String> memberIds,
}) {
  return withSequenceMutation(
    context,
    ref,
    operationName: 'disable the folded steps',
    action: () async {
      final notifier = ref.read(currentSequenceProvider.notifier);
      notifier.withUndoGroup(() {
        for (final memberId in memberIds) {
          notifier.toggleNodeEnabled(memberId);
        }
      });
    },
  );
}

/// Confirm once, then delete every member of the run in one undo step.
///
/// The policy is `confirmAndDeleteSequenceNode`'s, restated for a run: always
/// prompt (even though every member is a leaf), say how much is going, and
/// name the toolbar's Undo as the way back. It cannot call that helper because
/// that helper asks per node — three dialogs for one row is exactly the
/// question §6 says to ask once.
///
/// Returns true iff the user confirmed AND the removal completed.
Future<bool> confirmAndDeleteFoldGroup({
  required BuildContext context,
  required WidgetRef ref,
  required FoldGroup group,
  NightshadeColors? colors,
}) async {
  final sequence = ref.read(currentSequenceProvider);
  if (sequence == null) return false;
  final resolvedColors = colors ?? NightshadeColors.of(context);
  final count = group.memberCount;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: resolvedColors.surface,
      title: Text(
        'Delete $count steps?',
        style: TextStyle(color: resolvedColors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          dialogContext,
          designMaxWidth: 440,
        ),
        child: Text(
          // The member labels, not the group's title: "Ha · OIII · SII" is
          // what the row shows, and a delete prompt has to name the same
          // things the row named.
          '${group.memberLabels.join(' · ')} will be removed from the '
          'sequence. Recover them with Undo in the toolbar (or Ctrl+Z).',
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
  if (!context.mounted) return false;

  final removed = await withSequenceMutation(
    context,
    ref,
    operationName: 'delete the folded steps',
    action: () async {
      final notifier = ref.read(currentSequenceProvider.notifier);
      notifier.withUndoGroup(() {
        for (final memberId in group.memberIds) {
          notifier.removeNode(memberId);
        }
      });
    },
  );
  if (!removed) return false;

  // The members are gone; a selection still pointing at one of them would
  // redraw the properties panel on a node that no longer exists.
  ref.read(multiSelectedNodeIdsProvider.notifier).clear();
  if (group.memberIds.contains(ref.read(selectedNodeIdProvider))) {
    ref.read(selectedNodeIdProvider.notifier).state = null;
  }
  return true;
}

/// Re-seat [memberIds] as a contiguous, ordered block starting at [index].
/// See [moveFoldGroup] for why the followers chase their predecessor instead
/// of taking `index + k`.
void _relocateBlock(
  WidgetRef ref, {
  required List<String> memberIds,
  required String parentId,
  required int index,
}) {
  final notifier = ref.read(currentSequenceProvider.notifier);
  notifier.moveNode(memberIds.first, parentId, index);
  for (var k = 1; k < memberIds.length; k++) {
    final siblings =
        ref.read(currentSequenceProvider)!.nodes[parentId]!.childIds;
    notifier.moveNode(
      memberIds[k],
      parentId,
      siblings.indexOf(memberIds[k - 1]) + 1,
    );
  }
}

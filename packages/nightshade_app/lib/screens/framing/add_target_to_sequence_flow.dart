// "Add target to an existing sequence" flow for the Framing screen.
//
// The Framing screen historically offered only ONE handoff to the sequencer:
// auto-build a complete Smart Night instruction tree for the framed target
// (`addFramedTargetToSequencer` in plan_tonight_sequencer_helper.dart). Users
// who hand-build their own sequences had no way to drop a framed target into a
// sequence they were assembling — they were forced to accept (and then prune)
// a generated tree.
//
// This adds the complementary, low-magic path: insert a *bare* TargetHeaderNode
// — the framed target's name / RA / Dec / rotation, with NO child instructions
// — into a sequence the user chooses, leaving the instruction tree for them to
// build in the Sequencer. The choice surface:
//
//   * If a sequence is open in the editor, that is the default destination.
//   * If saved sequences exist, the user can pick one of those instead (it is
//     opened — as a fresh-ID copy — into the editor, then the header is added).
//   * "New empty sequence" is always offered as the fall-back, and is the only
//     option when nothing is open and the library is empty.
//
// Errors surface, never silently degrade: a locked sequence
// (run in progress) or an unsaved-changes clobber is reported to the user
// rather than swallowed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Identifies the destination the user picked in the add-to-sequence dialog.
@immutable
class _SequenceDestination {
  /// Display label shown in the picker (sequence name, or "New empty sequence").
  final String label;

  /// Optional secondary line (e.g. target count) shown under [label].
  final String? subtitle;

  /// The saved sequence to open as the destination. `null` for the current
  /// in-editor sequence or for the "new empty sequence" option.
  final Sequence? savedSequence;

  /// True for the destination that targets the sequence already open in the
  /// editor (no load/copy required — just append).
  final bool isCurrent;

  /// True for the "create a brand-new empty sequence" destination.
  final bool isNew;

  const _SequenceDestination.current({required this.label, this.subtitle})
      : savedSequence = null,
        isCurrent = true,
        isNew = false;

  const _SequenceDestination.saved(this.savedSequence,
      {required this.label, this.subtitle})
      : isCurrent = false,
        isNew = false;

  const _SequenceDestination.newEmpty({required this.label})
      : savedSequence = null,
        subtitle = null,
        isCurrent = false,
        isNew = true;
}

/// Build a bare [TargetHeaderNode] (no child instructions) for a framed target.
///
/// Carries the framing composition forward: [rotationDegrees] (when non-zero)
/// becomes the header's `rotation` so the Sequencer's slew/center/rotate step
/// reproduces the framing the user dialed in. RA/Dec/name come straight from
/// the resolved [target].
TargetHeaderNode bareTargetHeaderForFramedTarget({
  required FramingTarget target,
  double? rotationDegrees,
}) {
  final rotation = (rotationDegrees != null && rotationDegrees != 0)
      ? rotationDegrees
      : null;
  return TargetHeaderNode(
    name: target.name,
    targetName: target.name,
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    rotation: rotation,
  );
}

/// Present the destination picker and insert a bare target header for [target].
///
/// Returns `true` when a header was added, `false` when the user cancelled or
/// the editor refused (locked sequence / declined clobber). Mirrors the return
/// contract of the existing `addTargetHeaderWithPrompt` helper so callers can
/// gate their success snackbar on it.
Future<bool> addFramedTargetToExistingSequence({
  required BuildContext context,
  required WidgetRef ref,
  required FramingTarget target,
  double? rotationDegrees,
}) async {
  final current = ref.read(currentSequenceProvider);
  final savedAsync = ref.read(savedSequencesProvider);

  // Best-effort fetch of the library list. `savedSequencesProvider` is
  // autoDispose + async; if it has not resolved yet (or errored) we degrade
  // to "current + new" rather than blocking the user — the explicit fetch
  // below awaits a fresh read so the common case still shows the full list.
  List<Sequence> saved = savedAsync.valueOrNull ?? const <Sequence>[];
  if (savedAsync is! AsyncData) {
    try {
      saved = await ref.read(savedSequencesProvider.future);
    } catch (_) {
      // Library unavailable (e.g. remote host offline) — proceed with what we
      // have. The current/new destinations remain valid.
      saved = ref.read(savedSequencesProvider).valueOrNull ?? saved;
    }
  }
  if (!context.mounted) return false;

  // De-dupe: the open sequence often also appears in the saved list (same
  // databaseId). Show it once, as the "current" destination.
  final currentDbId = current?.databaseId;
  final destinations = <_SequenceDestination>[
    if (current != null)
      _SequenceDestination.current(
        label: current.name.isEmpty ? 'Current sequence' : current.name,
        subtitle: _targetCountSubtitle(current),
      ),
    for (final seq in saved)
      if (!(currentDbId != null && seq.databaseId == currentDbId))
        _SequenceDestination.saved(
          seq,
          label: seq.name.isEmpty ? 'Untitled sequence' : seq.name,
          subtitle: _targetCountSubtitle(seq),
        ),
    const _SequenceDestination.newEmpty(
      label: 'New empty sequence',
    ),
  ];

  // Default selection: the open sequence if there is one, else the first saved
  // sequence, else the "new empty" option.
  final initialIndex =
      current != null ? 0 : (saved.isNotEmpty ? 0 : destinations.length - 1);

  final chosen = await showDialog<_SequenceDestination>(
    context: context,
    builder: (ctx) => _DestinationPickerDialog(
      targetName: target.name,
      destinations: destinations,
      initialIndex: initialIndex,
    ),
  );
  if (chosen == null || !context.mounted) return false;

  final header = bareTargetHeaderForFramedTarget(
      target: target, rotationDegrees: rotationDegrees);
  final notifier = ref.read(currentSequenceProvider.notifier);

  try {
    if (chosen.isNew) {
      notifier.createSequence(
        name: target.name.isEmpty ? 'New Sequence' : target.name,
        discardUnsaved: false,
      );
      notifier.addTargetHeader(header);
    } else if (chosen.isCurrent) {
      notifier.addTargetHeader(header);
    } else {
      // A different saved sequence — open a fresh-ID copy into the editor,
      // then append the header.
      notifier.loadCopyForEditing(chosen.savedSequence!);
      notifier.addTargetHeader(header);
    }
    return true;
  } on UnsavedChangesException catch (e) {
    if (!context.mounted) return false;
    final discard = await _confirmDiscard(
      context,
      currentName: e.currentSequenceName,
      destinationName: chosen.label,
    );
    if (discard != true || !context.mounted) return false;
    try {
      if (chosen.isNew) {
        notifier.createSequence(
          name: target.name.isEmpty ? 'New Sequence' : target.name,
          discardUnsaved: true,
        );
      } else {
        notifier.loadCopyForEditing(chosen.savedSequence!,
            discardUnsaved: true);
      }
      notifier.addTargetHeader(header);
      return true;
    } on SequenceLockedException catch (lockErr) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(lockErr.message)));
      }
      return false;
    }
  } on SequenceLockedException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  } on NoActiveSequenceException catch (e) {
    // Should not happen — createSequence precedes addTargetHeader on the new
    // path and the current/saved paths guarantee a loaded sequence. Surface
    // rather than silently no-op if the invariant is ever broken.
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}

String? _targetCountSubtitle(Sequence sequence) {
  final count = sequence.nodes.values.whereType<TargetHeaderNode>().length;
  if (count == 0) return 'No targets yet';
  return '$count target${count == 1 ? '' : 's'}';
}

Future<bool?> _confirmDiscard(
  BuildContext context, {
  required String currentName,
  required String destinationName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => NightshadeDialog(
      title: 'Discard unsaved changes?',
      icon: NightshadeIcons.warning,
      width: 440,
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          label: 'Discard and continue',
          size: ButtonSize.small,
        ),
      ],
      child: Text(
        '"$currentName" has unsaved changes. Switching to "$destinationName" '
        'will discard them.',
      ),
    ),
  );
}

/// Radio-list dialog letting the user choose where the framed target goes.
class _DestinationPickerDialog extends StatefulWidget {
  final String targetName;
  final List<_SequenceDestination> destinations;
  final int initialIndex;

  const _DestinationPickerDialog({
    required this.targetName,
    required this.destinations,
    required this.initialIndex,
  });

  @override
  State<_DestinationPickerDialog> createState() =>
      _DestinationPickerDialogState();
}

class _DestinationPickerDialogState extends State<_DestinationPickerDialog> {
  late int _selected = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeDialog(
      title: 'Add target to sequence',
      icon: LucideIcons.listPlus,
      width: 460,
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () =>
              Navigator.of(context).pop(widget.destinations[_selected]),
          label: 'Add target',
          icon: NightshadeIcons.add,
          size: ButtonSize.small,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Insert "${widget.targetName}" as a new target group. You add the '
            'imaging instructions under it in the Sequencer.',
            style: NightshadeTypography.bodySm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          for (var i = 0; i < widget.destinations.length; i++)
            _DestinationTile(
              destination: widget.destinations[i],
              selected: i == _selected,
              onTap: () => setState(() => _selected = i),
              colors: colors,
            ),
        ],
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  final _SequenceDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _DestinationTile({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final icon = destination.isNew
        ? LucideIcons.filePlus
        : destination.isCurrent
            ? NightshadeIcons.edit
            : NightshadeIcons.folderOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.12)
                : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(
              color: selected ? colors.primary : colors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? LucideIcons.checkCircle2 : NightshadeIcons.circle,
                size: NightshadeTokens.iconSm,
                color: selected ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Icon(icon,
                  size: NightshadeTokens.iconSm, color: colors.textSecondary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      style: NightshadeTypography.bodyMedium
                          .copyWith(color: colors.textPrimary),
                    ),
                    if (destination.subtitle != null)
                      Text(
                        destination.subtitle!,
                        style: NightshadeTypography.caption
                            .copyWith(color: colors.textMuted),
                      ),
                  ],
                ),
              ),
              if (destination.isCurrent) _Badge(label: 'Open', colors: colors),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final NightshadeColors colors;

  const _Badge({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
      ),
      child: Text(
        label,
        style: NightshadeTypography.caption.copyWith(color: colors.primary),
      ),
    );
  }
}

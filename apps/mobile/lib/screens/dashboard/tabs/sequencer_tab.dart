import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Sequencer tab — phone-native run controller:
///   * Top half: node list with status icons (current/next/completed)
///   * Bottom 1/3: sticky strip with current target, ETA, and start/stop
///   * Load-sequence picker opens a `NightshadeDialog` listing saved
///     sequences from the database.
///
/// All work flows through the existing `sequenceExecutorProvider` and
/// `currentSequenceProvider` so behaviour stays identical to the desktop
/// sequencer.
class SequencerTab extends ConsumerWidget {
  const SequencerTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final execState = ref.watch(sequenceExecutionStateProvider);

    return Column(
      children: [
        // Sticky header — current sequence name + load button.
        _Header(sequence: sequence),
        Expanded(
          child: sequence == null
              ? const _NoSequenceState()
              : _NodeList(sequence: sequence, progress: progress),
        ),
        // Bottom strip — "current target + ETA" + start/stop controls.
        // Keeping it sticky means the user can run/halt from any scroll
        // position, which matches the desktop sequence-controls bar.
        _StickyFooter(
          sequence: sequence,
          progress: progress,
          execState: execState,
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  final Sequence? sequence;
  const _Header({required this.sequence});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sequence?.name ?? 'No sequence loaded',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (sequence != null)
                  Text(
                    '${sequence!.totalExposures} frames • '
                    '${_formatHms(sequence!.totalIntegrationSecs)}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          NightshadeButton(
            label: 'Load',
            icon: LucideIcons.folderOpen,
            size: ButtonSize.medium,
            variant: ButtonVariant.outline,
            onPressed: () => _showLoadPicker(context, ref),
          ),
        ],
      ),
    );
  }
}

Future<void> _showLoadPicker(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(sequenceRepositoryProvider);
  List<Sequence> all;
  try {
    all = await repo.loadAllSequences();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not load sequences: $e')));
    }
    return;
  }
  // Sort by modifiedAt desc so "Recent" reads as a natural prefix.
  all.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      return NightshadeDialog(
        title: 'Load sequence',
        icon: LucideIcons.folderOpen,
        width: 360,
        height: 480,
        child: all.isEmpty
            ? const EmptyState(
                icon: LucideIcons.fileX,
                title: 'No saved sequences',
                body: 'Create one on the desktop and it will appear here.',
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: all.length,
                separatorBuilder: (_, __) =>
                    Divider(color: Theme.of(dialogCtx).dividerColor),
                itemBuilder: (_, i) {
                  final s = all[i];
                  return ListTile(
                    minVerticalPadding: 12,
                    title: Text(s.name),
                    subtitle: Text(
                      '${s.totalExposures} frames • '
                      '${_formatHms(s.totalIntegrationSecs)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      ref
                          .read(currentSequenceProvider.notifier)
                          .loadSequence(s);
                      Navigator.of(dialogCtx).pop();
                    },
                  );
                },
              ),
      );
    },
  );
}

class _NoSequenceState extends StatelessWidget {
  const _NoSequenceState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: LucideIcons.play,
      title: 'No sequence loaded',
      body: 'Tap "Load" above to pick a saved sequence from the library.',
    );
  }
}

class _NodeList extends StatelessWidget {
  final Sequence sequence;
  final SequenceProgress progress;
  const _NodeList({required this.sequence, required this.progress});

  @override
  Widget build(BuildContext context) {
    // Walk the sequence tree in display order so the list mirrors the
    // desktop sequencer view. We do a simple DFS from the root node and
    // indent children by depth.
    final rows = <_NodeRow>[];
    final root = sequence.rootNode;
    if (root != null) {
      _walk(sequence, root, 0, rows);
    }

    if (rows.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.fileWarning,
        title: 'Sequence is empty',
        body: 'Add at least one instruction on the desktop and reload.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return _NodeTile(
          row: row,
          status: progress.nodeStatuses[row.node.id],
          isCurrent: progress.currentNodeId == row.node.id,
          progressPct: progress.nodeProgressPercent[row.node.id],
        );
      },
    );
  }

  void _walk(Sequence seq, SequenceNode node, int depth, List<_NodeRow> out) {
    out.add(_NodeRow(node: node, depth: depth));
    for (final childId in node.childIds) {
      final child = seq.nodes[childId];
      if (child != null) {
        _walk(seq, child, depth + 1, out);
      }
    }
  }
}

class _NodeRow {
  final SequenceNode node;
  final int depth;
  _NodeRow({required this.node, required this.depth});
}

class _NodeTile extends StatelessWidget {
  final _NodeRow row;
  final NodeStatus? status;
  final bool isCurrent;
  final double? progressPct;

  const _NodeTile({
    required this.row,
    required this.status,
    required this.isCurrent,
    required this.progressPct,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (icon, color) = _statusVisual(status, isCurrent, colors);
    return Container(
      margin: EdgeInsets.fromLTRB(16 + row.depth * 16.0, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent ? colors.primary.withValues(alpha: 0.1) : colors.surface,
        border: Border.all(
          color: isCurrent ? colors.primary : colors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.node.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (progressPct != null && isCurrent && progressPct! > 0) ...[
                  const SizedBox(height: 4),
                  NightshadeProgressBar(
                    value: (progressPct! / 100.0).clamp(0.0, 1.0),
                    height: 4,
                  ),
                ],
              ],
            ),
          ),
          if (!row.node.isEnabled)
            Icon(LucideIcons.eyeOff, size: 14, color: colors.textMuted),
        ],
      ),
    );
  }

  (IconData, Color) _statusVisual(
    NodeStatus? s,
    bool isCurrent,
    NightshadeColors colors,
  ) {
    if (isCurrent) {
      return (LucideIcons.loader, colors.primary);
    }
    return switch (s) {
      NodeStatus.success => (LucideIcons.checkCircle2, colors.success),
      NodeStatus.failure => (LucideIcons.xCircle, colors.error),
      NodeStatus.running => (LucideIcons.loader, colors.primary),
      NodeStatus.skipped => (LucideIcons.skipForward, colors.textMuted),
      NodeStatus.cancelled => (LucideIcons.ban, colors.warning),
      NodeStatus.pending => (LucideIcons.circle, colors.textMuted),
      null => (LucideIcons.circle, colors.textMuted),
    };
  }
}

class _StickyFooter extends ConsumerWidget {
  final Sequence? sequence;
  final SequenceProgress progress;
  final SequenceExecutionState execState;
  const _StickyFooter({
    required this.sequence,
    required this.progress,
    required this.execState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final size = MediaQuery.sizeOf(context);
    // Bottom strip occupies the lower third of the screen. We sit above
    // the bottom nav, so we cap height to keep the node list usable.
    final maxHeight = (size.height / 3).clamp(160.0, 260.0);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(LucideIcons.target, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progress.currentTarget ?? sequence?.name ?? 'No target',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _ExecBadge(state: execState),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Frames',
                    value: '${progress.completedExposures}/'
                        '${progress.totalExposures}',
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Elapsed',
                    value: _formatHms(progress.elapsedSecs),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'ETA',
                    value: progress.estimatedRemainingSecs != null
                        ? _formatHms(progress.estimatedRemainingSecs!)
                        : '—',
                    colors: colors,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Trigger status — show running triggers (HFR/guiding/etc.) if
            // any. The executor surfaces them as currentNodeName when a
            // trigger fires, so we render whichever message is freshest.
            if (progress.message != null && progress.message!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  progress.message!,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            _ControlButtons(
              sequence: sequence,
              execState: execState,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecBadge extends StatelessWidget {
  final SequenceExecutionState state;
  const _ExecBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (label, color) = switch (state) {
      SequenceExecutionState.idle => ('Idle', colors.textMuted),
      SequenceExecutionState.running => ('Running', colors.success),
      SequenceExecutionState.paused => ('Paused', colors.warning),
      SequenceExecutionState.stopping => ('Stopping', colors.warning),
      SequenceExecutionState.completed => ('Done', colors.success),
      SequenceExecutionState.failed => ('Failed', colors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  const _Stat({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: colors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _ControlButtons extends ConsumerStatefulWidget {
  final Sequence? sequence;
  final SequenceExecutionState execState;
  const _ControlButtons({required this.sequence, required this.execState});

  @override
  ConsumerState<_ControlButtons> createState() => _ControlButtonsState();
}

class _ControlButtonsState extends ConsumerState<_ControlButtons> {
  bool _busy = false;

  Future<void> _start() async {
    if (widget.sequence == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).start();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).stop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).pause();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _busy = true);
    try {
      await ref.read(sequenceExecutorProvider).resume();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.execState == SequenceExecutionState.running;
    final isPaused = widget.execState == SequenceExecutionState.paused;
    final canStart = widget.sequence != null &&
        !isRunning &&
        !isPaused &&
        widget.execState != SequenceExecutionState.stopping;

    return Row(
      children: [
        Expanded(
          child: NightshadeButton(
            label: isPaused ? 'Resume' : (isRunning ? 'Pause' : 'Start'),
            icon: isPaused
                ? LucideIcons.play
                : (isRunning ? LucideIcons.pause : LucideIcons.play),
            size: ButtonSize.large,
            isLoading: _busy,
            variant: ButtonVariant.primary,
            onPressed: _busy
                ? null
                : (canStart
                    ? _start
                    : (isRunning ? _pause : (isPaused ? _resume : null))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NightshadeButton(
            label: 'Stop',
            icon: LucideIcons.square,
            size: ButtonSize.large,
            variant: ButtonVariant.destructive,
            onPressed: (_busy || (!isRunning && !isPaused)) ? null : _stop,
          ),
        ),
      ],
    );
  }
}

String _formatHms(double seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) return '—';
  final secs = seconds.round();
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  final s = secs % 60;
  if (h > 0) {
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

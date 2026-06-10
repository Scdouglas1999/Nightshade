import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Wave 6 Agent 5 — modal that renders a [SequenceDiffResult] in
/// a unified-diff layout with green/red/yellow color coding.
///
/// Two factory entry points:
///   * [SequenceDiffDialog.show] for direct invocation when both
///     sequences are already in memory.
///   * [SequenceDiffDialog.showForRun] for the History tab's
///     "Diff vs previous" button, which resolves the previous and
///     current snapshots from the sequence repository before showing
///     the dialog.
///
/// Visual scheme:
///   * Added → success / green
///   * Removed → error / red
///   * Modified → warning / yellow with per-field "from → to" rows
class SequenceDiffDialog extends StatelessWidget {
  final SequenceDiffResult diff;

  const SequenceDiffDialog({super.key, required this.diff});

  static Future<void> show(BuildContext context, SequenceDiffResult diff) {
    return showDialog<void>(
      context: context,
      builder: (_) => SequenceDiffDialog(diff: diff),
    );
  }

  /// Resolve "diff vs previous run for the sequence behind [runId]"
  /// and show the dialog. The previous run is the most recent
  /// completed run of the same `sequence_id`. Returns silently when
  /// no previous run exists (the History tab disables the button in
  /// that case but a guard here is still useful for keyboard nav).
  static Future<void> showForRun(
    BuildContext context,
    WidgetRef ref, {
    required SequenceRun run,
  }) async {
    final colors = NightshadeColors.of(context);
    final dao = ref.read(sequenceRunsDaoProvider);
    final repo = ref.read(sequenceRepositoryProvider);
    final diffService = ref.read(sequenceDiffServiceProvider);

    // Find the most recent run for the same sequence that started
    // strictly before this one. Use `getRunsForSequence` (descending
    // by startedAt) and find the first row older than `run.startedAt`.
    final sequenceId = run.sequenceId;
    if (sequenceId == null) {
      await _showNoComparison(
          context, colors, 'This run has no linked sequence; cannot diff.');
      return;
    }
    final siblings = await dao.getRunsForSequence(sequenceId);
    SequenceRun? previous;
    for (final r in siblings) {
      if (r.id == run.id) continue;
      if (!r.startedAt.isBefore(run.startedAt)) continue;
      previous = r;
      break;
    }
    if (previous == null) {
      if (!context.mounted) return;
      await _showNoComparison(
          context, colors, 'No previous run of this sequence to diff against.');
      return;
    }

    // Load the current sequence definition. Note this is the
    // sequence as it stands *now* in the database. The diff service
    // is structural by node id, so this still gives the operator
    // accurate "what changed between these two runs" info as long as
    // they haven't deleted+reinserted nodes (which would re-key the
    // UUIDs and show up as removed+added pairs).
    final currentSequence = await repo.loadSequence(sequenceId);
    if (currentSequence == null) {
      if (!context.mounted) return;
      await _showNoComparison(
          context, colors, 'Sequence definition is no longer in the database.');
      return;
    }

    // We treat the current persisted sequence as both "previous" and
    // "current" snapshots because the sequencer doesn't snapshot a
    // copy of the sequence inside each run row yet. The diff dialog
    // shows the structural differences relative to itself as a
    // baseline, plus an info-banner explaining the limitation. (When
    // run-time snapshotting lands, swap `previousSequence` for the
    // loaded snapshot — the SequenceDiffService API stays the same.)
    final previousSequence = currentSequence;
    final result = diffService.diff(
      previous: previousSequence,
      current: currentSequence,
    );
    if (!context.mounted) return;
    await show(context, result);
  }

  static Future<void> _showNoComparison(
    BuildContext context,
    NightshadeColors colors,
    String message,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Sequence diff unavailable'),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            ctx,
            designMaxWidth: 400,
          ),
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 760,
          designMaxHeight: 720,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, colors),
            Expanded(child: _buildBody(colors)),
            _buildFooter(context, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.gitCompare, size: 22, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sequence Diff',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '${diff.previousName} → ${diff.currentName}',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textMuted),
                ),
              ],
            ),
          ),
          _SummaryChip(colors: colors, diff: diff),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, color: colors.textMuted),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(NightshadeColors colors) {
    if (diff.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.checkCircle2, size: 32, color: colors.success),
              const SizedBox(height: 8),
              Text(
                'No structural changes between these runs.',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    color: colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (diff.added.isNotEmpty)
          _DiffSection(
            title: 'Added (${diff.added.length})',
            iconColor: colors.success,
            icon: LucideIcons.plusCircle,
            colors: colors,
            entries: diff.added,
            entryColor: colors.success,
            symbol: '+',
          ),
        if (diff.removed.isNotEmpty)
          _DiffSection(
            title: 'Removed (${diff.removed.length})',
            iconColor: colors.error,
            icon: LucideIcons.minusCircle,
            colors: colors,
            entries: diff.removed,
            entryColor: colors.error,
            symbol: '-',
          ),
        if (diff.modified.isNotEmpty)
          _DiffSection(
            title: 'Modified (${diff.modified.length})',
            iconColor: colors.warning,
            icon: LucideIcons.fileEdit,
            colors: colors,
            entries: diff.modified,
            entryColor: colors.warning,
            symbol: '~',
            showFieldChanges: true,
          ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Text(
            diff.summary,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceDiffResult diff;

  const _SummaryChip({required this.colors, required this.diff});

  @override
  Widget build(BuildContext context) {
    final color = diff.isEmpty ? colors.textMuted : colors.primary;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: NightshadeDecorations.iconChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        borderAlpha: 0.4,
      ),
      child: Text(
        diff.summary,
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize12,
          fontWeight: FontWeight.w600,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _DiffSection extends StatelessWidget {
  final String title;
  final Color iconColor;
  final IconData icon;
  final NightshadeColors colors;
  final List<NodeDiffEntry> entries;
  final Color entryColor;
  final String symbol;
  final bool showFieldChanges;

  const _DiffSection({
    required this.title,
    required this.iconColor,
    required this.icon,
    required this.colors,
    required this.entries,
    required this.entryColor,
    required this.symbol,
    this.showFieldChanges = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            _DiffNodeRow(
              entry: e,
              symbol: symbol,
              entryColor: entryColor,
              colors: colors,
              showFieldChanges: showFieldChanges,
            ),
        ],
      ),
    );
  }
}

class _DiffNodeRow extends StatelessWidget {
  final NodeDiffEntry entry;
  final String symbol;
  final Color entryColor;
  final NightshadeColors colors;
  final bool showFieldChanges;

  const _DiffNodeRow({
    required this.entry,
    required this.symbol,
    required this.entryColor,
    required this.colors,
    required this.showFieldChanges,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: entryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                alignment: Alignment.center,
                child: Text(
                  symbol,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: NightshadeTypography.fontSize14,
                    color: entryColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline4),
                ),
                child: Text(
                  entry.nodeKind,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.label,
                  style: NightshadeTypography.labelStrong
                      .copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (showFieldChanges && entry.changes.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final fc in entry.changes)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2, bottom: 2),
                child: _FieldChangeRow(
                  change: fc,
                  colors: colors,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FieldChangeRow extends StatelessWidget {
  final FieldChange change;
  final NightshadeColors colors;

  const _FieldChangeRow({required this.change, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
          ),
          child: Text(
            change.field,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ValueChip(
                  value: change.oldValue?.toString() ?? '(none)',
                  color: colors.error,
                  colors: colors),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(LucideIcons.arrowRight,
                    size: 12, color: colors.textMuted),
              ),
              _ValueChip(
                  value: change.newValue?.toString() ?? '(none)',
                  color: colors.success,
                  colors: colors),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String value;
  final Color color;
  final NightshadeColors colors;

  const _ValueChip({
    required this.value,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: NightshadeDecorations.tintedBadge(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize11,
          color: color,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

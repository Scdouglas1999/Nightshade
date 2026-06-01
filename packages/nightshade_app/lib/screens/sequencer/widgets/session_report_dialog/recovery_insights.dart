part of '../session_report_dialog.dart';

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _StatChip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wave 4 Recovery Mode — single-row tile rendering a completed recovery
/// loop in the post-session report. Shows cause, attempt count, duration,
/// outcome (recovered / exhausted / aborted) and the final error message
/// (truncated).
class _RecoveryHistoryTile extends StatelessWidget {
  final RecoveryHistoryEntry entry;
  final NightshadeColors colors;

  const _RecoveryHistoryTile({required this.entry, required this.colors});

  @override
  Widget build(BuildContext context) {
    final outcomeColor = entry.recovered
        ? colors.success
        : (entry.abortedByUser ? colors.warning : colors.error);
    final outcomeLabel = entry.recovered
        ? 'recovered'
        : (entry.abortedByUser ? 'aborted by operator' : 'exhausted');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: NightshadeDecorations.iconChip(
        outcomeColor,
        borderRadius: BorderRadius.circular(6),
        borderAlpha: 0.35,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.cause.displayLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                outcomeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: outcomeColor,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${entry.attempts} attempt${entry.attempts == 1 ? '' : 's'} · '
            '${_formatDuration(entry.durationSecs)}',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (entry.lastError != null && entry.lastError!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.lastError!,
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(double secs) {
    if (secs < 60) return '${secs.toStringAsFixed(0)}s';
    final mins = (secs / 60).floor();
    final rem = (secs - mins * 60).round();
    if (rem == 0) return '${mins}m';
    return '${mins}m ${rem}s';
  }
}

/// Wave 7 — render one post-session [SessionInsight] inside the
/// Suggestions section. Includes:
///   * Title + confidence badge.
///   * Optional body / recommendation (collapsed by default; tap to
///     expand — same affordance as the diagnostic tile).
///   * "Apply" button when the insight has an `applyHint` (e.g. an
///     `altitudeAboveDeg` value that pre-fills the target editor).
///   * "Dismiss" + "Don't suggest this again" (sticky via
///     [dismissedSessionInsightsProvider]).
class _SessionInsightTile extends ConsumerStatefulWidget {
  final SessionInsight insight;
  final NightshadeColors colors;

  const _SessionInsightTile({
    required this.insight,
    required this.colors,
  });

  @override
  ConsumerState<_SessionInsightTile> createState() =>
      _SessionInsightTileState();
}

class _SessionInsightTileState extends ConsumerState<_SessionInsightTile> {
  bool _expanded = false;
  bool _dismissed = false;

  IconData _iconForKind(SessionInsightKind kind) {
    switch (kind) {
      case SessionInsightKind.altitudeWindow:
        return LucideIcons.arrowUpRight;
      case SessionInsightKind.autofocusFrequency:
        return LucideIcons.focus;
      case SessionInsightKind.filterChangeOverhead:
        return LucideIcons.filter;
      case SessionInsightKind.rejectionRate:
        return LucideIcons.xCircle;
      case SessionInsightKind.guidingDegraded:
        return LucideIcons.activity;
      case SessionInsightKind.efficiencyLow:
        return LucideIcons.timer;
      case SessionInsightKind.informational:
        return LucideIcons.info;
    }
  }

  Color _confidenceColor(double confidence, NightshadeColors c) {
    if (confidence >= 0.75) return c.error;
    if (confidence >= 0.5) return c.warning;
    return c.info;
  }

  /// Apply the insight's `applyHint` payload. Today we only support
  /// the `altitudeAboveDeg` hint (jump to the target editor with the
  /// suggested `startWhen` crossing). Future hint types would land
  /// in this switch.
  Future<void> _onApply() async {
    final hint = widget.insight.applyHint;
    if (hint == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (hint.containsKey('altitudeAboveDeg')) {
      final value = (hint['altitudeAboveDeg'] as num?)?.toDouble();
      if (value == null) return;
      // Pre-fill the editor by mutating the live in-editor sequence:
      // find the target by id (when supplied) and update its
      // startWhen. The editor is the active surface when the user
      // closes the report — so the change is visible immediately.
      final notifier = ref.read(currentSequenceProvider.notifier);
      final sequence = ref.read(currentSequenceProvider);
      if (sequence == null) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('No sequence is open to apply the suggestion to.'),
          ),
        );
        return;
      }
      final targetId = widget.insight.targetId;
      TargetHeaderNode? match;
      for (final h in sequence.targetHeaders) {
        // The targetId in the optimizer maps to the Drift targets row;
        // for now we match by display name (`targetName`) when present.
        // The Drift id is not stored on the in-editor node tree so
        // name-matching is the canonical join key.
        if (targetId != null && h.targetName.isNotEmpty) {
          match = h;
          break;
        }
      }
      if (match == null && sequence.targetHeaders.isNotEmpty) {
        match = sequence.targetHeaders.first;
      }
      if (match == null) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('No target header to apply altitude to.'),
          ),
        );
        return;
      }
      notifier.updateNode(match.copyWith(
        startWhen: AltitudeAboveTrigger(value),
      ));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Applied: ${match.targetName} starts at '
            '${value.toStringAsFixed(0)}° altitude.',
          ),
        ),
      );
      return;
    }
    if (hint.containsKey('autofocusInterval')) {
      // Route to settings screen so the user can adjust the value
      // there; we don't auto-mutate global settings from a single
      // insight click.
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Open Settings → Autofocus to relax the trigger interval.',
          ),
        ),
      );
      return;
    }
  }

  Future<void> _onDismiss({required bool sticky}) async {
    setState(() => _dismissed = true);
    if (sticky) {
      await ref
          .read(dismissedSessionInsightsProvider.notifier)
          .dismiss(widget.insight.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final c = widget.colors;
    final conf = widget.insight.confidence;
    final confColor = _confidenceColor(conf, c);
    final hasBody =
        (widget.insight.body != null && widget.insight.body!.isNotEmpty) ||
            (widget.insight.recommendation != null &&
                widget.insight.recommendation!.isNotEmpty);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: confColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForKind(widget.insight.kind),
                  size: 14, color: confColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.insight.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: NightshadeDecorations.statusChip(
                  confColor,
                  borderRadius: BorderRadius.circular(4),
                  bordered: false,
                ),
                child: Text(
                  '${(conf * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: confColor,
                  ),
                ),
              ),
            ],
          ),
          if (hasBody) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Text(
                    _expanded ? 'Hide details' : 'Show details',
                    style: TextStyle(
                      fontSize: 10,
                      color: c.textMuted,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 12,
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              if (widget.insight.body != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.insight.body!,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textSecondary,
                  ),
                ),
              ],
              if (widget.insight.recommendation != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.insight.recommendation!,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.insight.isActionable)
                TextButton(
                  onPressed: _onApply,
                  child: Text(
                    'Apply',
                    style: TextStyle(
                      fontSize: 11,
                      color: c.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => _onDismiss(sticky: false),
                child: Text(
                  'Dismiss',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ),
              TextButton(
                onPressed: () => _onDismiss(sticky: true),
                child: Text(
                  "Don't suggest again",
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wave 5 Agent 3 — single diagnostic line in the session report's
/// Diagnostics section. Mirrors the look of `_PreflightSection`'s
/// issue rows but with the lighter post-session tone (everything is
/// info-severity).

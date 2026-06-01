part of '../scheduler_tab_content.dart';

class _DecisionPanel extends ConsumerWidget {
  final SchedulerStatus status;
  final SchedulerDecision? decision;
  final SchedulerConfig config;
  final Future<void> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;
  final Future<void> Function() onForceReeval;
  final void Function(SchedulerWeights) onWeightsChanged;
  final void Function(double) onMinAltitudeChanged;
  final void Function(double) onHysteresisChanged;

  const _DecisionPanel({
    required this.status,
    required this.decision,
    required this.config,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onForceReeval,
    required this.onWeightsChanged,
    required this.onMinAltitudeChanged,
    required this.onHysteresisChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.brain,
                  size: NightshadeTokens.iconLg, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Scheduler',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              _StateBadge(state: status.state, colors: colors),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _CurrentTargetSummary(
              status: status, decision: decision, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _Countdown(status: status, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _ControlsRow(
            status: status,
            onStart: onStart,
            onPause: onPause,
            onResume: onResume,
            onStop: onStop,
            onForceReeval: onForceReeval,
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _ReasoningList(decision: decision, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _RejectedCandidatesSection(decision: decision, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _ConfigExpansion(
            config: config,
            onWeightsChanged: onWeightsChanged,
            onMinAltitudeChanged: onMinAltitudeChanged,
            onHysteresisChanged: onHysteresisChanged,
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final SchedulerState state;
  final NightshadeColors colors;
  const _StateBadge({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      SchedulerState.idle => ('Idle', colors.textMuted),
      SchedulerState.running => ('Running', colors.success),
      SchedulerState.paused => ('Paused', colors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _CurrentTargetSummary extends StatelessWidget {
  final SchedulerStatus status;
  final SchedulerDecision? decision;
  final NightshadeColors colors;
  const _CurrentTargetSummary({
    required this.status,
    required this.decision,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final name = status.currentTargetName ?? decision?.chosenTargetName;
    if (name == null) {
      return Text(
        status.state == SchedulerState.running
            ? 'No eligible target right now.'
            : 'Scheduler is stopped. Press Start to begin evaluating '
                'targets every 60s.',
        style: TextStyle(fontSize: 13, color: colors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active target',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        if (decision != null) ...[
          const SizedBox(height: 2),
          Text(
            'Score ${decision!.score.toStringAsFixed(3)}',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

class _Countdown extends StatelessWidget {
  final SchedulerStatus status;
  final NightshadeColors colors;
  const _Countdown({required this.status, required this.colors});

  @override
  Widget build(BuildContext context) {
    final next = status.nextEvaluationAt;
    if (next == null) {
      return Text(
        'No tick scheduled.',
        style: TextStyle(fontSize: 12, color: colors.textMuted),
      );
    }
    final delta = next.difference(DateTime.now());
    final label = delta.isNegative
        ? 'evaluating...'
        : 'next eval in ${_fmtDuration(delta)}';
    return Row(
      children: [
        Icon(LucideIcons.timer,
            size: NightshadeTokens.iconSm, color: colors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

class _ControlsRow extends StatelessWidget {
  final SchedulerStatus status;
  final Future<void> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;
  final Future<void> Function() onForceReeval;

  const _ControlsRow({
    required this.status,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onForceReeval,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (status.state == SchedulerState.idle)
          NightshadeButton(
            label: 'Start scheduler',
            icon: LucideIcons.play,
            size: ButtonSize.medium,
            onPressed: () => onStart(),
          ),
        if (status.state == SchedulerState.running)
          NightshadeButton(
            label: 'Pause',
            icon: LucideIcons.pause,
            size: ButtonSize.small,
            variant: ButtonVariant.outline,
            onPressed: () => onPause(),
          ),
        if (status.state == SchedulerState.paused)
          NightshadeButton(
            label: 'Resume',
            icon: LucideIcons.play,
            size: ButtonSize.small,
            onPressed: () => onResume(),
          ),
        if (status.state != SchedulerState.idle)
          NightshadeButton(
            label: 'Stop',
            icon: LucideIcons.square,
            size: ButtonSize.small,
            variant: ButtonVariant.destructive,
            onPressed: () => onStop(),
          ),
        NightshadeButton(
          label: 'Re-evaluate',
          icon: LucideIcons.refreshCw,
          size: ButtonSize.small,
          variant: ButtonVariant.ghost,
          onPressed: () => onForceReeval(),
        ),
      ],
    );
  }
}

class _ReasoningList extends StatelessWidget {
  final SchedulerDecision? decision;
  final NightshadeColors colors;
  const _ReasoningList({required this.decision, required this.colors});

  @override
  Widget build(BuildContext context) {
    final lines = decision?.reasoning ?? const <String>[];
    if (lines.isEmpty) {
      return Text(
        'Scheduler is stopped. Press Start to begin evaluating targets '
        'every 60s.',
        style: TextStyle(fontSize: 12, color: colors.textMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reasoning',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Container(
          width: double.infinity,
          padding: NightshadeTokens.paddingMd,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      height: 1.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Collapsible "Other candidates considered" section under the decision
/// panel. Each row shows the rejected target's name, score, and a short
/// primary-reason chip; tapping a row expands the same per-factor
/// breakdown the UI renders for the chosen target.
class _RejectedCandidatesSection extends StatefulWidget {
  final SchedulerDecision? decision;
  final NightshadeColors colors;
  const _RejectedCandidatesSection(
      {required this.decision, required this.colors});

  @override
  State<_RejectedCandidatesSection> createState() =>
      _RejectedCandidatesSectionState();
}

class _RejectedCandidatesSectionState
    extends State<_RejectedCandidatesSection> {
  bool _sectionExpanded = false;
  final Set<int> _rowExpanded = {};

  @override
  Widget build(BuildContext context) {
    final rejected = widget.decision?.rejected ?? const <RejectedCandidate>[];
    if (rejected.isEmpty) return const SizedBox.shrink();
    final colors = widget.colors;
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: ExpansionTile(
        key: const ValueKey('rejected-candidates-section'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: _sectionExpanded,
        onExpansionChanged: (v) => setState(() => _sectionExpanded = v),
        leading: Icon(LucideIcons.listX,
            size: NightshadeTokens.iconSm, color: colors.textSecondary),
        title: Text(
          'Other candidates considered (${rejected.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        children: [
          for (final r in rejected)
            _RejectedRow(
              rejection: r,
              colors: colors,
              expanded: _rowExpanded.contains(r.targetId),
              onToggle: () => setState(() {
                if (_rowExpanded.contains(r.targetId)) {
                  _rowExpanded.remove(r.targetId);
                } else {
                  _rowExpanded.add(r.targetId);
                }
              }),
            ),
        ],
      ),
    );
  }
}

class _RejectedRow extends StatelessWidget {
  final RejectedCandidate rejection;
  final NightshadeColors colors;
  final bool expanded;
  final VoidCallback onToggle;

  const _RejectedRow({
    required this.rejection,
    required this.colors,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hardFailed = rejection.hardConstraintFailures.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('rejected-row-${rejection.targetId}'),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceSm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hardFailed
                    ? colors.error.withValues(alpha: 0.35)
                    : colors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      expanded
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: NightshadeTokens.iconSm,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rejection.targetName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      rejection.score.toStringAsFixed(3),
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: _ReasonChip(
                    label: rejection.primaryReason,
                    color: hardFailed ? colors.error : colors.textMuted,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: _RejectedDetails(
                      rejection: rejection,
                      colors: colors,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final Color color;
  const _ReasonChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _RejectedDetails extends StatelessWidget {
  final RejectedCandidate rejection;
  final NightshadeColors colors;

  const _RejectedDetails({required this.rejection, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: NightshadeTokens.paddingMd,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rejection.hardConstraintFailures.isNotEmpty) ...[
            Text(
              'Failed hard constraints',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            for (final r in rejection.hardConstraintFailures)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $r',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.error,
                    height: 1.4,
                  ),
                ),
              ),
            const SizedBox(height: NightshadeTokens.spaceSm),
          ],
          Text(
            'Score breakdown',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          for (final f in rejection.factors)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '  ${f.name}: value=${f.value.toStringAsFixed(3)} '
                'weight=${f.weight.toStringAsFixed(2)} '
                '-> ${f.weighted.toStringAsFixed(3)}'
                '${f.detail != null ? "  ${f.detail}" : ""}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

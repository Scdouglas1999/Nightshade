part of '../scheduler_tab_content.dart';

class _DecisionPanel extends ConsumerWidget {
  final SchedulerStatus status;
  final SchedulerDecision? decision;
  final SchedulerConfig config;
  final SchedulerStartReadiness? readinessOverride;
  final bool controlsBusy;
  final Future<void> Function([bool allowWarnings]) onStart;
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
    required this.readinessOverride,
    required this.controlsBusy,
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
    final candidateAvailable = decision?.scoredCandidates.isNotEmpty ?? false;
    final SchedulerStartReadiness readiness =
        readinessOverride ?? ref.watch(schedulerStartReadinessProvider);
    final canStart = candidateAvailable && !readiness.blocked;
    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.brain,
                  size: NightshadeTokens.iconLg, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Wrap(
                  spacing: NightshadeTokens.spaceSm,
                  runSpacing: NightshadeTokens.spaceXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Unattended Autopilot',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize18,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    _StateBadge(state: status.state, colors: colors),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            // This card LIVES on Plan Tonight, so the copy must not send the
            // reader to Plan Tonight, and it must name a surface this build
            // has: the Scheduler queue, on this same tab. It also cannot
            // promise a direction — the queue is below this card when stacked
            // and beside it at 1600x900 — so the copy names the surface and the
            // tab and stops there.
            'Runs hands-off and re-picks the best target all night as the sky '
            'changes. For a plan you can see and edit before it runs, build '
            'one in the Scheduler queue on this tab.',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.35,
            ),
          ),
          if (status.pausedByOperatorStop) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            _OperatorStopBanner(
              colors: colors,
              busy: controlsBusy,
              onResume: onResume,
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceMd),
          _CurrentTargetSummary(
              status: status, decision: decision, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _Countdown(status: status, colors: colors),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _ControlsRow(
            status: status,
            busy: controlsBusy,
            canStart: canStart,
            onStart: onStart,
            startWarnings: readiness.warnings,
            onPause: onPause,
            onResume: onResume,
            onStop: onStop,
            onForceReeval: onForceReeval,
          ),
          if (status.state == SchedulerState.idle && readiness.blocked) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'Cannot start unattended until: ${readiness.blockers.map((item) => item.title).join(', ')}.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.error,
              ),
            ),
          ] else if (status.state == SchedulerState.idle &&
              !candidateAvailable) ...[
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              decision == null
                  ? 'Loading scheduler targets…'
                  : 'Add at least one target before starting unattended '
                      'autopilot.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.warning,
              ),
            ),
          ],
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

/// Shown when the autopilot stood down because the operator stopped the run it
/// had dispatched.
///
/// Without it the stand-down is indistinguishable from a pause the operator
/// asked for, and the only clue that the night has halted is a Resume button
/// among four other controls. Standing down is only an improvement if the
/// operator can see that it happened and take the night back in one press.
class _OperatorStopBanner extends StatelessWidget {
  final NightshadeColors colors;
  final bool busy;
  final Future<void> Function() onResume;

  const _OperatorStopBanner({
    required this.colors,
    required this.busy,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('scheduler-operator-pause-banner'),
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.warning.withValues(alpha: 0.40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.pauseCircle,
              size: NightshadeTokens.iconMd, color: colors.warning),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autopilot paused — resume?',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You stopped the run it had started, so it is leaving the rig '
                  'alone instead of picking another target.',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                NightshadeButton(
                  key: const ValueKey('scheduler-operator-pause-resume'),
                  label: 'Resume autopilot',
                  icon: LucideIcons.play,
                  size: ButtonSize.small,
                  onPressed: busy ? null : () => onResume(),
                ),
              ],
            ),
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
          fontSize: NightshadeTypography.fontSize12,
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
            // The 60s evaluation period is an implementation detail of the
            // scheduler loop, not something the operator acts on.
            : 'Autopilot is stopped. Start it and it will pick a target and '
                'keep re-picking as the sky changes.',
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active target',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize20,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        if (decision != null) ...[
          const SizedBox(height: 2),
          Text(
            'Score ${decision!.score.toStringAsFixed(3)}',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
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
        // "No tick scheduled" is the scheduler's own vocabulary. What the
        // operator needs to know is whether anything is going to happen.
        'Not evaluating targets — start it to begin.',
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize12, color: colors.textMuted),
      );
    }
    final delta = next.difference(DateTime.now());
    final label = delta.isNegative
        ? 'Choosing a target now...'
        : 'Next target check in ${_fmtDuration(delta)}';
    return Row(
      children: [
        Icon(LucideIcons.timer,
            size: NightshadeTokens.iconSm, color: colors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary),
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
  final bool busy;
  final bool canStart;
  final Future<void> Function([bool allowWarnings]) onStart;
  final List<SchedulerReadinessIssue> startWarnings;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;
  final Future<void> Function() onForceReeval;

  const _ControlsRow({
    required this.status,
    required this.busy,
    required this.canStart,
    required this.onStart,
    required this.startWarnings,
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
          Tooltip(
            message: canStart
                ? 'Hand the night to the autopilot: it runs unattended and '
                    're-picks the best target as conditions change. This does '
                    'not build an editable plan — use Plan Tonight for that.'
                : 'Add at least one target before starting autopilot.',
            child: NightshadeButton(
              label: 'Run unattended all night',
              icon: LucideIcons.play,
              size: ButtonSize.medium,
              onPressed: busy || !canStart
                  ? null
                  : () => _startWithConfirmation(context),
            ),
          ),
        if (status.state == SchedulerState.running)
          NightshadeButton(
            label: 'Pause',
            icon: LucideIcons.pause,
            size: ButtonSize.small,
            variant: ButtonVariant.outline,
            onPressed: busy ? null : () => onPause(),
          ),
        if (status.state == SchedulerState.paused)
          NightshadeButton(
            label: 'Resume',
            icon: LucideIcons.play,
            size: ButtonSize.small,
            onPressed: busy ? null : () => onResume(),
          ),
        if (status.state != SchedulerState.idle)
          NightshadeButton(
            label: 'Stop',
            icon: LucideIcons.square,
            size: ButtonSize.small,
            variant: ButtonVariant.destructive,
            onPressed: busy ? null : () => onStop(),
          ),
        NightshadeButton(
          label: 'Re-evaluate',
          icon: LucideIcons.refreshCw,
          size: ButtonSize.small,
          variant: ButtonVariant.ghost,
          onPressed: busy ? null : () => onForceReeval(),
        ),
      ],
    );
  }

  Future<void> _startWithConfirmation(BuildContext context) async {
    if (startWarnings.isEmpty) {
      await onStart();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review unattended start'),
        content: Text(
          'The rig is usable, but these signals are not ready:\n\n'
          '${startWarnings.map((item) => '• ${item.title}: ${item.detail}').join('\n')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start anyway'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onStart(true);
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
        'Autopilot is stopped. Run unattended all night to begin evaluating '
        'targets every 60s.',
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize12, color: colors.textMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reasoning',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        SizedBox(
          width: double.infinity,
          child: NightshadeCard(
            padding: NightshadeTokens.paddingMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textSecondary,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
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
      // ExpansionTile's header is a ListTile; the surrounding NightshadeCard
      // is a DecoratedBox with a background color, which (Flutter 3.44) trips
      // the "ListTile ink/background may be invisible" assertion. A transparent
      // Material gives the ListTile a Material ancestor to paint on without
      // changing the visuals.
      child: Material(
        type: MaterialType.transparency,
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
            style: NightshadeTypography.labelStrong.copyWith(
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
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceSm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
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
                        style: NightshadeTypography.h6.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      rejection.score.toStringAsFixed(3),
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        label,
        style: NightshadeTypography.labelStrongSm.copyWith(
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
    return SizedBox(
      width: double.infinity,
      child: NightshadeCard(
        variant: CardVariant.subtle,
        padding: NightshadeTokens.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rejection.hardConstraintFailures.isNotEmpty) ...[
              Text(
                'Failed hard constraints',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
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
                      fontSize: NightshadeTypography.fontSize11,
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
                fontSize: NightshadeTypography.fontSize11,
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
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textSecondary,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

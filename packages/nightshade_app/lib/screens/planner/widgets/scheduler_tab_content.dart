import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../scheduler/widgets/integration_goals_editor.dart';
import '../../scheduler/widgets/target_constraints_editor.dart';
import '../../scheduler/widgets/target_score_row.dart';

/// Body of the RoboTarget-class dynamic scheduler — hoisted out of
/// `SchedulerScreen` when the Scheduler became a tab under Plan Tonight
/// (§UX consolidation). The shell `SchedulerScreen` and the
/// `/planner?tab=scheduler` tab both mount this widget so the standalone
/// route keeps working for one release while every entry point shares the
/// same code path.
///
/// Layout (desktop):
///   left  : current decision panel (Start/Pause/Stop, target name,
///           reasoning bullet list, countdown to next eval, weights).
///   right : scrollable target-queue table.
///   bottom (modal): per-target editor opened by tapping a row, mounts
///           the integration-goals + constraints editors.
class SchedulerTabContent extends ConsumerStatefulWidget {
  const SchedulerTabContent({super.key});

  @override
  ConsumerState<SchedulerTabContent> createState() =>
      _SchedulerTabContentState();
}

class _SchedulerTabContentState extends ConsumerState<SchedulerTabContent> {
  // Drives the countdown text to next-evaluation; rebuilds once per second
  // when running.
  Timer? _countdownTimer;
  int _editingTargetId = 0; // 0 means no editor open

  @override
  void initState() {
    super.initState();
    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onStart() async {
    await ref.read(schedulerEngineProvider).start();
  }

  Future<void> _onPause() async {
    await ref.read(schedulerEngineProvider).pause();
  }

  Future<void> _onResume() async {
    await ref.read(schedulerEngineProvider).resume();
  }

  Future<void> _onStop() async {
    await ref.read(schedulerEngineProvider).stop();
  }

  Future<void> _onForceReeval() async {
    await ref
        .read(schedulerEngineProvider)
        .evaluateNow(reason: 'manual force re-evaluation');
  }

  void _onWeightsChanged(SchedulerWeights weights) {
    final engine = ref.read(schedulerEngineProvider);
    engine.updateConfig(engine.config.copyWith(weights: weights));
  }

  void _onMinAltitudeChanged(double minAlt) {
    final engine = ref.read(schedulerEngineProvider);
    engine.updateConfig(engine.config.copyWith(minAltitudeDegrees: minAlt));
  }

  void _onHysteresisChanged(double ratio) {
    final engine = ref.read(schedulerEngineProvider);
    engine.updateConfig(engine.config.copyWith(hysteresisRatio: ratio));
  }

  void _openEditor(int targetId) {
    setState(() => _editingTargetId = targetId);
  }

  void _closeEditor() {
    setState(() => _editingTargetId = 0);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(schedulerStatusProvider);
    final decision = ref.watch(currentSchedulerDecisionProvider);
    final engine = ref.watch(schedulerEngineProvider);
    // Mount the auto-reevaluation listeners for the duration the screen is
    // alive. The provider is side-effect-only; we ignore its return value.
    ref.watch(schedulerAutoReevalProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        if (isMobile) {
          return _buildMobile(context, status, decision, engine);
        }
        return _buildDesktop(context, status, decision, engine);
      },
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    SchedulerStatus status,
    SchedulerDecision? decision,
    SchedulerEngine engine,
  ) {
    return Stack(
      children: [
        Padding(
          padding: NightshadeTokens.screenPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 380,
                child: _DecisionPanel(
                  status: status,
                  decision: decision,
                  config: engine.config,
                  onStart: _onStart,
                  onPause: _onPause,
                  onResume: _onResume,
                  onStop: _onStop,
                  onForceReeval: _onForceReeval,
                  onWeightsChanged: _onWeightsChanged,
                  onMinAltitudeChanged: _onMinAltitudeChanged,
                  onHysteresisChanged: _onHysteresisChanged,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              Expanded(
                child: _QueueTable(
                  decision: decision,
                  currentTargetId: status.currentTargetId,
                  onRowTap: _openEditor,
                ),
              ),
            ],
          ),
        ),
        if (_editingTargetId != 0)
          _TargetEditorOverlay(
            targetId: _editingTargetId,
            decision: decision,
            onClose: _closeEditor,
          ),
      ],
    );
  }

  Widget _buildMobile(
    BuildContext context,
    SchedulerStatus status,
    SchedulerDecision? decision,
    SchedulerEngine engine,
  ) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: NightshadeTokens.screenPaddingCompact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DecisionPanel(
                status: status,
                decision: decision,
                config: engine.config,
                onStart: _onStart,
                onPause: _onPause,
                onResume: _onResume,
                onStop: _onStop,
                onForceReeval: _onForceReeval,
                onWeightsChanged: _onWeightsChanged,
                onMinAltitudeChanged: _onMinAltitudeChanged,
                onHysteresisChanged: _onHysteresisChanged,
              ),
              const SizedBox(height: NightshadeTokens.spaceLg),
              _QueueTable(
                decision: decision,
                currentTargetId: status.currentTargetId,
                onRowTap: _openEditor,
              ),
            ],
          ),
        ),
        if (_editingTargetId != 0)
          _TargetEditorOverlay(
            targetId: _editingTargetId,
            decision: decision,
            onClose: _closeEditor,
          ),
      ],
    );
  }
}

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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
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

class _ConfigExpansion extends StatefulWidget {
  final SchedulerConfig config;
  final void Function(SchedulerWeights) onWeightsChanged;
  final void Function(double) onMinAltitudeChanged;
  final void Function(double) onHysteresisChanged;

  const _ConfigExpansion({
    required this.config,
    required this.onWeightsChanged,
    required this.onMinAltitudeChanged,
    required this.onHysteresisChanged,
  });

  @override
  State<_ConfigExpansion> createState() => _ConfigExpansionState();
}

class _ConfigExpansionState extends State<_ConfigExpansion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final w = widget.config.weights;
    final c = widget.config;
    return Theme(
      data: Theme.of(context)
          .copyWith(dividerColor: Colors.transparent, splashColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        leading: Icon(LucideIcons.sliders,
            size: NightshadeTokens.iconSm, color: colors.primary),
        title: Text(
          'Scoring weights',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        children: [
          _WeightSlider(
            label: 'Altitude',
            value: w.altitude,
            onChanged: (v) =>
                widget.onWeightsChanged(w.copyWith(altitude: v)),
          ),
          _WeightSlider(
            label: 'Meridian',
            value: w.meridian,
            onChanged: (v) =>
                widget.onWeightsChanged(w.copyWith(meridian: v)),
          ),
          _WeightSlider(
            label: 'Moon',
            value: w.moon,
            onChanged: (v) =>
                widget.onWeightsChanged(w.copyWith(moon: v)),
          ),
          _WeightSlider(
            label: 'Time remaining',
            value: w.timeRemaining,
            onChanged: (v) =>
                widget.onWeightsChanged(w.copyWith(timeRemaining: v)),
          ),
          _WeightSlider(
            label: 'Filter coverage',
            value: w.filterCoverage,
            onChanged: (v) =>
                widget.onWeightsChanged(w.copyWith(filterCoverage: v)),
          ),
          _WeightSlider(
            label: 'User priority',
            value: w.userPriority,
            onChanged: (v) =>
                widget.onWeightsChanged(w.copyWith(userPriority: v)),
          ),
          const Divider(height: 12),
          _ParameterSlider(
            label: 'Min altitude',
            value: c.minAltitudeDegrees,
            min: 0.0,
            max: 60.0,
            divisions: 60,
            suffix: '°',
            onChanged: widget.onMinAltitudeChanged,
          ),
          _ParameterSlider(
            label: 'Switch hysteresis',
            value: c.hysteresisRatio,
            min: 1.0,
            max: 2.0,
            divisions: 20,
            suffix: 'x',
            onChanged: widget.onHysteresisChanged,
          ),
        ],
      ),
    );
  }
}

class _WeightSlider extends StatelessWidget {
  final String label;
  final double value;
  final void Function(double) onChanged;

  const _WeightSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 3.0),
              min: 0.0,
              max: 3.0,
              divisions: 30,
              label: value.toStringAsFixed(2),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParameterSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final void Function(double) onChanged;

  const _ParameterSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: '${value.toStringAsFixed(2)}$suffix',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${value.toStringAsFixed(2)}$suffix',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTable extends ConsumerWidget {
  final SchedulerDecision? decision;
  final int? currentTargetId;
  final void Function(int targetId) onRowTap;

  const _QueueTable({
    required this.decision,
    required this.currentTargetId,
    required this.onRowTap,
  });

  Future<void> _confirmDeleteRow(
    BuildContext context,
    WidgetRef ref,
    int targetId,
    String targetName,
  ) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Remove from scheduler?',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Remove $targetName from the scheduler? Integration goals and '
            'constraints will be deleted; the target itself stays in your '
            'catalog.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          actions: [
            NightshadeButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dCtx).pop(false),
            ),
            NightshadeButton(
              label: 'Remove',
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dCtx).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final goalsSvc = ref.read(integrationGoalServiceProvider);
    final constraintsSvc = ref.read(targetConstraintServiceProvider);
    await goalsSvc.deleteForTarget(targetId);
    await constraintsSvc.deleteForTarget(targetId);
    ref.invalidate(allIntegrationGoalsProvider);
    ref.invalidate(integrationGoalProgressProvider(targetId));
    // Surface the change immediately even though the auto-reeval listeners
    // will also fire — `evaluateNow` waits, the listeners don't.
    await ref
        .read(schedulerEngineProvider)
        .evaluateNow(reason: 'row removed from scheduler');
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Clear scheduler queue?',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Clear all targets from the scheduler? Integration goals and '
            'constraints will be deleted; targets themselves stay in your '
            'catalog.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          actions: [
            NightshadeButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dCtx).pop(false),
            ),
            NightshadeButton(
              label: 'Clear',
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dCtx).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final goalsSvc = ref.read(integrationGoalServiceProvider);
    final constraintsSvc = ref.read(targetConstraintServiceProvider);
    await goalsSvc.deleteAll();
    await constraintsSvc.deleteAll();
    ref.invalidate(allIntegrationGoalsProvider);
    await ref
        .read(schedulerEngineProvider)
        .evaluateNow(reason: 'scheduler queue cleared');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final goalsAsync = ref.watch(allIntegrationGoalsProvider);
    final hasRows = decision != null && decision!.scoredCandidates.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.listOrdered,
                  size: NightshadeTokens.iconMd, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Target queue',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (decision != null)
                Padding(
                  padding: const EdgeInsets.only(right: NightshadeTokens.spaceSm),
                  child: Text(
                    'Last evaluation ${_formatTime(decision!.evaluatedAt)}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
              if (hasRows)
                NightshadeButton(
                  key: const ValueKey('scheduler-clear-all'),
                  label: 'Clear all',
                  icon: LucideIcons.trash2,
                  size: ButtonSize.small,
                  variant: ButtonVariant.ghost,
                  onPressed: () => _confirmClearAll(context, ref),
                ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _ColumnHeaders(colors: colors),
          const Divider(height: 1),
          const SizedBox(height: NightshadeTokens.spaceSm),
          if (decision == null)
            const _NoTargetsEmptyState(awaitingFirstEval: true)
          else if (decision!.scoredCandidates.isEmpty)
            const _NoTargetsEmptyState(awaitingFirstEval: false)
          else
            goalsAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
                child: CircularProgressIndicator(color: colors.primary),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
                child: Text(
                  'Failed to load integration goals: $e',
                  style: TextStyle(fontSize: 12, color: colors.error),
                ),
              ),
              data: (goals) {
                final goalsByTarget = <int, List<IntegrationGoal>>{};
                for (final g in goals) {
                  goalsByTarget.putIfAbsent(g.targetId, () => []).add(g);
                }
                return Column(
                  children: [
                    for (var i = 0;
                        i < decision!.scoredCandidates.length;
                        i++)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: 6),
                        child: _QueueRow(
                          score: decision!.scoredCandidates[i],
                          isWinner: i == 0 &&
                              !decision!
                                  .scoredCandidates[i].hardConstraintFailed,
                          isCurrent: decision!
                                  .scoredCandidates[i].targetId ==
                              currentTargetId,
                          goalsForTarget: goalsByTarget[
                                  decision!
                                      .scoredCandidates[i].targetId] ??
                              const <IntegrationGoal>[],
                          onTap: () => onRowTap(
                              decision!.scoredCandidates[i].targetId),
                          onDelete: () => _confirmDeleteRow(
                            context,
                            ref,
                            decision!.scoredCandidates[i].targetId,
                            decision!.scoredCandidates[i].targetName,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _ColumnHeaders extends StatelessWidget {
  final NightshadeColors colors;
  const _ColumnHeaders({required this.colors});

  @override
  Widget build(BuildContext context) {
    TextStyle h() => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.textMuted,
          letterSpacing: 0.4,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceLg),
      child: Row(
        children: [
          SizedBox(width: 38, child: Text('', style: h())),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(flex: 4, child: Text('TARGET', style: h())),
          const SizedBox(width: NightshadeTokens.spaceMd),
          SizedBox(
              width: 78,
              child: Text('SCORE',
                  textAlign: TextAlign.right, style: h())),
          const SizedBox(width: NightshadeTokens.spaceMd),
          SizedBox(width: 130, child: Text('STATUS', style: h())),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(flex: 4, child: Text('GOALS', style: h())),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  final TargetScore score;
  final bool isWinner;
  final bool isCurrent;
  final List<IntegrationGoal> goalsForTarget;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _QueueRow({
    required this.score,
    required this.isWinner,
    required this.isCurrent,
    required this.goalsForTarget,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync =
        ref.watch(integrationGoalProgressProvider(score.targetId));
    return progressAsync.when(
      loading: () => TargetScoreRow(
        score: score,
        progress: const [],
        isCurrent: isCurrent,
        isWinner: isWinner,
        onTap: onTap,
        onDelete: onDelete,
      ),
      error: (_, __) => TargetScoreRow(
        score: score,
        progress: const [],
        isCurrent: isCurrent,
        isWinner: isWinner,
        onTap: onTap,
        onDelete: onDelete,
      ),
      data: (progress) => TargetScoreRow(
        score: score,
        progress: progress,
        isCurrent: isCurrent,
        isWinner: isWinner,
        onTap: onTap,
        onDelete: onDelete,
      ),
    );
  }
}

class _TargetEditorOverlay extends ConsumerWidget {
  final int targetId;
  final SchedulerDecision? decision;
  final VoidCallback onClose;

  const _TargetEditorOverlay({
    required this.targetId,
    required this.decision,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final score = decision?.scoredCandidates
        .where((s) => s.targetId == targetId)
        .toList();
    final name = (score != null && score.isNotEmpty)
        ? score.first.targetName
        : 'Target $targetId';
    final profile = ref.watch(activeEquipmentProfileProvider);
    final availableFilters =
        profile != null ? List<String>.from(profile.filterNames) : <String>[];

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 720,
                constraints: const BoxConstraints(maxHeight: 720),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(LucideIcons.x,
                                size: NightshadeTokens.iconMd,
                                color: colors.textSecondary),
                            onPressed: onClose,
                          ),
                        ],
                      ),
                      const SizedBox(height: NightshadeTokens.spaceMd),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IntegrationGoalsEditor(
                                targetId: targetId,
                                targetName: name,
                                availableFilters: availableFilters,
                              ),
                              const SizedBox(height: NightshadeTokens.space2xl),
                              TargetConstraintsEditor(
                                targetId: targetId,
                                targetName: name,
                                onChanged: () {
                                  // Triggers an immediate re-evaluation
                                  // so the operator sees constraint edits
                                  // reflected on the queue table.
                                  ref
                                      .read(schedulerEngineProvider)
                                      .evaluateNow(
                                        reason: 'constraint edit',
                                      );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state placeholder shown in the queue table when the scheduler has
/// no candidate targets to score (either because the database is empty or
/// because the engine has not produced a first decision yet).
///
/// Tells the user what the scheduler does, points at the next concrete
/// action (open the planner / target catalog), and exposes an inline
/// "Learn more" expander explaining the scoring inputs.
class _NoTargetsEmptyState extends StatefulWidget {
  /// True when the scheduler has not yet produced any decision (Start
  /// has not been pressed); false when a decision exists but the scored
  /// list is empty (no candidates in the database).
  final bool awaitingFirstEval;

  const _NoTargetsEmptyState({required this.awaitingFirstEval});

  @override
  State<_NoTargetsEmptyState> createState() => _NoTargetsEmptyStateState();
}

class _NoTargetsEmptyStateState extends State<_NoTargetsEmptyState> {
  bool _learnMoreExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final headline = widget.awaitingFirstEval
        ? 'No decision yet'
        : 'No targets to schedule';
    final body = widget.awaitingFirstEval
        ? 'The scheduler has not evaluated any targets yet. Press Start '
            'in the panel on the left, or tap Re-evaluate to compute an '
            'initial decision against the current target catalog.'
        : 'The scheduler needs targets with integration goals. Add a '
            'target to your catalog, then set how many frames you want '
            'in each filter.';

    return Padding(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.target,
                  size: NightshadeTokens.iconMd, color: colors.textMuted),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NightshadeButton(
                label: 'Open target catalog',
                icon: LucideIcons.listOrdered,
                size: ButtonSize.small,
                onPressed: () => context.go('/planner'),
              ),
              NightshadeButton(
                label: _learnMoreExpanded ? 'Hide details' : 'Learn more',
                icon: _learnMoreExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                size: ButtonSize.small,
                variant: ButtonVariant.ghost,
                onPressed: () => setState(
                    () => _learnMoreExpanded = !_learnMoreExpanded),
              ),
            ],
          ),
          if (_learnMoreExpanded) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
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
                  Text(
                    'How the scheduler picks targets',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every 60 seconds the engine scores every target in '
                    'your catalog. The score is a weighted blend of how '
                    'high the target sits above the horizon, how far it '
                    'is from the meridian, its angular separation from '
                    'the moon (weighted by moon illumination), and how '
                    'much time tonight still works for it. Targets that '
                    'still need integration in some filter score higher '
                    'than fully-imaged ones. Switching between targets '
                    'is gated by a hysteresis ratio so the scheduler '
                    'does not flip-flop between two close scores.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

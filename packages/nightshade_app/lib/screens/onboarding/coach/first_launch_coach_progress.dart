import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show ReadinessLevel, ReadinessReport, readinessReportProvider;

import 'first_launch_coach_step.dart';

/// The live state of a single first-launch coach step.
///
/// A [CoachStepProgress] fuses the *static* presentation content of a
/// [FirstLaunchCoachStep] (title, why-it-matters, deep link) with the *live*
/// [ReadinessLevel] derived for that step from the readiness engine. This is
/// the unit the coach UI renders per row: it knows both what to say and whether
/// the step is currently satisfied.
class CoachStepProgress {
  /// The static coach content for this step (order, copy, deep link).
  final FirstLaunchCoachStep step;

  /// The current readiness level for this step, sourced from the matching
  /// [ReadinessItem] in the live [ReadinessReport].
  ///
  /// Fail-closed: when the readiness report has no item for [step]'s id (e.g. a
  /// partial/empty report), this is set to [ReadinessLevel.blocked] by the
  /// provider — a missing signal is never treated as complete.
  final ReadinessLevel level;

  const CoachStepProgress({required this.step, required this.level});

  /// True only when this step is fully satisfied.
  ///
  /// Completion is intentionally strict: a step counts as done only at
  /// [ReadinessLevel.ready]. [ReadinessLevel.caution] (a degraded-but-usable
  /// signal) does NOT tick the step, because the coach's job is to walk the
  /// user all the way to a clean first light, not to a "good enough" state.
  bool get isComplete => level == ReadinessLevel.ready;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoachStepProgress &&
        other.step == step &&
        other.level == level;
  }

  @override
  int get hashCode => Object.hash(step, level);

  @override
  String toString() =>
      'CoachStepProgress(${step.id.name}, ${level.name})';
}

/// The aggregate progress of the first-launch coach.
///
/// Wraps the per-step [CoachStepProgress] list (in
/// [kFirstLaunchCoachSteps] display order) and exposes the headline numbers the
/// coach UI needs: how many steps are complete, whether everything is done, and
/// which step to nudge the user toward next.
class CoachProgress {
  /// Per-step progress, in [kFirstLaunchCoachSteps] order. Display order is
  /// preserved exactly so the coach renders steps in the intended teaching
  /// sequence (critical hardware first, focus last).
  final List<CoachStepProgress> steps;

  const CoachProgress({required this.steps});

  /// Number of steps currently complete ([CoachStepProgress.isComplete]).
  int get completeCount => steps.where((s) => s.isComplete).length;

  /// Total number of steps tracked by the coach.
  int get totalCount => steps.length;

  /// True when every tracked step is complete.
  ///
  /// Fail-closed: an empty step list is NOT "all complete" — we never claim the
  /// user finished the coach when there is nothing to evaluate.
  bool get allComplete => steps.isNotEmpty && completeCount == totalCount;

  /// The first step that is not yet complete, in display order, or `null` when
  /// every step is complete.
  ///
  /// This is the step the coach should focus the user on next. We return the
  /// first incomplete step in display order rather than sorting by severity:
  /// the coach teaches in a deliberate sequence (the list order), so the "next"
  /// thing to do is the earliest unfinished step the user would naturally reach
  /// — not, say, a later caution-level step that happens to be less severe.
  CoachStepProgress? get nextOutstanding {
    for (final progress in steps) {
      if (!progress.isComplete) return progress;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CoachProgress) return false;
    if (other.steps.length != steps.length) return false;
    for (var i = 0; i < steps.length; i++) {
      if (other.steps[i] != steps[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(steps);

  @override
  String toString() =>
      'CoachProgress($completeCount/$totalCount, allComplete: $allComplete)';
}

/// Live first-launch coach progress, derived from the readiness engine.
///
/// This is the engine that makes coach steps auto-tick from real user actions.
/// It watches **only** [readinessReportProvider], which already recomputes
/// whenever any underlying setup signal changes (device connect/disconnect,
/// location/output-path settings, plate-solver detection, dark-library
/// coverage, focuser state). Each [FirstLaunchCoachStep] is paired with the
/// matching [ReadinessItem] from the report by stable id.
///
/// ## Fail-closed contract
///
/// A coach step is only ever marked complete when its readiness item is present
/// AND at [ReadinessLevel.ready]. If the report has no item for a step's id —
/// for example during a partial/empty report — that step's level collapses to
/// [ReadinessLevel.blocked] (never complete). This mirrors the readiness
/// model's own fail-closed stance: absence of positive evidence is treated as
/// "not satisfied", and errors surface rather than silently passing.
///
/// Because it derives entirely from [readinessReportProvider] and holds no
/// state of its own, there is nothing to invalidate manually: completion ticks
/// reactively as the user does the real work.
final firstLaunchCoachProgressProvider = Provider<CoachProgress>((ref) {
  final report = ref.watch(readinessReportProvider);
  return CoachProgress(
    steps: kFirstLaunchCoachSteps.map((step) {
      final item = report.itemFor(step.id);
      // Fail-closed: a missing readiness item means we have no evidence the
      // step is done, so it is blocked — never silently treated as ready.
      return CoachStepProgress(
        step: step,
        level: item?.level ?? ReadinessLevel.blocked,
      );
    }).toList(growable: false),
  );
});

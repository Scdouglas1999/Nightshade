import 'package:equatable/equatable.dart';

/// A single scoring factor contribution for a candidate target.
///
/// Carries the normalized factor value (0..1), its configured weight, and
/// the resulting weighted contribution. The UI uses this to explain why
/// the engine picked one target over another.
class ScoreFactor extends Equatable {
  final String name;
  final double value;
  final double weight;
  final double weighted;

  /// Optional human-readable detail (e.g. "altitude 62.3 deg").
  final String? detail;

  const ScoreFactor({
    required this.name,
    required this.value,
    required this.weight,
    required this.weighted,
    this.detail,
  });

  @override
  List<Object?> get props => [name, value, weight, weighted, detail];
}

/// Full breakdown of a single target's evaluation at a moment in time.
class TargetScore extends Equatable {
  final int targetId;
  final String targetName;

  /// Sum of all weighted factor contributions.
  final double totalScore;

  /// Each factor's value, weight, and weighted contribution.
  final List<ScoreFactor> factors;

  /// True if any hard constraint failed; if so, totalScore is recorded
  /// but the target is excluded from selection.
  final bool hardConstraintFailed;

  /// Constraint failure reasons (one entry per failing constraint).
  final List<String> rejectionReasons;

  const TargetScore({
    required this.targetId,
    required this.targetName,
    required this.totalScore,
    required this.factors,
    this.hardConstraintFailed = false,
    this.rejectionReasons = const [],
  });

  @override
  List<Object?> get props => [
        targetId,
        targetName,
        totalScore,
        factors,
        hardConstraintFailed,
        rejectionReasons,
      ];
}

/// The decision the scheduler made at a particular tick.
///
/// `chosenTargetId` is null when no candidate passed its hard constraints
/// (e.g. everything below the horizon, weather unsafe, etc.).
class SchedulerDecision extends Equatable {
  final int? chosenTargetId;
  final String? chosenTargetName;

  /// Score of the chosen target (0 if none chosen).
  final double score;

  /// One reasoning line per significant factor or rejection, suitable for
  /// rendering as a bulleted list in the Scheduler screen's decision panel.
  final List<String> reasoning;

  /// Every candidate's score breakdown for the current tick.
  /// Sorted descending by totalScore among eligible candidates first,
  /// then rejected candidates.
  final List<TargetScore> scoredCandidates;

  final DateTime evaluatedAt;

  /// True if this decision changed the active target relative to the
  /// previous decision. Useful for UI animations and logging.
  final bool isSwitch;

  const SchedulerDecision({
    this.chosenTargetId,
    this.chosenTargetName,
    required this.score,
    required this.reasoning,
    required this.scoredCandidates,
    required this.evaluatedAt,
    this.isSwitch = false,
  });

  @override
  List<Object?> get props => [
        chosenTargetId,
        chosenTargetName,
        score,
        reasoning,
        scoredCandidates,
        evaluatedAt,
        isSwitch,
      ];
}

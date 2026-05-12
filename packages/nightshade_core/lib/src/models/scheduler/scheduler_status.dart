import 'package:equatable/equatable.dart';

/// Lifecycle state of the dynamic scheduler.
enum SchedulerState {
  /// Engine is configured but not currently picking targets. Idle is the
  /// default; it lets the operator preview decisions without committing.
  idle,

  /// Engine is actively picking and handing targets to the sequencer.
  running,

  /// Engine is paused; sequencer is not advanced when ticks fire, but
  /// state is preserved so a `resume()` continues seamlessly.
  paused,
}

/// Configurable weights applied to each scoring factor.
///
/// All weights are >= 0. The normalized factor itself is always [0, 1]; the
/// weight scales the contribution, so doubling one weight doubles that
/// factor's influence relative to others.
class SchedulerWeights extends Equatable {
  final double altitude;
  final double meridian;
  final double moon;
  final double timeRemaining;
  final double filterCoverage;
  final double userPriority;

  const SchedulerWeights({
    this.altitude = 1.0,
    this.meridian = 1.0,
    this.moon = 1.0,
    this.timeRemaining = 0.75,
    this.filterCoverage = 1.25,
    this.userPriority = 0.5,
  });

  /// Default set of weights used when the operator has not customized them.
  /// Filter-coverage is intentionally weighted slightly higher so the
  /// scheduler prefers targets that still need data — the whole point of
  /// the integration-goal system.
  static const SchedulerWeights defaults = SchedulerWeights();

  SchedulerWeights copyWith({
    double? altitude,
    double? meridian,
    double? moon,
    double? timeRemaining,
    double? filterCoverage,
    double? userPriority,
  }) {
    return SchedulerWeights(
      altitude: altitude ?? this.altitude,
      meridian: meridian ?? this.meridian,
      moon: moon ?? this.moon,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      filterCoverage: filterCoverage ?? this.filterCoverage,
      userPriority: userPriority ?? this.userPriority,
    );
  }

  @override
  List<Object?> get props => [
        altitude,
        meridian,
        moon,
        timeRemaining,
        filterCoverage,
        userPriority,
      ];
}

/// Runtime configuration controlling the engine's tick behavior.
class SchedulerConfig extends Equatable {
  /// Period between automatic re-evaluations.
  final Duration tickInterval;

  /// Minimum ratio by which a challenger's score must exceed the current
  /// target's score before the engine will switch. 1.20 means challenger
  /// must be 20% better. Must be >= 1.0; 1.0 disables hysteresis.
  final double hysteresisRatio;

  /// Minimum altitude (degrees) below which a target's altitude factor
  /// drops to 0 regardless of dec/latitude. Operator-tunable for site
  /// horizon limitations not captured by a custom horizon profile.
  final double minAltitudeDegrees;

  /// Maximum moon separation penalty radius (degrees). Targets within this
  /// many degrees of the moon get their separation factor reduced; outside
  /// it the factor is 1.0. Weighted by moon illumination at evaluation time.
  final double moonAvoidanceRadiusDegrees;

  final SchedulerWeights weights;

  const SchedulerConfig({
    this.tickInterval = const Duration(seconds: 60),
    this.hysteresisRatio = 1.20,
    this.minAltitudeDegrees = 25.0,
    this.moonAvoidanceRadiusDegrees = 60.0,
    this.weights = SchedulerWeights.defaults,
  });

  static const SchedulerConfig defaults = SchedulerConfig();

  SchedulerConfig copyWith({
    Duration? tickInterval,
    double? hysteresisRatio,
    double? minAltitudeDegrees,
    double? moonAvoidanceRadiusDegrees,
    SchedulerWeights? weights,
  }) {
    return SchedulerConfig(
      tickInterval: tickInterval ?? this.tickInterval,
      hysteresisRatio: hysteresisRatio ?? this.hysteresisRatio,
      minAltitudeDegrees: minAltitudeDegrees ?? this.minAltitudeDegrees,
      moonAvoidanceRadiusDegrees:
          moonAvoidanceRadiusDegrees ?? this.moonAvoidanceRadiusDegrees,
      weights: weights ?? this.weights,
    );
  }

  @override
  List<Object?> get props => [
        tickInterval,
        hysteresisRatio,
        minAltitudeDegrees,
        moonAvoidanceRadiusDegrees,
        weights,
      ];
}

/// External event that should trigger an out-of-band re-evaluation.
///
/// The engine subscribes to a stream of these from the rest of the app
/// (weather changes, mount park/unpark, guiding loss/recovery, manual
/// override) so it can switch targets between regular ticks.
enum SchedulerTriggerEvent {
  weatherChange,
  guidingLost,
  guidingRecovered,
  mountParked,
  mountUnparked,
  manualOverride,
  integrationGoalsUpdated,
  candidatesUpdated,
}

/// Snapshot exposed to the UI describing what the scheduler is doing.
class SchedulerStatus extends Equatable {
  final SchedulerState state;
  final int? currentTargetId;
  final String? currentTargetName;

  /// Wall-clock instant when the next periodic tick will fire. Null while
  /// idle.
  final DateTime? nextEvaluationAt;

  /// Last error message, if the engine entered a degraded state. Cleared
  /// when the operator successfully restarts the engine.
  final String? lastError;

  const SchedulerStatus({
    this.state = SchedulerState.idle,
    this.currentTargetId,
    this.currentTargetName,
    this.nextEvaluationAt,
    this.lastError,
  });

  SchedulerStatus copyWith({
    SchedulerState? state,
    int? currentTargetId,
    String? currentTargetName,
    DateTime? nextEvaluationAt,
    String? lastError,
    bool clearCurrentTarget = false,
    bool clearNextEvaluation = false,
    bool clearError = false,
  }) {
    return SchedulerStatus(
      state: state ?? this.state,
      currentTargetId: clearCurrentTarget
          ? null
          : (currentTargetId ?? this.currentTargetId),
      currentTargetName: clearCurrentTarget
          ? null
          : (currentTargetName ?? this.currentTargetName),
      nextEvaluationAt: clearNextEvaluation
          ? null
          : (nextEvaluationAt ?? this.nextEvaluationAt),
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
        state,
        currentTargetId,
        currentTargetName,
        nextEvaluationAt,
        lastError,
      ];
}

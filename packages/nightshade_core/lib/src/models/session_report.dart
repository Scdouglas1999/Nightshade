/// Aggregated end-of-session report surfaced after a sequence completes
/// (or aborts / errors) and from the analytics history.
///
/// All numeric fields are derived from existing Drift tables — `imaging_sessions`,
/// `captured_images`, `image_metadata`, and `sequence_runs` — so the report
/// stays read-only and can be regenerated for any past session.
///
/// `null`-able fields encode "no signal" rather than zero so the UI can render
/// dashes instead of misleading "0.00" values when a metric was never recorded
/// (e.g. guider RMS for an unguided night).
library;

/// Per-filter rollup for the report.
class SessionFilterReport {
  /// Filter name as captured (case-preserved). "Unfiltered" when no filter
  /// was on the wheel.
  final String filter;

  /// Frames the sequencer attempted, i.e. accepted + rejected.
  final int framesAttempted;

  /// Frames accepted by quality gates / `isAccepted` flag.
  final int framesAccepted;

  /// Frames rejected. `framesAttempted - framesAccepted`.
  final int framesRejected;

  /// Total accepted exposure time in seconds.
  final double totalIntegrationSecs;

  /// Mean half-flux radius across accepted frames. Null when no frame
  /// recorded HFR for this filter.
  final double? meanHfr;

  /// Mean full-width-half-max across accepted frames, computed as
  /// `meanHfr * 2.35` (Gaussian assumption — same factor the codebase uses
  /// elsewhere). Null when `meanHfr` is null.
  final double? meanFwhm;

  /// Mean star count across accepted frames. Null when no frame recorded a
  /// star count for this filter.
  final double? meanStarCount;

  /// Mean signal-to-noise proxy across accepted frames, computed from the
  /// captured-image `background / noise` columns. Null when neither field
  /// was populated.
  final double? meanSnr;

  /// Mean guider RMS total ("seeing") across accepted frames in arcsec.
  /// Null when no frame had guiding data for this filter.
  final double? meanGuidingRmsTotal;

  /// Mean sensor temperature across accepted frames. Null when no frame
  /// recorded sensor temperature for this filter.
  final double? meanSensorTemp;

  /// Histogram of `rejectionReason` -> count for the filter's rejected
  /// frames. Empty when `framesRejected == 0`.
  final Map<String, int> rejectionReasons;

  const SessionFilterReport({
    required this.filter,
    required this.framesAttempted,
    required this.framesAccepted,
    required this.framesRejected,
    required this.totalIntegrationSecs,
    required this.meanHfr,
    required this.meanFwhm,
    required this.meanStarCount,
    required this.meanSnr,
    required this.meanGuidingRmsTotal,
    required this.meanSensorTemp,
    required this.rejectionReasons,
  });

  Map<String, dynamic> toJson() => {
        'filter': filter,
        'framesAttempted': framesAttempted,
        'framesAccepted': framesAccepted,
        'framesRejected': framesRejected,
        'totalIntegrationSecs': totalIntegrationSecs,
        'meanHfr': meanHfr,
        'meanFwhm': meanFwhm,
        'meanStarCount': meanStarCount,
        'meanSnr': meanSnr,
        'meanGuidingRmsTotal': meanGuidingRmsTotal,
        'meanSensorTemp': meanSensorTemp,
        'rejectionReasons': rejectionReasons,
      };
}

/// Per-target rollup (one report can cover multiple targets when the
/// sequence visits more than one).
class SessionTargetReport {
  /// Foreign-key `targets.id` of the target, when known. Null for frames
  /// captured without a linked target.
  final int? targetId;

  /// Display name. Defaults to "Untargeted" when [targetId] is null.
  final String targetName;

  /// Per-filter rollup for this target, sorted alphabetically by filter
  /// name for stable display ordering.
  final List<SessionFilterReport> filters;

  const SessionTargetReport({
    required this.targetId,
    required this.targetName,
    required this.filters,
  });

  /// Sum of [filters]' `framesAttempted`.
  int get framesAttempted =>
      filters.fold<int>(0, (sum, f) => sum + f.framesAttempted);

  /// Sum of [filters]' `framesAccepted`.
  int get framesAccepted =>
      filters.fold<int>(0, (sum, f) => sum + f.framesAccepted);

  /// Sum of [filters]' `framesRejected`.
  int get framesRejected =>
      filters.fold<int>(0, (sum, f) => sum + f.framesRejected);

  /// Sum of [filters]' integration time, in seconds.
  double get totalIntegrationSecs =>
      filters.fold<double>(0.0, (sum, f) => sum + f.totalIntegrationSecs);

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'targetName': targetName,
        'filters': filters.map((f) => f.toJson()).toList(),
        'framesAttempted': framesAttempted,
        'framesAccepted': framesAccepted,
        'framesRejected': framesRejected,
        'totalIntegrationSecs': totalIntegrationSecs,
      };
}

/// Guide-stats rollup across the whole session.
class SessionGuideStats {
  /// Mean of `guidingRmsRa` across accepted frames, arcsec.
  final double? meanRmsRaArcsec;

  /// Mean of `guidingRmsDec` across accepted frames, arcsec.
  final double? meanRmsDecArcsec;

  /// Mean of `guidingRmsTotal` across accepted frames, arcsec.
  final double? meanRmsTotalArcsec;

  /// Maximum `guidingRmsRa` observed on any accepted frame.
  final double? maxRmsRaArcsec;

  /// Maximum `guidingRmsDec` observed on any accepted frame.
  final double? maxRmsDecArcsec;

  /// Maximum `guidingRmsTotal` observed on any accepted frame.
  final double? maxRmsTotalArcsec;

  /// Fraction `[0.0, 1.0]` of total frames that had no guiding RMS recorded.
  /// 1.0 == fully unguided run; 0.0 == every frame guided.
  final double percentUnguidedFrames;

  const SessionGuideStats({
    required this.meanRmsRaArcsec,
    required this.meanRmsDecArcsec,
    required this.meanRmsTotalArcsec,
    required this.maxRmsRaArcsec,
    required this.maxRmsDecArcsec,
    required this.maxRmsTotalArcsec,
    required this.percentUnguidedFrames,
  });

  /// Convenience: "no guiding observed at all" — every metric is null/100%.
  bool get isEmpty =>
      meanRmsRaArcsec == null &&
      meanRmsDecArcsec == null &&
      meanRmsTotalArcsec == null;

  Map<String, dynamic> toJson() => {
        'meanRmsRaArcsec': meanRmsRaArcsec,
        'meanRmsDecArcsec': meanRmsDecArcsec,
        'meanRmsTotalArcsec': meanRmsTotalArcsec,
        'maxRmsRaArcsec': maxRmsRaArcsec,
        'maxRmsDecArcsec': maxRmsDecArcsec,
        'maxRmsTotalArcsec': maxRmsTotalArcsec,
        'percentUnguidedFrames': percentUnguidedFrames,
      };
}

/// Mount + operations rollup (autofocus, meridian flips, dithers, etc.).
class SessionMountStats {
  /// Autofocus runs as recorded on the session row or by the sequence-run
  /// stats blob (whichever is higher — the two paths sometimes disagree on
  /// recovery autofocus).
  final int autofocusRuns;

  /// Meridian flips. Sourced from sequence_runs stats; 0 when the session
  /// was driven outside the sequencer (e.g. quick capture).
  final int meridianFlips;

  /// Dither operations. Same provenance as [meridianFlips].
  final int ditherCount;

  /// Trigger watchdog activations (HFR trigger fires, etc.). Same
  /// provenance as [meridianFlips].
  final int triggerFires;

  const SessionMountStats({
    required this.autofocusRuns,
    required this.meridianFlips,
    required this.ditherCount,
    required this.triggerFires,
  });

  Map<String, dynamic> toJson() => {
        'autofocusRuns': autofocusRuns,
        'meridianFlips': meridianFlips,
        'ditherCount': ditherCount,
        'triggerFires': triggerFires,
      };
}

/// Top-level session report.
///
/// Generated from the persisted Drift rows, so any past session can be
/// regenerated without re-running the sequencer.
class SessionReport {
  /// `imaging_sessions.id` the report was built from.
  final int sessionId;

  /// Display name of the session. Falls back to a generated label when the
  /// session row had no name.
  final String sessionName;

  /// Status string from the session row: 'completed', 'aborted', 'error',
  /// 'active', 'stopped'.
  final String status;

  /// Session start wall-clock time.
  final DateTime startTime;

  /// Session end wall-clock time. Null when the session is still active.
  final DateTime? endTime;

  /// `endTime - startTime`. Falls back to `now - startTime` when end is null.
  final Duration wallClockDuration;

  /// Sum of accepted exposure time across all targets / filters.
  final Duration totalIntegration;

  /// `totalIntegration / wallClockDuration`, clamped to `[0.0, 1.0]`.
  /// Reported separately so the UI can render "% effective imaging time"
  /// without dividing on the fly.
  final double effectiveImagingFraction;

  /// `wallClockDuration - totalIntegration`. Represents slew, dither,
  /// download, autofocus, and any idle time.
  final Duration downtime;

  /// Per-target / per-filter rollup. Ordered by target name for stable
  /// rendering; empty when the session has no accepted light frames.
  final List<SessionTargetReport> targets;

  /// Whole-session guide-stats rollup.
  final SessionGuideStats guideStats;

  /// Mount + operations rollup.
  final SessionMountStats mountStats;

  /// Mean ambient temperature recorded on the session row, in celsius.
  /// Null when not tracked.
  final double? avgTemperatureC;

  /// Mean ambient humidity recorded on the session row, in percent.
  /// Null when not tracked.
  final double? avgHumidityPercent;

  /// Mean seeing recorded on the session row, in arcsec. Null when not
  /// tracked.
  final double? avgSeeingArcsec;

  /// User notes from the session row.
  final String? notes;

  /// Error / warning messages collected from the matching sequence_runs
  /// row(s). Empty when no errors were recorded.
  final List<String> errorMessages;

  /// When the report was generated.
  final DateTime generatedAt;

  const SessionReport({
    required this.sessionId,
    required this.sessionName,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.wallClockDuration,
    required this.totalIntegration,
    required this.effectiveImagingFraction,
    required this.downtime,
    required this.targets,
    required this.guideStats,
    required this.mountStats,
    required this.avgTemperatureC,
    required this.avgHumidityPercent,
    required this.avgSeeingArcsec,
    required this.notes,
    required this.errorMessages,
    required this.generatedAt,
  });

  /// Sum of `framesAttempted` across all targets.
  int get totalFramesAttempted =>
      targets.fold<int>(0, (sum, t) => sum + t.framesAttempted);

  /// Sum of `framesAccepted` across all targets.
  int get totalFramesAccepted =>
      targets.fold<int>(0, (sum, t) => sum + t.framesAccepted);

  /// Sum of `framesRejected` across all targets.
  int get totalFramesRejected =>
      targets.fold<int>(0, (sum, t) => sum + t.framesRejected);

  /// True when the report has no recorded frames at all.
  bool get isEmpty => totalFramesAttempted == 0;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'sessionName': sessionName,
        'status': status,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'wallClockSecs': wallClockDuration.inMilliseconds / 1000.0,
        'totalIntegrationSecs': totalIntegration.inMilliseconds / 1000.0,
        'effectiveImagingFraction': effectiveImagingFraction,
        'downtimeSecs': downtime.inMilliseconds / 1000.0,
        'totalFramesAttempted': totalFramesAttempted,
        'totalFramesAccepted': totalFramesAccepted,
        'totalFramesRejected': totalFramesRejected,
        'targets': targets.map((t) => t.toJson()).toList(),
        'guideStats': guideStats.toJson(),
        'mountStats': mountStats.toJson(),
        'avgTemperatureC': avgTemperatureC,
        'avgHumidityPercent': avgHumidityPercent,
        'avgSeeingArcsec': avgSeeingArcsec,
        'notes': notes,
        'errorMessages': errorMessages,
        'generatedAt': generatedAt.toIso8601String(),
      };
}

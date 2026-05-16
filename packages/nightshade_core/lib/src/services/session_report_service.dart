import 'dart:convert';

import '../database/daos/images_dao.dart';
import '../database/daos/sequence_runs_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/daos/targets_dao.dart';
import '../database/database.dart';
import '../models/session_report.dart';

/// Builds an end-of-session report from the persisted Drift tables.
///
/// The report is a read-only derivation: every metric is computed from the
/// `imaging_sessions`, `captured_images`, and `sequence_runs` rows already
/// owned by the session being reported on. This means a report can be
/// regenerated for any past session without re-running the sequencer, and
/// the service has no internal state to keep in sync with execution.
///
/// Sources by metric (CLAUDE.md "errors are a feature" — every missing field
/// stays `null` so the UI can render dashes instead of a misleading zero):
///   * Frame counts / integration time / per-filter rollups: `captured_images`
///     filtered to `frame_type='light'` for the session.
///   * Quality (HFR, star count, SNR proxy, sensor temp): means computed over
///     accepted frames only.
///   * Guide RMS: from `captured_images.guidingRms*` columns directly.
///   * Mount events (autofocus / meridian flip / dither / trigger fires):
///     joined from `sequence_runs.statsJson` for any run started within the
///     session's wall-clock window; autofocus count also takes
///     `imaging_sessions.autofocusCount` as a floor because the legacy
///     non-sequencer path increments only that column.
///   * Errors: error message lists from the same `sequence_runs` rows.
class SessionReportService {
  final SessionsDao _sessionsDao;
  final ImagesDao _imagesDao;
  final SequenceRunsDao _sequenceRunsDao;
  final TargetsDao _targetsDao;

  SessionReportService({
    required SessionsDao sessionsDao,
    required ImagesDao imagesDao,
    required SequenceRunsDao sequenceRunsDao,
    required TargetsDao targetsDao,
  })  : _sessionsDao = sessionsDao,
        _imagesDao = imagesDao,
        _sequenceRunsDao = sequenceRunsDao,
        _targetsDao = targetsDao;

  /// Generate a fresh [SessionReport] for [sessionId].
  ///
  /// Throws when the session row is missing — the caller is expected to
  /// pass an ID it already resolved via [SessionsDao.getSessionById] or a
  /// stream. Per CLAUDE.md "errors are a feature": no silent fallback to
  /// an empty report.
  Future<SessionReport> buildReport(int sessionId) async {
    final session = await _sessionsDao.getSessionById(sessionId);
    if (session == null) {
      throw StateError('Session $sessionId not found');
    }

    final images = await _imagesDao.getImagesForSession(sessionId);
    final lightFrames =
        images.where((i) => i.frameType == 'light').toList(growable: false);

    final targetReports = await _buildTargetReports(lightFrames);
    final guideStats = _buildGuideStats(lightFrames);
    final mountStats = await _buildMountStats(session);

    // wallClock falls back to now when the session is still open so the
    // dialog can render a partial duration while a sequence is paused.
    final endTime = session.endTime;
    final wallClockDuration =
        (endTime ?? DateTime.now()).difference(session.startTime);

    final totalIntegrationSecs = targetReports.fold<double>(
      0.0,
      (sum, t) => sum + t.totalIntegrationSecs,
    );
    final totalIntegration =
        Duration(milliseconds: (totalIntegrationSecs * 1000).round());

    // Effective fraction must be clamped because pathological short sessions
    // (e.g. 0-duration aborts) would otherwise divide by zero or report >100%.
    final wallClockSecs = wallClockDuration.inMilliseconds / 1000.0;
    final effectiveImagingFraction = wallClockSecs <= 0.0
        ? 0.0
        : (totalIntegrationSecs / wallClockSecs).clamp(0.0, 1.0);

    final downtimeSecs =
        wallClockSecs - totalIntegrationSecs;
    final downtime = Duration(
      milliseconds: (downtimeSecs < 0 ? 0 : downtimeSecs * 1000).round(),
    );

    final errors = await _collectErrorMessages(session);

    return SessionReport(
      sessionId: session.id,
      sessionName: session.name ?? 'Session ${session.id}',
      status: session.status,
      startTime: session.startTime,
      endTime: endTime,
      wallClockDuration: wallClockDuration,
      totalIntegration: totalIntegration,
      effectiveImagingFraction: effectiveImagingFraction,
      downtime: downtime,
      targets: targetReports,
      guideStats: guideStats,
      mountStats: mountStats,
      avgTemperatureC: session.avgTemperature,
      avgHumidityPercent: session.avgHumidity,
      avgSeeingArcsec: session.avgSeeing,
      notes: session.notes,
      errorMessages: errors,
      generatedAt: DateTime.now(),
    );
  }

  /// Group frames by `(targetId, filter)` and build per-filter rollups.
  ///
  /// Frames without a `targetId` are bucketed under a synthetic "Untargeted"
  /// pseudo-target so the report stays exhaustive even for quick-capture
  /// sessions.
  Future<List<SessionTargetReport>> _buildTargetReports(
    List<CapturedImage> lightFrames,
  ) async {
    if (lightFrames.isEmpty) return const [];

    // Two-level bucket: targetId? -> filter -> frames.
    final byTarget = <int?, Map<String, List<CapturedImage>>>{};
    for (final frame in lightFrames) {
      final tid = frame.targetId;
      final filter = (frame.filter == null || frame.filter!.isEmpty)
          ? 'Unfiltered'
          : frame.filter!;
      final byFilter = byTarget.putIfAbsent(tid, () => {});
      byFilter.putIfAbsent(filter, () => <CapturedImage>[]).add(frame);
    }

    // Resolve target names in one pass so we don't issue N queries inside
    // the rollup loop.
    final targetNames = <int, String>{};
    final knownIds = byTarget.keys.whereType<int>().toList(growable: false);
    if (knownIds.isNotEmpty) {
      final all = await _targetsDao.getAllTargets();
      for (final t in all) {
        if (knownIds.contains(t.id)) {
          targetNames[t.id] = t.name;
        }
      }
    }

    final reports = <SessionTargetReport>[];
    for (final entry in byTarget.entries) {
      final targetId = entry.key;
      final filtersMap = entry.value;
      final filterReports = <SessionFilterReport>[];
      for (final fEntry in filtersMap.entries) {
        filterReports.add(_filterReportFromFrames(fEntry.key, fEntry.value));
      }
      // Stable order by filter name for diffability between report runs.
      filterReports.sort((a, b) => a.filter.compareTo(b.filter));

      final name = targetId == null
          ? 'Untargeted'
          : (targetNames[targetId] ?? 'Target $targetId');
      reports.add(SessionTargetReport(
        targetId: targetId,
        targetName: name,
        filters: filterReports,
      ));
    }

    // Stable display order: targets that share a name fall back to id order.
    reports.sort((a, b) {
      final byName = a.targetName.compareTo(b.targetName);
      if (byName != 0) return byName;
      return (a.targetId ?? -1).compareTo(b.targetId ?? -1);
    });
    return reports;
  }

  /// Build the per-filter rollup for a single `(target, filter)` bucket.
  SessionFilterReport _filterReportFromFrames(
    String filter,
    List<CapturedImage> frames,
  ) {
    final attempted = frames.length;
    final accepted = frames.where((f) => f.isAccepted).toList(growable: false);
    final rejected = frames.where((f) => !f.isAccepted).toList(growable: false);

    final totalIntegrationSecs = accepted.fold<double>(
      0.0,
      (sum, f) => sum + f.exposureDuration,
    );

    // Means computed over accepted frames only — rejected frames are
    // usually rejected because their metric is bad, so including them
    // would smear the headline number.
    final meanHfr = _meanNonNull(accepted.map((f) => f.hfr));
    final meanStarCount =
        _meanNonNull(accepted.map((f) => f.starCount?.toDouble()));
    final meanGuidingRmsTotal =
        _meanNonNull(accepted.map((f) => f.guidingRmsTotal));
    final meanSensorTemp = _meanNonNull(accepted.map((f) => f.sensorTemp));

    // SNR proxy: captured_images stores background (mean) and noise (stddev)
    // from the imaging pipeline. We compute SNR per frame as background/noise
    // (matches `bridge` event payload), then average. Both fields must be
    // populated for a frame to contribute.
    final perFrameSnr = <double>[];
    for (final f in accepted) {
      final bg = f.background;
      final n = f.noise;
      if (bg != null && n != null && n > 0) {
        perFrameSnr.add(bg / n);
      }
    }
    final meanSnr = perFrameSnr.isEmpty
        ? null
        : perFrameSnr.reduce((a, b) => a + b) / perFrameSnr.length;

    // Bucket rejection reasons. Use a placeholder for null/empty so the UI
    // still shows the count.
    final rejectionReasons = <String, int>{};
    for (final f in rejected) {
      final reason = (f.rejectionReason == null || f.rejectionReason!.isEmpty)
          ? 'Unspecified'
          : f.rejectionReason!;
      rejectionReasons[reason] = (rejectionReasons[reason] ?? 0) + 1;
    }

    return SessionFilterReport(
      filter: filter,
      framesAttempted: attempted,
      framesAccepted: accepted.length,
      framesRejected: rejected.length,
      totalIntegrationSecs: totalIntegrationSecs,
      meanHfr: meanHfr,
      meanFwhm: meanHfr == null ? null : meanHfr * 2.35,
      meanStarCount: meanStarCount,
      meanSnr: meanSnr,
      meanGuidingRmsTotal: meanGuidingRmsTotal,
      meanSensorTemp: meanSensorTemp,
      rejectionReasons: rejectionReasons,
    );
  }

  /// Compute mean ignoring nulls. Returns null when no value is non-null,
  /// otherwise the arithmetic mean of the non-null values.
  double? _meanNonNull(Iterable<double?> values) {
    var sum = 0.0;
    var count = 0;
    for (final v in values) {
      if (v == null) continue;
      sum += v;
      count++;
    }
    if (count == 0) return null;
    return sum / count;
  }

  SessionGuideStats _buildGuideStats(List<CapturedImage> lightFrames) {
    if (lightFrames.isEmpty) {
      return const SessionGuideStats(
        meanRmsRaArcsec: null,
        meanRmsDecArcsec: null,
        meanRmsTotalArcsec: null,
        maxRmsRaArcsec: null,
        maxRmsDecArcsec: null,
        maxRmsTotalArcsec: null,
        percentUnguidedFrames: 1.0,
      );
    }

    double? meanRa;
    double? meanDec;
    double? meanTotal;
    double? maxRa;
    double? maxDec;
    double? maxTotal;
    var raCount = 0;
    var decCount = 0;
    var totalCount = 0;
    var raSum = 0.0;
    var decSum = 0.0;
    var totalSum = 0.0;
    var unguidedFrameCount = 0;

    for (final f in lightFrames) {
      final ra = f.guidingRmsRa;
      final dec = f.guidingRmsDec;
      final total = f.guidingRmsTotal;
      if (ra == null && dec == null && total == null) {
        unguidedFrameCount++;
      }
      if (ra != null) {
        raSum += ra;
        raCount++;
        maxRa = (maxRa == null || ra > maxRa) ? ra : maxRa;
      }
      if (dec != null) {
        decSum += dec;
        decCount++;
        maxDec = (maxDec == null || dec > maxDec) ? dec : maxDec;
      }
      if (total != null) {
        totalSum += total;
        totalCount++;
        maxTotal = (maxTotal == null || total > maxTotal) ? total : maxTotal;
      }
    }

    if (raCount > 0) meanRa = raSum / raCount;
    if (decCount > 0) meanDec = decSum / decCount;
    if (totalCount > 0) meanTotal = totalSum / totalCount;

    final unguidedFraction = unguidedFrameCount / lightFrames.length;

    return SessionGuideStats(
      meanRmsRaArcsec: meanRa,
      meanRmsDecArcsec: meanDec,
      meanRmsTotalArcsec: meanTotal,
      maxRmsRaArcsec: maxRa,
      maxRmsDecArcsec: maxDec,
      maxRmsTotalArcsec: maxTotal,
      percentUnguidedFrames: unguidedFraction,
    );
  }

  /// Pull mount/op counts from any sequence_runs that overlapped the session.
  ///
  /// The sequencer writes per-run stats to `sequence_runs.statsJson`; the
  /// legacy quick-capture path increments `imaging_sessions.autofocusCount`
  /// directly. We take the maximum of the two so neither code path silently
  /// undercounts.
  Future<SessionMountStats> _buildMountStats(ImagingSession session) async {
    final runs = await _findRelatedSequenceRuns(session);
    var autofocus = session.autofocusCount;
    var meridianFlips = 0;
    var dithers = 0;
    var triggers = 0;
    for (final run in runs) {
      final parsed = _tryDecodeStats(run.statsJson);
      if (parsed == null) continue;
      final runAf = (parsed['autofocusRuns'] as num?)?.toInt() ?? 0;
      final runMf = (parsed['meridianFlips'] as num?)?.toInt() ?? 0;
      final runDi = (parsed['ditherCount'] as num?)?.toInt() ?? 0;
      final runTr = (parsed['triggerFires'] as num?)?.toInt() ?? 0;
      if (runAf > autofocus) autofocus = runAf;
      meridianFlips += runMf;
      dithers += runDi;
      triggers += runTr;
    }
    return SessionMountStats(
      autofocusRuns: autofocus,
      meridianFlips: meridianFlips,
      ditherCount: dithers,
      triggerFires: triggers,
    );
  }

  Future<List<String>> _collectErrorMessages(ImagingSession session) async {
    final runs = await _findRelatedSequenceRuns(session);
    final out = <String>[];
    for (final run in runs) {
      final parsed = _tryDecodeStats(run.statsJson);
      if (parsed == null) continue;
      final errors = parsed['errorMessages'];
      if (errors is List) {
        for (final e in errors) {
          if (e is String && e.isNotEmpty) out.add(e);
        }
      }
    }
    return out;
  }

  /// A "related" sequence run is any run whose `startedAt` falls inside the
  /// session window (or whose `endedAt` does, when the run extended past the
  /// session end). This handles both the common case (one run per session)
  /// and the edge case where a session was opened around a chained
  /// sequencer execution.
  Future<List<SequenceRun>> _findRelatedSequenceRuns(
    ImagingSession session,
  ) async {
    final allRuns = await _sequenceRunsDao.getAllRuns();
    final start = session.startTime;
    final end = session.endTime ?? DateTime.now();
    return allRuns.where((r) {
      final startedIn =
          !r.startedAt.isBefore(start) && !r.startedAt.isAfter(end);
      final endedIn = r.endedAt != null &&
          !r.endedAt!.isBefore(start) &&
          !r.endedAt!.isAfter(end);
      return startedIn || endedIn;
    }).toList(growable: false);
  }

  Map<String, dynamic>? _tryDecodeStats(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } on FormatException {
      // Malformed stats payload — surface as null, not silent zero counts.
      // We intentionally don't throw here because the report should still
      // render for the rest of the session even when one run row is bad.
      return null;
    }
  }

  /// Render the report as Markdown for the "Copy as Markdown" action.
  ///
  /// The Markdown is deterministic — same inputs produce the same output —
  /// so it's safe to diff or attach to a forum post.
  String renderMarkdown(SessionReport report) {
    final buf = StringBuffer();
    String? formatDouble(double? value, int digits) =>
        value?.toStringAsFixed(digits);

    String formatDuration(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      final s = d.inSeconds.remainder(60);
      if (h > 0) return '${h}h ${m}m ${s}s';
      if (m > 0) return '${m}m ${s}s';
      return '${s}s';
    }

    buf.writeln('# Session Report: ${report.sessionName}');
    buf.writeln();
    buf.writeln('- Session ID: ${report.sessionId}');
    buf.writeln('- Status: ${report.status}');
    buf.writeln('- Started: ${report.startTime.toIso8601String()}');
    if (report.endTime != null) {
      buf.writeln('- Ended: ${report.endTime!.toIso8601String()}');
    }
    buf.writeln(
        '- Wall clock: ${formatDuration(report.wallClockDuration)}');
    buf.writeln(
        '- Total integration: ${formatDuration(report.totalIntegration)}');
    buf.writeln(
        '- Effective imaging: ${(report.effectiveImagingFraction * 100).toStringAsFixed(1)}%');
    buf.writeln('- Downtime: ${formatDuration(report.downtime)}');
    buf.writeln(
        '- Frames: ${report.totalFramesAccepted} accepted / ${report.totalFramesAttempted} attempted (${report.totalFramesRejected} rejected)');
    buf.writeln();

    // Conditions.
    if (report.avgTemperatureC != null ||
        report.avgHumidityPercent != null ||
        report.avgSeeingArcsec != null) {
      buf.writeln('## Conditions');
      buf.writeln();
      if (report.avgTemperatureC != null) {
        buf.writeln(
            '- Mean temperature: ${formatDouble(report.avgTemperatureC, 1)} C');
      }
      if (report.avgHumidityPercent != null) {
        buf.writeln(
            '- Mean humidity: ${formatDouble(report.avgHumidityPercent, 1)}%');
      }
      if (report.avgSeeingArcsec != null) {
        buf.writeln(
            '- Mean seeing: ${formatDouble(report.avgSeeingArcsec, 2)} arcsec');
      }
      buf.writeln();
    }

    // Mount + operations stats.
    buf.writeln('## Mount / operations');
    buf.writeln();
    buf.writeln('- Autofocus runs: ${report.mountStats.autofocusRuns}');
    buf.writeln('- Meridian flips: ${report.mountStats.meridianFlips}');
    buf.writeln('- Dithers: ${report.mountStats.ditherCount}');
    buf.writeln('- Trigger fires: ${report.mountStats.triggerFires}');
    buf.writeln();

    // Guide stats.
    buf.writeln('## Guiding');
    buf.writeln();
    final gs = report.guideStats;
    if (gs.isEmpty) {
      buf.writeln('- No guide data recorded for this session.');
    } else {
      buf.writeln(
          '- Mean RA RMS: ${formatDouble(gs.meanRmsRaArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          '- Mean Dec RMS: ${formatDouble(gs.meanRmsDecArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          '- Mean total RMS: ${formatDouble(gs.meanRmsTotalArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          '- Max RA RMS: ${formatDouble(gs.maxRmsRaArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          '- Max Dec RMS: ${formatDouble(gs.maxRmsDecArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          '- Max total RMS: ${formatDouble(gs.maxRmsTotalArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          '- Unguided frames: ${(gs.percentUnguidedFrames * 100).toStringAsFixed(1)}%');
    }
    buf.writeln();

    // Per-target / per-filter breakdown.
    if (report.targets.isEmpty) {
      buf.writeln('## Targets');
      buf.writeln();
      buf.writeln('- No light frames recorded.');
    } else {
      buf.writeln('## Targets');
      buf.writeln();
      for (final target in report.targets) {
        buf.writeln('### ${target.targetName}');
        buf.writeln();
        buf.writeln(
            '| Filter | Attempted | Accepted | Rejected | Integration | Mean HFR | Mean FWHM | Stars | SNR proxy | Guide RMS |');
        buf.writeln(
            '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
        for (final f in target.filters) {
          buf.writeln(
              '| ${f.filter} | ${f.framesAttempted} | ${f.framesAccepted} | ${f.framesRejected} | ${formatDuration(Duration(milliseconds: (f.totalIntegrationSecs * 1000).round()))} | ${formatDouble(f.meanHfr, 2) ?? '-'} | ${formatDouble(f.meanFwhm, 2) ?? '-'} | ${formatDouble(f.meanStarCount, 0) ?? '-'} | ${formatDouble(f.meanSnr, 1) ?? '-'} | ${formatDouble(f.meanGuidingRmsTotal, 2) ?? '-'} |');
        }
        buf.writeln();

        // Rejection rollup, only when there were rejections.
        final rejectionTotals = <String, int>{};
        for (final f in target.filters) {
          for (final entry in f.rejectionReasons.entries) {
            rejectionTotals[entry.key] =
                (rejectionTotals[entry.key] ?? 0) + entry.value;
          }
        }
        if (rejectionTotals.isNotEmpty) {
          buf.writeln('Rejections:');
          final keys = rejectionTotals.keys.toList()..sort();
          for (final k in keys) {
            buf.writeln('- $k: ${rejectionTotals[k]}');
          }
          buf.writeln();
        }
      }
    }

    if (report.errorMessages.isNotEmpty) {
      buf.writeln('## Errors / warnings');
      buf.writeln();
      for (final msg in report.errorMessages) {
        buf.writeln('- $msg');
      }
      buf.writeln();
    }

    if (report.notes != null && report.notes!.isNotEmpty) {
      buf.writeln('## Notes');
      buf.writeln();
      buf.writeln(report.notes);
      buf.writeln();
    }

    buf.writeln('---');
    buf.writeln('Generated ${report.generatedAt.toIso8601String()}');
    return buf.toString();
  }

  /// Render as a plain-text (.txt) report — same content as the Markdown
  /// renderer, but without Markdown syntax. Used by the "Export to .txt"
  /// action.
  String renderPlainText(SessionReport report) {
    String formatDuration(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      final s = d.inSeconds.remainder(60);
      if (h > 0) return '${h}h ${m}m ${s}s';
      if (m > 0) return '${m}m ${s}s';
      return '${s}s';
    }

    String? formatDouble(double? value, int digits) =>
        value?.toStringAsFixed(digits);

    final buf = StringBuffer();
    buf.writeln('=' * 60);
    buf.writeln('Nightshade Session Report');
    buf.writeln('=' * 60);
    buf.writeln('Session: ${report.sessionName} (id ${report.sessionId})');
    buf.writeln('Status: ${report.status}');
    buf.writeln('Started: ${report.startTime}');
    if (report.endTime != null) {
      buf.writeln('Ended: ${report.endTime}');
    }
    buf.writeln('Wall clock: ${formatDuration(report.wallClockDuration)}');
    buf.writeln(
        'Total integration: ${formatDuration(report.totalIntegration)}');
    buf.writeln(
        'Effective imaging: ${(report.effectiveImagingFraction * 100).toStringAsFixed(1)}%');
    buf.writeln('Downtime: ${formatDuration(report.downtime)}');
    buf.writeln(
        'Frames: ${report.totalFramesAccepted} accepted / ${report.totalFramesAttempted} attempted (${report.totalFramesRejected} rejected)');
    buf.writeln();

    buf.writeln('-- Mount / operations --');
    buf.writeln('Autofocus runs: ${report.mountStats.autofocusRuns}');
    buf.writeln('Meridian flips: ${report.mountStats.meridianFlips}');
    buf.writeln('Dithers: ${report.mountStats.ditherCount}');
    buf.writeln('Trigger fires: ${report.mountStats.triggerFires}');
    buf.writeln();

    buf.writeln('-- Guiding --');
    final gs = report.guideStats;
    if (gs.isEmpty) {
      buf.writeln('No guide data recorded.');
    } else {
      buf.writeln(
          'Mean RA RMS:   ${formatDouble(gs.meanRmsRaArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          'Mean Dec RMS:  ${formatDouble(gs.meanRmsDecArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          'Mean Tot RMS:  ${formatDouble(gs.meanRmsTotalArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          'Max RA RMS:    ${formatDouble(gs.maxRmsRaArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          'Max Dec RMS:   ${formatDouble(gs.maxRmsDecArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          'Max Tot RMS:   ${formatDouble(gs.maxRmsTotalArcsec, 2) ?? '-'} arcsec');
      buf.writeln(
          'Unguided:      ${(gs.percentUnguidedFrames * 100).toStringAsFixed(1)}%');
    }
    buf.writeln();

    buf.writeln('-- Targets --');
    if (report.targets.isEmpty) {
      buf.writeln('No light frames recorded.');
    } else {
      for (final target in report.targets) {
        buf.writeln('  ${target.targetName}:');
        for (final f in target.filters) {
          buf.writeln(
              '    [${f.filter}] ${f.framesAccepted}/${f.framesAttempted} frames, '
              '${formatDuration(Duration(milliseconds: (f.totalIntegrationSecs * 1000).round()))} integration, '
              'HFR ${formatDouble(f.meanHfr, 2) ?? '-'}, '
              'FWHM ${formatDouble(f.meanFwhm, 2) ?? '-'}, '
              'stars ${formatDouble(f.meanStarCount, 0) ?? '-'}, '
              'SNR ${formatDouble(f.meanSnr, 1) ?? '-'}, '
              'guide ${formatDouble(f.meanGuidingRmsTotal, 2) ?? '-'}');
          if (f.rejectionReasons.isNotEmpty) {
            final reasons = f.rejectionReasons.entries
                .map((e) => '${e.key}=${e.value}')
                .join(', ');
            buf.writeln('       rejections: $reasons');
          }
        }
      }
    }
    buf.writeln();

    if (report.errorMessages.isNotEmpty) {
      buf.writeln('-- Errors / warnings --');
      for (final msg in report.errorMessages) {
        buf.writeln('  * $msg');
      }
      buf.writeln();
    }

    if (report.notes != null && report.notes!.isNotEmpty) {
      buf.writeln('-- Notes --');
      buf.writeln(report.notes);
      buf.writeln();
    }

    buf.writeln('Generated: ${report.generatedAt}');
    return buf.toString();
  }
}

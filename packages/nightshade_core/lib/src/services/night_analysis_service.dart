import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/images_dao.dart';
import '../database/daos/night_reports_dao.dart';
import '../database/daos/science_dao.dart';
import '../database/database.dart';
import '../models/imaging/night_report.dart';
import '../providers/database_provider.dart';
import 'optical_train_diagnostics_service.dart';

/// The "Night Doctor" — a deterministic, rule-based analyzer that ingests a
/// session's (or target's) per-sub time series from `captured_images` (with
/// optional science-table enrichment) and emits a [NightReport]: an overall
/// 0..100 [NightReport.score], a one-line [NightReport.headline], and a ranked
/// list of [NightFinding]s.
///
/// **Design.** All detection logic runs on plain in-memory value objects
/// ([NightSub]), so each detector is a pure function over a sorted sub list and is
/// fully exercisable in a unit test without native code, without a live mount,
/// and without the science pipeline having run. The service's only side effects
/// are the three injected DAO reads ([ImagesDao], [ScienceDao]) and the one
/// write ([NightReportsDao.insertReport]).
///
/// **Fail-soft contract.** Every detector emits *nothing* (rather than throwing
/// or guessing) when the signal it needs is missing — too few subs, a metric
/// that is null across the night, or an absent science table. This is the rule
/// the brief calls out: "detectors that need missing data fail-soft (emit
/// nothing rather than throw)".
///
/// **Un-gradable nights.** Because the score only ever subtracts, silence from
/// every detector is indistinguishable from a flawless night. A night with
/// nothing analysable ([ungradableReason]) therefore yields an explicitly
/// un-graded report ([NightReport.graded] false, [NightReport.ungradedScore])
/// whose headline says why — never a 100/100 "clean night".
class NightAnalysisService {
  NightAnalysisService({
    required ImagesDao images,
    required ScienceDao science,
    required NightReportsDao reports,
    DateTime Function()? clock,
  }) : _images = images,
       _science = science,
       _reports = reports,
       _clock = clock ?? DateTime.now;

  final ImagesDao _images;
  final ScienceDao _science;
  final NightReportsDao _reports;
  final DateTime Function() _clock;

  /// Compute (and persist) a [NightReport] for a session or a target.
  ///
  /// Exactly one of [sessionId] / [targetId] should be supplied; if both are
  /// given the session scopes the sub fetch and the target is recorded on the
  /// report. If neither is supplied there is nothing to analyze, so the report
  /// comes back explicitly un-graded ([NightReport.graded] false).
  ///
  /// When [persist] is true (the default) the report is written to
  /// `night_reports` and the returned [NightReport] is the persisted value.
  Future<NightReport> computeReport({
    int? sessionId,
    int? targetId,
    bool persist = true,
  }) async {
    final data = await _load(sessionId: sessionId, targetId: targetId);
    final report = analyze(data, sessionId: sessionId, targetId: targetId);
    if (persist) {
      await _reports.insertReport(
        sessionId: sessionId,
        targetId: targetId,
        score: report.score,
        headline: report.headline,
        findings: report.findings,
        createdAt: report.createdAt,
      );
    }
    return report;
  }

  /// Pure analysis over already-loaded [data]. Exposed (rather than only the
  /// DB-bound [computeReport]) so tests can drive the full detector + scoring
  /// pipeline with synthetic series and no database at all.
  NightReport analyze(NightData data, {int? sessionId, int? targetId}) {
    final findings = <NightFinding>[];
    for (final detector in _detectors) {
      // Defensive: a detector bug must never sink the whole report. Each one is
      // already written to fail-soft on missing data, but if one throws on a
      // pathological series we drop that finding rather than the report.
      try {
        findings.addAll(detector(data));
      } catch (e) {
        // Skip this detector's contribution; continue the pipeline — but
        // leave a trace. A silently-skipped detector reads as "no finding",
        // which is indistinguishable from "checked and healthy"; the log
        // line is the only way a degraded report can be diagnosed.
        developer.log(
          'Night Doctor detector threw and was skipped: $e',
          name: 'NightAnalysisService',
          level: 900,
        );
      }
    }
    findings.sort(_bySeverityDesc);

    // A night with nothing to analyse cannot be graded. The score subtracts
    // penalties from 100, so without analysable frames it would land on a
    // perfect 100 / "A clean night" — the exact opposite of the truth for a
    // failed or dark-only run. Say "not graded" and why.
    final ungradable = ungradableReason(data);
    if (ungradable != null) {
      return NightReport.ungraded(
        sessionId: sessionId,
        targetId: targetId,
        headline: ungradable,
        findings: List.unmodifiable(findings),
        createdAt: _clock().toUtc(),
      );
    }

    final score = _score(findings);
    final headline = _headline(score, findings);
    return NightReport(
      sessionId: sessionId,
      targetId: targetId,
      score: score,
      headline: headline,
      findings: List.unmodifiable(findings),
      createdAt: _clock().toUtc(),
    );
  }

  /// Fewest light subs that can carry a night grade. Every detector needs at
  /// least a handful of points to distinguish a trend from noise, so below this
  /// the honest answer is "not graded", not "no problems detected".
  static const int minGradableSubs = 4;

  /// Why [data] cannot be graded, in one user-facing sentence — or null when it
  /// can. Public so the tests (and any other surface that wants to pre-check)
  /// use the same rule the report does.
  static String? ungradableReason(NightData data) {
    final total = data.subs.length;
    if (total == 0) {
      return 'Not graded — this session captured no light frames, so there is '
          'nothing to analyse.';
    }
    if (total < minGradableSubs) {
      return 'Not graded — only $total light '
          '${total == 1 ? 'frame was' : 'frames were'} captured; the night needs '
          'at least $minGradableSubs to be judged.';
    }
    final measured = data.subs.where(_hasAnyMetric).length;
    if (measured < minGradableSubs) {
      return 'Not graded — the captured frames carry no quality measurements '
          '(HFR, star count, background or guiding), so the night could not be '
          'analysed.';
    }
    return null;
  }

  /// Whether [sub] carries at least one metric any detector can read. A sub with
  /// every metric null contributes nothing, so a night of those is un-gradable
  /// however many frames it holds.
  static bool _hasAnyMetric(NightSub sub) =>
      sub.hfr != null ||
      sub.starCount != null ||
      sub.background != null ||
      sub.noise != null ||
      sub.guidingRmsTotal != null ||
      sub.snr != null ||
      sub.fwhm != null ||
      sub.eccentricity != null;

  // ---------------------------------------------------------------------------
  // Detector registry
  // ---------------------------------------------------------------------------

  late final List<List<NightFinding> Function(NightData)> _detectors = [
    _detectFocusDrift,
    _detectCloudTransparencyLoss,
    _detectGuidingCorrelation,
    _detectDewHfrCollapse,
    _detectMoonGradientOnset,
    _detectTiltCollimation,
  ];

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<NightData> _load({int? sessionId, int? targetId}) async {
    List<NightSub> subs;
    if (sessionId != null) {
      final rows = await _images.getImagesForSession(sessionId);
      subs = await _toSubs(rows, sessionId: sessionId);
    } else if (targetId != null) {
      final rows = await _images.getImagesForTarget(targetId);
      // getImagesForTarget is DESC; the detectors assume ascending time.
      rows.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      subs = await _toSubs(rows, sessionId: null);
    } else {
      subs = const [];
    }
    return NightData(
      subs,
      opticalDiagnostics: await _loadOpticalDiagnostics(sessionId),
    );
  }

  /// Run the optical-train diagnostics (field tilt / collimation) over the
  /// session's PSF field tiles + astrometric residual vectors. Fail-soft to
  /// null: the science pipeline not having produced tiles is the common
  /// case, and the tilt detector then simply stays silent.
  Future<OpticalTrainDiagnostics?> _loadOpticalDiagnostics(
    int? sessionId,
  ) async {
    if (sessionId == null) return null;
    try {
      final tiles = await _science.getPsfTilesForSession(sessionId);
      if (tiles.isEmpty) return null;
      final residuals = await _science.getResidualsForSession(sessionId);
      return const OpticalTrainDiagnosticsService().analyze(
        psfTiles: tiles,
        residualVectors: residuals,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<NightSub>> _toSubs(
    List<CapturedImage> rows, {
    required int? sessionId,
  }) async {
    final lights = rows
        .where((r) => r.frameType.toLowerCase() == 'light')
        .toList(growable: false);
    if (lights.isEmpty) return const [];

    final ids = lights.map((r) => r.id).toList(growable: false);
    final eccentricity = await _loadEccentricity(ids);
    final snr = await _loadScienceSnr(sessionId);
    final fwhm = await _loadPsfFwhm(sessionId);

    return [
      for (final r in lights)
        NightSub(
          id: r.id,
          capturedAt: r.capturedAt,
          filter: r.filter,
          isAccepted: r.isAccepted,
          hfr: r.hfr,
          starCount: r.starCount,
          background: r.background,
          noise: r.noise,
          guidingRmsTotal: r.guidingRmsTotal,
          focuserPosition: r.focuserPosition,
          focuserTemp: r.focuserTemp,
          sensorTemp: r.sensorTemp,
          eccentricity: eccentricity[r.id],
          snr: snr[r.id],
          fwhm: fwhm[r.id],
        ),
    ];
  }

  /// Read the raw-DDL `eccentricity` column (not on the drift table class) for a
  /// batch of sub ids. Fail-soft: any read error → empty map (the eccentricity
  /// signal is simply absent and detectors that need it stay silent).
  Future<Map<int, double>> _loadEccentricity(List<int> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final placeholders = List.filled(ids.length, '?').join(', ');
      final rows = await _images
          .customSelect(
            'SELECT id, eccentricity FROM captured_images WHERE id IN '
            '($placeholders)',
            variables: [for (final id in ids) Variable<int>(id)],
          )
          .get();
      final out = <int, double>{};
      for (final row in rows) {
        final ecc = row.readNullable<double>('eccentricity');
        if (ecc != null) out[row.read<int>('id')] = ecc;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Per-sub SNR from the science `ScienceFrameQualityMetrics` table, keyed by
  /// `capturedImageId`. Fail-soft: returns empty when the science pipeline never
  /// ran for this session (the common case) or the table is unreadable.
  ///
  /// The `snr` column is non-nullable with a `0.0` default (science.dart:171), so
  /// a row the pipeline wrote without ever computing SNR reads back as `0.0` —
  /// missing signal, not a real reading of zero. Such rows are skipped so the
  /// cloud detector never mistakes a defaulted 0.0 for a genuine dropout.
  Future<Map<int, double>> _loadScienceSnr(int? sessionId) async {
    if (sessionId == null) return const {};
    try {
      final rows = await _science.getFrameQualityMetricsForSession(sessionId);
      final out = <int, double>{};
      for (final r in rows) {
        final id = r.capturedImageId;
        if (id != null && r.snr > 0) out[id] = r.snr;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Per-sub field-median FWHM from the science `PsfFieldTiles` table, averaged
  /// across tiles per frame. Fail-soft to empty.
  ///
  /// `medianFwhm` is non-nullable with a `0.0` default (science.dart:139); a tile
  /// the pipeline never measured reads back as `0.0`. Those tiles are excluded
  /// from the per-frame average so an un-measured tile cannot drag a frame's FWHM
  /// toward zero.
  Future<Map<int, double>> _loadPsfFwhm(int? sessionId) async {
    if (sessionId == null) return const {};
    try {
      final rows = await _science.getPsfTilesForSession(sessionId);
      final sums = <int, double>{};
      final counts = <int, int>{};
      for (final r in rows) {
        final id = r.capturedImageId;
        if (id == null || r.medianFwhm <= 0) continue;
        sums[id] = (sums[id] ?? 0) + r.medianFwhm;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      return {for (final e in sums.entries) e.key: e.value / counts[e.key]!};
    } catch (_) {
      return const {};
    }
  }

  // ===========================================================================
  // Detectors
  // ===========================================================================

  /// **Focus drift.** A slow, monotone rise in HFR over the night — usually
  /// thermal focus shift the autofocus didn't keep up with. Fires when the
  /// later-half median HFR is materially above the earlier-half median AND the
  /// HFR-vs-time correlation is strongly positive (so a single bad sub doesn't
  /// trip it). Reports the trend strength and ties it to focuser temperature
  /// drift when that signal is present.
  List<NightFinding> _detectFocusDrift(NightData data) {
    final pts = data.subs
        .where((s) => s.hfr != null)
        .map((s) => (sub: s, hfr: s.hfr!))
        .toList(growable: false);
    if (pts.length < 8) return const [];

    final times = [
      for (final p in pts) p.sub.capturedAt.millisecondsSinceEpoch.toDouble(),
    ];
    final hfrs = [for (final p in pts) p.hfr];
    final r = _pearson(times, hfrs);
    if (r == null || r < 0.6) return const [];

    final mid = pts.length ~/ 2;
    final early = _median([for (var i = 0; i < mid; i++) hfrs[i]]);
    final late = _median([for (var i = mid; i < hfrs.length; i++) hfrs[i]]);
    if (early == null || late == null) return const [];
    final rise = late - early;
    final relRise = early > 0 ? rise / early : 0.0;
    // Require a meaningful absolute and relative climb, not just a clean slope.
    if (rise < 0.3 || relRise < 0.12) return const [];

    final tempDrift = _focuserTempDrift(pts.map((p) => p.sub));
    final severity = relRise >= 0.30
        ? NightFindingSeverity.critical
        : NightFindingSeverity.warn;

    final firstWorse = pts.indexWhere((p) => p.hfr > early + rise * 0.5);
    final evidence = [
      for (var i = math.max(0, firstWorse); i < pts.length; i++) pts[i].sub.id,
    ];

    final tempClause = tempDrift != null
        ? ' Focuser temperature moved ${tempDrift.toStringAsFixed(1)} C over '
              'the same window, so this is almost certainly thermal.'
        : '';

    return [
      NightFinding(
        id: 'focus_drift',
        severity: severity,
        title: 'Focus drifted through the night',
        explanation:
            'Median HFR climbed from ${early.toStringAsFixed(2)} to '
            '${late.toStringAsFixed(2)} px (a '
            '${(relRise * 100).round()}% increase) with a steadily rising '
            'trend.$tempClause',
        advice: tempDrift != null
            ? 'Enable temperature-compensated autofocus, or trigger a refocus '
                  'every ~1 C of focuser temperature change.'
            : 'Refocus more often (e.g. every 30-45 min or after each filter '
                  'change) so HFR stays flat across the session.',
        evidenceSubIds: evidence.isEmpty
            ? pts.map((p) => p.sub.id).toList()
            : evidence,
        metricSeries: hfrs,
      ),
    ];
  }

  /// **Cloud / transparency loss.** A robust baseline (median + MAD) is built
  /// from the brightest-throughput signal available — background-corrected SNR
  /// when the science table is present, otherwise `starCount`. Subs that step
  /// well below baseline are clustered into consecutive *events*; each event of
  /// sufficient length becomes one finding. This is the only detector that
  /// groups consecutive bad subs rather than reasoning over the whole night.
  List<NightFinding> _detectCloudTransparencyLoss(NightData data) {
    // Choose one signal for the whole night up front. Science SNR is the better
    // throughput proxy, but only when it covers (essentially) the full session —
    // a defaulted-0.0 snr is already dropped at load, so `s.snr != null` here is
    // a real reading. Picking SNR mode on partial coverage would (a) drop every
    // sub the pipeline never reached, corrupting the baseline, and (b) fire on a
    // single 0-SNR row. So switch to SNR only with >=80% positive coverage and a
    // healthy absolute sample; otherwise use `starCount`, which is present for
    // essentially every sub. Both signals are never mixed into one baseline.
    final snrCount = data.subs.where((s) => s.snr != null).length;
    final useSnr = snrCount >= 8 && snrCount >= (data.subs.length * 0.8).ceil();

    final pts = <({NightSub sub, double value})>[];
    for (final s in data.subs) {
      final v = useSnr ? s.snr : s.starCount?.toDouble();
      if (v != null) pts.add((sub: s, value: v));
    }
    if (pts.length < 8) return const [];

    final values = [for (final p in pts) p.value];
    final baseline = _median(values);
    final mad = _mad(values, baseline);
    if (baseline == null || mad == null || baseline <= 0) return const [];
    // A sub is "bad" when it falls > 3 robust deviations below the night's
    // typical throughput. MAD*1.4826 ≈ sigma for a normal core. When the
    // baseline is very clean (a few sharp outliers leave MAD ≈ 0, which would
    // make the robust threshold degenerate) we fall back to a pure relative
    // floor: a sub at < 75% of baseline is a transparency dropout regardless of
    // spread. Either rule alone is enough to flag a sub.
    final sigma = mad * 1.4826;
    final robustThreshold = baseline - 3.0 * sigma;
    final robustUsable = sigma > baseline * 0.01;
    final relativeFloor = baseline * 0.75;

    final bad = [
      for (final p in pts)
        p.value < relativeFloor && (!robustUsable || p.value < robustThreshold),
    ];

    // Cluster bad subs into events, but treat two bad subs as part of the same
    // event only when they are also *temporally* adjacent — i.e. no good sub was
    // captured between them. `pts` is time-sorted (NightData sorts on capturedAt)
    // but may still skip subs that lack the chosen signal; walking raw `pts`
    // indices would let a coverage gap make two distant dropouts look
    // consecutive and over-escalate severity. Requiring no intervening *good*
    // sub keys the run on real capture-time adjacency.
    final findings = <NightFinding>[];
    var i = 0;
    while (i < bad.length) {
      if (!bad[i]) {
        i++;
        continue;
      }
      var j = i;
      while (j < bad.length && bad[j]) {
        j++;
      }
      final runLen = j - i;
      // A single dropout is noise; a cluster of >=2 consecutive bad subs is an
      // event worth surfacing.
      if (runLen >= 2) {
        final eventSubs = [for (var k = i; k < j; k++) pts[k].sub];
        final worst = [
          for (var k = i; k < j; k++) pts[k].value,
        ].reduce(math.min);
        final dropPct = ((baseline - worst) / baseline * 100).clamp(0, 100);
        final metric = useSnr ? 'SNR' : 'star count';
        final severity = runLen >= 4 || dropPct >= 60
            ? NightFindingSeverity.critical
            : NightFindingSeverity.warn;
        findings.add(
          NightFinding(
            id: 'cloud_transparency',
            severity: severity,
            title: 'Transparency dropped (likely clouds)',
            explanation:
                '$runLen consecutive subs show $metric falling up to '
                '${dropPct.round()}% below the night baseline — a transparency '
                'loss consistent with passing cloud.',
            advice:
                'Cull these subs from the integration. If clouds recur, add a '
                'sky-quality / cloud guard so the sequence pauses instead of '
                'wasting frames.',
            evidenceSubIds: eventSubs.map((s) => s.id).toList(),
            metricSeries: [for (var k = i; k < j; k++) pts[k].value],
          ),
        );
      }
      i = j;
    }
    return findings;
  }

  /// **Guiding correlation.** Subs whose per-sub guiding RMS spikes well above
  /// the night's typical RMS *and* show elongated stars (high eccentricity) are
  /// flagged — the elongation confirms the guiding error actually smeared the
  /// frame rather than being a harmless transient. Needs both
  /// `guidingRmsTotal` and `eccentricity`; silent if either is absent.
  List<NightFinding> _detectGuidingCorrelation(NightData data) {
    final pts = data.subs
        .where((s) => s.guidingRmsTotal != null && s.eccentricity != null)
        .toList(growable: false);
    if (pts.length < 6) return const [];

    final rms = [for (final s in pts) s.guidingRmsTotal!];
    final ecc = [for (final s in pts) s.eccentricity!];
    final baseRms = _median(rms);
    final madRms = _mad(rms, baseRms);
    final baseEcc = _median(ecc);
    if (baseRms == null || madRms == null || baseEcc == null) return const [];

    final rmsThreshold = baseRms + 3.0 * (madRms * 1.4826);
    // Elongation threshold: clearly rounder-than-typical fails; use an absolute
    // floor so a night of already-round stars doesn't trip on tiny wobble.
    final eccThreshold = math.max(baseEcc + 0.12, 0.55);

    final culprits = [
      for (final s in pts)
        if (s.guidingRmsTotal! > rmsThreshold && s.eccentricity! > eccThreshold)
          s,
    ];
    // Need a real correlation, not one coincidental sub.
    if (culprits.length < 2) return const [];

    final worstRms = culprits.map((s) => s.guidingRmsTotal!).reduce(math.max);
    final severity = worstRms > baseRms * 2.0
        ? NightFindingSeverity.critical
        : NightFindingSeverity.warn;

    return [
      NightFinding(
        id: 'guiding_correlation',
        severity: severity,
        title: 'Guiding spikes elongated your stars',
        explanation:
            '${culprits.length} subs show guiding RMS up to '
            '${worstRms.toStringAsFixed(2)}" (vs a '
            '${baseRms.toStringAsFixed(2)}" baseline) together with elongated '
            'stars — the guiding error directly cost frame sharpness.',
        advice:
            'Cull the affected subs. Investigate the cause (wind, cable snag, '
            'differential flexure, or aggressive guide settings) and consider '
            'dithering / lower guide aggressiveness.',
        evidenceSubIds: culprits.map((s) => s.id).toList(),
        metricSeries: rms,
      ),
    ];
  }

  /// **Dew / HFR collapse.** A *sharp, irreversible* HFR jump combined with star
  /// loss — the optics fogging over. Distinct from focus drift (which is slow
  /// and monotone): here HFR steps up at one point and never recovers, and the
  /// star count falls off a cliff. Fires on the first such collapse point.
  List<NightFinding> _detectDewHfrCollapse(NightData data) {
    final pts = data.subs.where((s) => s.hfr != null).toList(growable: false);
    if (pts.length < 6) return const [];

    final hfrs = [for (final s in pts) s.hfr!];
    // Scan for a step where HFR jumps sharply and stays high afterwards.
    for (var k = 2; k < pts.length - 1; k++) {
      final before = _median([for (var i = 0; i < k; i++) hfrs[i]]);
      final afterVals = [for (var i = k; i < hfrs.length; i++) hfrs[i]];
      final after = _median(afterVals);
      if (before == null || after == null || before <= 0) continue;

      final ratio = after / before;
      // Irreversible: the post-collapse minimum never returns near baseline.
      final afterMin = afterVals.reduce(math.min);
      final recovered = afterMin < before * 1.3;
      final stepUp = hfrs[k] / before;

      if (ratio >= 1.6 && stepUp >= 1.4 && !recovered) {
        // Confirm star loss across the same boundary when star counts exist.
        final starsBefore = _median(
          [
            for (var i = 0; i < k; i++) pts[i].starCount?.toDouble(),
          ].whereType<double>().toList(),
        );
        final starsAfter = _median(
          [
            for (var i = k; i < pts.length; i++) pts[i].starCount?.toDouble(),
          ].whereType<double>().toList(),
        );
        final starLoss =
            (starsBefore != null && starsAfter != null && starsBefore > 0)
            ? starsAfter < starsBefore * 0.6
            : true; // no star data → don't block on it (HFR step is enough)
        if (!starLoss) continue;

        final evidence = [for (var i = k; i < pts.length; i++) pts[i].id];
        return [
          NightFinding(
            id: 'dew_hfr_collapse',
            severity: NightFindingSeverity.critical,
            title: 'Optics likely dewed over',
            explanation:
                'HFR jumped sharply (${before.toStringAsFixed(2)} → '
                '${after.toStringAsFixed(2)} px) and never recovered'
                '${starsBefore != null && starsAfter != null ? ', with star '
                          'count collapsing from ${starsBefore.round()} to '
                          '${starsAfter.round()}' : ''} — the classic signature of '
                'dew or frost on the optics.',
            advice:
                'Fit and power a dew heater on the corrector/objective, and '
                'consider a dew shield. Everything after this point is likely '
                'unusable.',
            evidenceSubIds: evidence,
            metricSeries: hfrs,
          ),
        ];
      }
    }
    return const [];
  }

  /// **Moon-gradient onset.** A rising sky background that tracks the moon
  /// climbing in altitude — sky brightness from moonlight. Needs per-sub
  /// `background` and the mount pointing to compute moon separation/altitude;
  /// since `captured_images` carries no per-sub moon column we compute the moon
  /// altitude from `capturedAt` against an inferred observer site. When the
  /// observer location is unknown we fail-soft to a pure background-vs-time
  /// rise check only if it correlates with the lunar phase being bright.
  ///
  /// In this Dart-core layer we have no site lat/long on the session row, so the
  /// detector reduces to: background rises monotonically through the night while
  /// the moon is illuminated and climbing (computed from the timestamp). It is
  /// deliberately conservative — info severity — because without a site it can't
  /// fully separate moon from light-pollution gradient.
  List<NightFinding> _detectMoonGradientOnset(NightData data) {
    final pts = data.subs
        .where((s) => s.background != null)
        .map((s) => (sub: s, bg: s.background!))
        .toList(growable: false);
    if (pts.length < 8) return const [];

    final times = [
      for (final p in pts) p.sub.capturedAt.millisecondsSinceEpoch.toDouble(),
    ];
    final bgs = [for (final p in pts) p.bg];
    final r = _pearson(times, bgs);
    if (r == null || r < 0.6) return const [];

    final mid = pts.length ~/ 2;
    final early = _median([for (var i = 0; i < mid; i++) bgs[i]]);
    final late = _median([for (var i = mid; i < bgs.length; i++) bgs[i]]);
    if (early == null || late == null || early <= 0) return const [];
    final relRise = (late - early) / early;
    if (relRise < 0.2) return const [];

    // Cross-reference the moon: only call it a moon gradient when the moon is
    // both illuminated and rising across the window. Otherwise it's more likely
    // a target descending into light pollution — still worth noting, lower key.
    final moonStart = _MoonEphemeris.illuminationAndAltitudeTrend(
      pts.first.sub.capturedAt,
      pts.last.sub.capturedAt,
    );
    final moonDriven = moonStart.illumination > 0.4 && moonStart.altitudeRising;

    return [
      NightFinding(
        id: 'moon_gradient',
        severity: moonDriven
            ? NightFindingSeverity.warn
            : NightFindingSeverity.info,
        title: moonDriven
            ? 'Moon washed out the sky as it rose'
            : 'Sky background rose through the night',
        explanation: moonDriven
            ? 'Sky background climbed '
                  '${(relRise * 100).round()}% as the moon '
                  '(${(moonStart.illumination * 100).round()}% lit) rose — '
                  'moonlight gradient reducing contrast on faint signal.'
            : 'Sky background climbed ${(relRise * 100).round()}% through the '
                  'session, eroding contrast (light-pollution gradient or the '
                  'target sinking toward the horizon).',
        advice: moonDriven
            ? 'Schedule this target on darker, moon-free nights, or switch to '
                  'narrowband filters that reject moonlight.'
            : 'Image this target when it is higher / earlier, and apply gradient '
                  'extraction in post.',
        evidenceSubIds: [for (final p in pts) p.sub.id],
        metricSeries: bgs,
      ),
    ];
  }

  /// **Tilt / collimation.** Driven by the session's PSF field tiles +
  /// astrometric residual vectors via [OpticalTrainDiagnosticsService] —
  /// the same engine behind the equipment screen's optical-health card, so
  /// the morning report and the live card can never disagree. Silent when
  /// the science pipeline produced no tiles for the session (the common
  /// case for rigs with the science tier disabled).
  List<NightFinding> _detectTiltCollimation(NightData data) {
    final diag = data.opticalDiagnostics;
    if (diag == null) return const [];

    final findings = <NightFinding>[];
    if (diag.tiltScore >= OpticalHealthScore.tiltWarnThreshold) {
      final critical =
          diag.tiltScore >= OpticalHealthScore.tiltCriticalThreshold;
      findings.add(
        NightFinding(
          id: 'field_tilt',
          severity: critical
              ? NightFindingSeverity.critical
              : NightFindingSeverity.warn,
          title:
              'Field tilt detected '
              '(score ${diag.tiltScore.toStringAsFixed(0)}/100)',
          explanation:
              'Star size (PSF) is systematically uneven across the frame; the '
              'strongest degradation is toward ${diag.dominantTiltDirection}. '
              'This pattern held across the night\'s solved frames, which '
              'points at sensor tilt or a sagging imaging-train connection '
              'rather than seeing.',
          advice:
              'Check the camera/corrector connection for sag and the '
              'sensor tilt adjustment (if your camera has a tilt plate). The '
              'equipment screen\'s optical-health card shows the live '
              'corner-by-corner breakdown.',
        ),
      );
    }
    if (diag.collimationScore >= OpticalHealthScore.collimationWarnThreshold) {
      final critical =
          diag.collimationScore >=
          OpticalHealthScore.collimationCriticalThreshold;
      findings.add(
        NightFinding(
          id: 'collimation_spacing',
          severity: critical
              ? NightFindingSeverity.critical
              : NightFindingSeverity.warn,
          title:
              'Collimation / spacing mismatch '
              '(score ${diag.collimationScore.toStringAsFixed(0)}/100)',
          explanation:
              'Astrometric residuals grow toward the field edges relative to '
              'the centre — the signature of optical misalignment or wrong '
              'corrector/flattener back-spacing, not atmosphere.',
          advice:
              'Verify collimation and the flattener back-focus distance '
              '(55 mm is typical but check your corrector\'s spec).',
        ),
      );
    }
    return findings;
  }

  // ===========================================================================
  // Scoring + headline
  // ===========================================================================

  /// Per-finding penalties. Monotone in severity (critical > warn > info), so
  /// the night score is monotone w.r.t. the worst finding's severity. Penalties
  /// stack but the score is floored at 0.
  static const Map<NightFindingSeverity, int> _penalty = {
    NightFindingSeverity.info: 2,
    NightFindingSeverity.warn: 12,
    NightFindingSeverity.critical: 30,
  };

  int _score(List<NightFinding> findings) {
    var score = 100;
    for (final f in findings) {
      score -= _penalty[f.severity] ?? 0;
    }
    return score.clamp(0, 100);
  }

  String _headline(int score, List<NightFinding> findings) {
    if (findings.isEmpty) {
      return score >= 100
          ? 'A clean night — no problems detected.'
          : 'A solid night with nothing significant to flag.';
    }
    final worst = findings.first; // sorted severity-desc
    final extra = findings.length - 1;
    final tail = extra > 0
        ? ' (+$extra more ${extra == 1 ? 'finding' : 'findings'})'
        : '';
    switch (worst.severity) {
      case NightFindingSeverity.critical:
        return 'Rough night: ${worst.title.toLowerCase()}$tail.';
      case NightFindingSeverity.warn:
        return 'Decent night, but ${worst.title.toLowerCase()}$tail.';
      case NightFindingSeverity.info:
        return 'Good night${tail.isEmpty ? '' : ' —'}${worst.title.toLowerCase()}$tail.';
    }
  }

  static int _bySeverityDesc(NightFinding a, NightFinding b) {
    return b.severity.index.compareTo(a.severity.index);
  }

  // ===========================================================================
  // Numeric helpers (pure)
  // ===========================================================================

  static double? _focuserTempDrift(Iterable<NightSub> subs) {
    final temps = [
      for (final s in subs)
        if (s.focuserTemp != null) s.focuserTemp!,
    ];
    if (temps.length < 4) return null;
    final drift = temps.last - temps.first;
    return drift.abs() >= 1.0 ? drift : null;
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
  }

  /// Median absolute deviation about [center] — a robust spread estimate.
  static double? _mad(List<double> values, double? center) {
    if (values.isEmpty || center == null) return null;
    final devs = [for (final v in values) (v - center).abs()];
    return _median(devs);
  }

  /// Pearson correlation; null when undefined (too few points or zero variance).
  static double? _pearson(List<double> xs, List<double> ys) {
    final n = math.min(xs.length, ys.length);
    if (n < 3) return null;
    var sx = 0.0, sy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += xs[i];
      sy += ys[i];
    }
    final mx = sx / n, my = sy / n;
    var num = 0.0, dx = 0.0, dy = 0.0;
    for (var i = 0; i < n; i++) {
      final ax = xs[i] - mx, ay = ys[i] - my;
      num += ax * ay;
      dx += ax * ax;
      dy += ay * ay;
    }
    if (dx <= 0 || dy <= 0) return null;
    return num / math.sqrt(dx * dy);
  }
}

/// One sub's per-sub metrics, denormalized from `captured_images` (+ optional
/// science enrichment) into a plain value object the detectors operate on.
///
/// Public so tests can build synthetic series directly and drive
/// [NightAnalysisService.analyze] without a database.
class NightSub {
  const NightSub({
    required this.id,
    required this.capturedAt,
    this.filter,
    this.isAccepted = true,
    this.hfr,
    this.starCount,
    this.background,
    this.noise,
    this.guidingRmsTotal,
    this.focuserPosition,
    this.focuserTemp,
    this.sensorTemp,
    this.eccentricity,
    this.snr,
    this.fwhm,
  });

  final int id;
  final DateTime capturedAt;
  final String? filter;
  final bool isAccepted;
  final double? hfr;
  final int? starCount;
  final double? background;
  final double? noise;
  final double? guidingRmsTotal;
  final int? focuserPosition;
  final double? focuserTemp;
  final double? sensorTemp;
  final double? eccentricity;

  /// Background-corrected SNR (science table); null when the science pipeline
  /// did not run for this sub.
  final double? snr;

  /// Field-median FWHM (science PSF tiles); null when absent.
  final double? fwhm;
}

/// The analyzed night: a time-sorted list of [NightSub]s. Thin wrapper so the
/// detector signatures read clearly and future cross-sub aggregates have a home.
class NightData {
  NightData(List<NightSub> subs, {this.opticalDiagnostics})
    : subs = List.unmodifiable(
        [...subs]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt)),
      );

  final List<NightSub> subs;

  /// Session-level optical-train diagnostics (field tilt / collimation)
  /// computed from the science PSF field tiles + astrometric residuals.
  /// Null when the science pipeline produced no tiles for the session.
  final OpticalTrainDiagnostics? opticalDiagnostics;

  bool get isEmpty => subs.isEmpty;
  int get length => subs.length;
}

/// Self-contained low-precision lunar ephemeris (Meeus), copied from
/// `SchedulerService.calculateMoonPosition` + the scheduler's alt/az conversion
/// so [NightAnalysisService] depends on neither the scheduler engine (its moon
/// API is private) nor a live site. Illumination uses the same
/// `(1 - cos(D)) / 2` phase approximation as the rest of the codebase.
class _MoonEphemeris {
  /// Mean illumination over the window and whether the moon's altitude is
  /// rising across it. Altitude is computed at a nominal mid-northern-latitude
  /// observer because `captured_images` / the session row carry no site
  /// lat/long in this layer; the *rising/setting* trend is robust to that
  /// choice for the "is the moon coming up?" question the detector asks.
  static ({double illumination, bool altitudeRising})
  illuminationAndAltitudeTrend(DateTime start, DateTime end) {
    const latDeg = 40.0; // nominal mid-northern site
    const lonDeg = 0.0;
    final mid = DateTime.fromMillisecondsSinceEpoch(
      (start.millisecondsSinceEpoch + end.millisecondsSinceEpoch) ~/ 2,
      isUtc: true,
    );
    final pos = _moonPosition(mid);
    final altStart = _altitude(
      raHours: pos.raHours,
      decDeg: pos.decDeg,
      time: start,
      latDeg: latDeg,
      lonDeg: lonDeg,
    );
    final altEnd = _altitude(
      raHours: _moonPosition(end).raHours,
      decDeg: _moonPosition(end).decDeg,
      time: end,
      latDeg: latDeg,
      lonDeg: lonDeg,
    );
    return (illumination: pos.illumination, altitudeRising: altEnd > altStart);
  }

  static ({double raHours, double decDeg, double illumination}) _moonPosition(
    DateTime time,
  ) {
    final jd = _julianDate(time);
    final t = (jd - 2451545.0) / 36525.0;
    final l = (218.3164477 + 481267.88123421 * t) % 360.0;
    final d = (297.8501921 + 445267.1114034 * t) % 360.0;
    final mp = (134.9633964 + 477198.8675055 * t) % 360.0;
    final dRad = d * math.pi / 180.0;
    final mpRad = mp * math.pi / 180.0;
    final lambda = l + 6.289 * math.sin(mpRad);
    final lambdaRad = lambda * math.pi / 180.0;
    final beta = 5.128 * math.sin(mpRad);
    final betaRad = beta * math.pi / 180.0;
    const epsRad = 23.439 * math.pi / 180.0;
    final ra = math.atan2(
      math.sin(lambdaRad) * math.cos(epsRad) -
          math.tan(betaRad) * math.sin(epsRad),
      math.cos(lambdaRad),
    );
    final dec = math.asin(
      math.sin(betaRad) * math.cos(epsRad) +
          math.cos(betaRad) * math.sin(epsRad) * math.sin(lambdaRad),
    );
    var raHours = (ra * 180.0 / math.pi) / 15.0;
    if (raHours < 0) raHours += 24.0;
    final illumination = (1.0 - math.cos(dRad)) / 2.0;
    return (
      raHours: raHours,
      decDeg: dec * 180.0 / math.pi,
      illumination: illumination,
    );
  }

  static double _altitude({
    required double raHours,
    required double decDeg,
    required DateTime time,
    required double latDeg,
    required double lonDeg,
  }) {
    final dec = decDeg * math.pi / 180.0;
    final lat = latDeg * math.pi / 180.0;
    final lst = _localSiderealTime(time, lonDeg);
    final ha = (lst - raHours) * 15.0 * math.pi / 180.0;
    final sinAlt =
        math.sin(dec) * math.sin(lat) +
        math.cos(dec) * math.cos(lat) * math.cos(ha);
    return math.asin(sinAlt.clamp(-1.0, 1.0)) * 180.0 / math.pi;
  }

  static double _localSiderealTime(DateTime time, double lonDeg) {
    final jd = _julianDate(time);
    final t = (jd - 2451545.0) / 36525.0;
    var gmst =
        280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        t * t * t / 38710000.0;
    gmst %= 360.0;
    if (gmst < 0) gmst += 360.0;
    var lst = gmst / 15.0 + lonDeg / 15.0;
    while (lst < 0) {
      lst += 24.0;
    }
    while (lst >= 24) {
      lst -= 24.0;
    }
    return lst;
  }

  static double _julianDate(DateTime dt) {
    final utc = dt.toUtc();
    var y = utc.year;
    var m = utc.month;
    final d =
        utc.day + utc.hour / 24.0 + utc.minute / 1440.0 + utc.second / 86400.0;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        d +
        b -
        1524.5;
  }
}

/// Riverpod provider for the Night Doctor. Constructor-injected DAOs mirror the
/// post-session services' idiom so tests override the DAO providers (or
/// construct the service directly) to run without native code.
final nightAnalysisServiceProvider = Provider<NightAnalysisService>((ref) {
  return NightAnalysisService(
    images: ref.watch(imagesDaoProvider),
    science: ref.watch(scienceDaoProvider),
    reports: ref.watch(nightReportsDaoProvider),
  );
});

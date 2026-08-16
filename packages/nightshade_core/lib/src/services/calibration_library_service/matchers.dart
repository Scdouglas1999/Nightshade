part of '../calibration_library_service.dart';

extension _CalibrationLibraryMatchers on CalibrationLibraryService {
  // Per-type matchers

  CalibrationMatch? _matchDark(
    Iterable<CalibrationMasterRecord> darks,
    LightFrameContext ctx,
    CalibrationMatchTolerances tol,
  ) {
    // Hard requirements: exact gain / offset / binning, compatible camera.
    final candidates = darks
        .where(
          (r) =>
              r.gain == ctx.gain &&
              r.offset == ctx.offset &&
              r.binX == ctx.binX &&
              r.binY == ctx.binY &&
              _cameraCompatible(r, ctx),
        )
        .toList();
    if (candidates.isEmpty) return null;

    final exposureTol = tol.dark.exposureSecs;
    final exact = candidates
        .where(
          (r) =>
              r.exposureSeconds != null &&
              (r.exposureSeconds! - ctx.exposureSeconds).abs() <= exposureTol,
        )
        .toList();
    final scaled = exact.isEmpty;
    var pool = scaled ? candidates : exact;

    // Temperature gate: prefer within-tolerance; fall back (with a warning,
    // applied at scoring) only when nothing is within tolerance.
    var tempFellBack = false;
    if (ctx.temperature != null) {
      final within = pool
          .where(
            (r) =>
                r.temperature == null ||
                (r.temperature! - ctx.temperature!).abs() <=
                    tol.dark.temperatureC,
          )
          .toList();
      if (within.isNotEmpty) {
        pool = within;
      } else {
        tempFellBack = true;
      }
    }

    pool.sort((a, b) {
      // Masters beat raw frames.
      if (a.isMaster != b.isMaster) return a.isMaster ? -1 : 1;
      if (scaled) {
        // Nearest exposure first.
        final aD = _expDelta(a, ctx);
        final bD = _expDelta(b, ctx);
        final byExp = aD.compareTo(bD);
        if (byExp != 0) return byExp;
      }
      final aT = _tempDelta(a, ctx);
      final bT = _tempDelta(b, ctx);
      final byTemp = aT.compareTo(bT);
      if (byTemp != 0) return byTemp;
      // Conflict resolution: on an otherwise-exact tie, prefer a LOCAL master
      // over a remote one (you already have it; no download / trust step).
      if (a.isRemote != b.isRemote) return a.isRemote ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
    final best = pool.first;

    final reasons = <String>[
      'Exact gain ${ctx.gain} / offset ${ctx.offset} / bin '
          '${ctx.binX}x${ctx.binY} match (required for darks)',
    ];
    final warnings = <String>[];
    var score = 100.0;
    double? scaleFactor;

    if (scaled) {
      final darkExp = best.exposureSeconds;
      scaleFactor = (darkExp != null && darkExp > 0)
          ? ctx.exposureSeconds / darkExp
          : null;
      score -= 25;
      warnings.add(
        'No dark at ${_fmtSecs(ctx.exposureSeconds)} — nearest is '
        '${_fmtSecs(darkExp ?? 0)}; the dark will be scaled'
        '${scaleFactor != null ? ' by ${scaleFactor.toStringAsFixed(2)}x' : ''}.'
        ' Capture a matching-exposure dark for best results.',
      );
    } else {
      reasons.add(
        'Exposure ${_fmtSecs(best.exposureSeconds ?? 0)} '
        '(within ±${exposureTol}s of ${_fmtSecs(ctx.exposureSeconds)})',
      );
    }

    score = _applyTempScore(
      score: score,
      record: best,
      ctx: ctx,
      toleranceC: tol.dark.temperatureC,
      fellBack: tempFellBack,
      reasons: reasons,
      warnings: warnings,
      label: 'dark',
    );

    if (!best.isMaster) {
      score -= 15;
      warnings.add(
        'Matched a raw dark frame, not a stacked master — '
        'stack your darks to reduce injected noise.',
      );
    } else if (best.frameCount != null) {
      reasons.add('Stacked master of ${best.frameCount} frames');
    }

    _applyRemoteProvenance(best, reasons, warnings);
    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: CalibrationLibraryService._clampScore(score),
      reasons: reasons,
      warnings: warnings,
      exposureScaled: scaled,
      exposureScaleFactor: scaleFactor,
    );
  }

  CalibrationMatch? _matchBias(
    Iterable<CalibrationMasterRecord> biases,
    LightFrameContext ctx,
    CalibrationMatchTolerances tol,
  ) {
    final pool = biases
        .where(
          (r) =>
              r.gain == ctx.gain &&
              r.offset == ctx.offset &&
              r.binX == ctx.binX &&
              r.binY == ctx.binY &&
              _cameraCompatible(r, ctx),
        )
        .toList();
    if (pool.isEmpty) return null;

    pool.sort((a, b) {
      if (a.isMaster != b.isMaster) return a.isMaster ? -1 : 1;
      if (a.isRemote != b.isRemote) return a.isRemote ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
    final best = pool.first;

    final reasons = <String>[
      'Exact gain ${ctx.gain} / offset ${ctx.offset} / bin '
          '${ctx.binX}x${ctx.binY} match',
      'Newest of ${pool.length} candidate${pool.length == 1 ? '' : 's'}',
    ];
    final warnings = <String>[];
    var score = 100.0;
    if (!best.isMaster) {
      score -= 15;
      warnings.add('Matched a raw bias frame, not a stacked master.');
    }
    _applyRemoteProvenance(best, reasons, warnings);
    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: CalibrationLibraryService._clampScore(score),
      reasons: reasons,
      warnings: warnings,
    );
  }

  CalibrationMatch? _matchFlat(
    Iterable<CalibrationMasterRecord> flats,
    LightFrameContext ctx,
    CalibrationMatchTolerances tol,
  ) {
    final wantFilter = ctx.filter?.trim();
    var pool = flats
        .where(
          (r) =>
              r.gain == ctx.gain &&
              r.offset == ctx.offset &&
              r.binX == ctx.binX &&
              r.binY == ctx.binY &&
              _cameraCompatible(r, ctx),
        )
        .toList();
    if (wantFilter != null && wantFilter.isNotEmpty) {
      pool = pool
          .where((r) => r.filter != null && r.filter!.trim() == wantFilter)
          .toList();
    }
    // Mirror FlatLibraryDao: when the context carries an optical-train tag,
    // accept flats with a matching tag OR no tag at all (a generic flat).
    final wantTrain = ctx.opticalTrainId?.trim();
    if (wantTrain != null && wantTrain.isNotEmpty) {
      pool = pool
          .where(
            (r) =>
                r.opticalTrainId == null ||
                r.opticalTrainId!.trim() == wantTrain,
          )
          .toList();
    }
    if (pool.isEmpty) return null;

    // Temperature gate at the flat tolerance, falling back when empty.
    var tempFellBack = false;
    if (ctx.temperature != null) {
      final within = pool
          .where(
            (r) =>
                r.temperature == null ||
                (r.temperature! - ctx.temperature!).abs() <=
                    tol.flatTemperatureC,
          )
          .toList();
      if (within.isNotEmpty) {
        pool = within;
      } else {
        tempFellBack = true;
      }
    }

    // Flats are matched by filter + RECENCY: dust and the optical train
    // drift over days, so the newest qualifying flat wins outright; a LOCAL
    // flat breaks an exact same-day tie (you already have it).
    pool.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      if (byDate != 0) return byDate;
      if (a.isRemote != b.isRemote) return a.isRemote ? 1 : -1;
      return 0;
    });
    final best = pool.first;

    final reasons = <String>[
      if (wantFilter != null && wantFilter.isNotEmpty)
        'Filter $wantFilter match (required for flats)',
      'Newest of ${pool.length} qualifying flat${pool.length == 1 ? '' : 's'} '
          '(${CalibrationLibraryService._fmtDate(best.createdAt)})',
    ];
    final warnings = <String>[];
    var score = 100.0;

    score = _applyTempScore(
      score: score,
      record: best,
      ctx: ctx,
      toleranceC: tol.flatTemperatureC,
      fellBack: tempFellBack,
      reasons: reasons,
      warnings: warnings,
      label: 'flat',
      unknownTempPenalty: 0, // Flats are temperature-insensitive.
    );

    if (wantTrain != null &&
        wantTrain.isNotEmpty &&
        best.opticalTrainId == null) {
      score -= 10;
      warnings.add(
        'Flat has no optical-train tag — verify it was shot with '
        'the current optical configuration ($wantTrain).',
      );
    }

    _applyRemoteProvenance(best, reasons, warnings);
    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: CalibrationLibraryService._clampScore(score),
      reasons: reasons,
      warnings: warnings,
    );
  }

  CalibrationMatch? _matchDefectMap(
    Iterable<CalibrationMasterRecord> maps,
    LightFrameContext ctx,
  ) {
    final cameraId = ctx.cameraId?.trim();
    if (cameraId == null || cameraId.isEmpty) return null;
    final pool = maps.where((r) => r.cameraId == cameraId).toList();
    if (pool.isEmpty) return null;

    pool.sort((a, b) {
      final aT = _tempDelta(a, ctx);
      final bT = _tempDelta(b, ctx);
      final byTemp = aT.compareTo(bT);
      if (byTemp != 0) return byTemp;
      return b.createdAt.compareTo(a.createdAt);
    });
    final best = pool.first;

    final reasons = <String>['Camera $cameraId match'];
    final warnings = <String>[];
    var score = 100.0;
    if (ctx.temperature != null && best.temperature != null) {
      final delta = (best.temperature! - ctx.temperature!).abs();
      reasons.add(
        'Temperature bucket ${best.temperature!.toStringAsFixed(1)}'
        '°C (Δ${delta.toStringAsFixed(1)}°C)',
      );
      if (delta > 5.0) {
        score -= math.min(20.0, 2.0 * delta);
        warnings.add(
          'Defect map was built ${delta.toStringAsFixed(1)}°C from '
          'the current sensor temperature — hot-pixel sets shift with '
          'cooling setpoint.',
        );
      }
    }
    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: CalibrationLibraryService._clampScore(score),
      reasons: reasons,
      warnings: warnings,
    );
  }

  // Scoring helpers

  double _applyTempScore({
    required double score,
    required CalibrationMasterRecord record,
    required LightFrameContext ctx,
    required double toleranceC,
    required bool fellBack,
    required List<String> reasons,
    required List<String> warnings,
    required String label,
    double unknownTempPenalty = 10,
  }) {
    if (ctx.temperature != null && record.temperature != null) {
      final delta = (record.temperature! - ctx.temperature!).abs();
      reasons.add(
        'Temperature ${record.temperature!.toStringAsFixed(1)}°C '
        '(Δ${delta.toStringAsFixed(1)}°C, tolerance ±$toleranceC°C)',
      );
      score -= math.min(20.0, 4.0 * delta);
      if (fellBack || delta > toleranceC) {
        warnings.add(
          'Sensor temperature differs by ${delta.toStringAsFixed(1)}°C '
          'from the $label (tolerance ±$toleranceC°C).',
        );
      }
    } else if (record.temperature == null) {
      score -= unknownTempPenalty;
      if (unknownTempPenalty > 0) {
        warnings.add('The matched $label has no recorded sensor temperature.');
      }
    }
    return score;
  }

  double _applyStaleness(
    double score,
    CalibrationMasterRecord record,
    List<String> reasons,
    List<String> warnings,
  ) {
    final now = _now();
    final age = record.ageDays(now);
    final staleDays = thresholds.staleDaysFor(record.type);
    switch (record.freshness(now, thresholds: thresholds)) {
      case CalibrationFreshness.stale:
        warnings.add(
          '${_typeLabel(record.type)} is $age days old '
          '(recommended refresh: every $staleDays days).',
        );
        return score - 15;
      case CalibrationFreshness.aging:
        reasons.add(
          '$age days old (aging; refresh recommended every '
          '$staleDays days)',
        );
        return score - 5;
      case CalibrationFreshness.fresh:
        reasons.add('$age day${age == 1 ? '' : 's'} old (fresh)');
        return score;
    }
  }

  /// A record only conflicts with the context camera when BOTH are known and
  /// differ — legacy rows without a cached camera id stay matchable.
  bool _cameraCompatible(CalibrationMasterRecord r, LightFrameContext ctx) {
    final want = ctx.cameraId?.trim();
    if (want == null || want.isEmpty) return true;
    if (r.cameraId == null) return true;
    return r.cameraId == want;
  }

  double _expDelta(CalibrationMasterRecord r, LightFrameContext ctx) =>
      r.exposureSeconds == null
      ? double.maxFinite
      : (r.exposureSeconds! - ctx.exposureSeconds).abs();

  double _tempDelta(CalibrationMasterRecord r, LightFrameContext ctx) =>
      (ctx.temperature == null || r.temperature == null)
      ? double.maxFinite
      : (r.temperature! - ctx.temperature!).abs();
}

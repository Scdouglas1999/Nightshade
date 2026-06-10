import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/calibration_tags_dao.dart';
import '../database/daos/flat_library_dao.dart';
import '../database/database.dart';
import '../models/calibration/calibration_library_models.dart';
import '../providers/database_provider.dart';
import 'calibration/fits_header_reader.dart';

/// The Calibration Library Manager service: one unified browse / tag /
/// auto-match surface over the master artifacts the imaging pipeline already
/// records — `dark_library` (darks + biases), `flat_library` (master flats),
/// and `defect_maps` — joined with the v46 `calibration_tags` annotations.
///
/// Three jobs:
///  1. **List** masters with independent filters ([listMasters]), enriching
///     metadata the DB rows lack (camera id, temperature, filter) from the
///     FITS primary header and caching the camera id in `calibration_tags`.
///  2. **Match** ([match]): given a light-frame context, pick the best master
///     per type with a transparent 0–100 score, per-pick reasons, and
///     warnings (exact gain/offset required for darks; temperature within
///     tolerance; nearest exposure with a scaling flag; flats by filter +
///     recency; staleness thresholds per type).
///  3. **Annotate / manage**: user tags + notes per master ([setTags] /
///     [setNotes]) and deletion of the artifact row + optional file
///     ([deleteMaster]).
class CalibrationLibraryService {
  CalibrationLibraryService({
    required NightshadeDatabase db,
    required FlatLibraryDao flatLibraryDao,
    required CalibrationTagsDao tagsDao,
    this.headerReader = const FitsHeaderReader(),
    this.thresholds = CalibrationStalenessThresholds.defaults,
    DateTime Function()? now,
  })  : _db = db,
        _flatDao = flatLibraryDao,
        _tagsDao = tagsDao,
        _now = now ?? DateTime.now;

  final NightshadeDatabase _db;
  final FlatLibraryDao _flatDao;
  final CalibrationTagsDao _tagsDao;
  final FitsHeaderReader headerReader;
  final CalibrationStalenessThresholds thresholds;
  final DateTime Function() _now;

  // ---------------------------------------------------------------------------
  // Listing + enrichment
  // ---------------------------------------------------------------------------

  /// All library records matching [filter], newest first.
  ///
  /// When [enrichFromHeaders] is set (the default), records missing a camera
  /// id / temperature / filter get those keys read from the FITS primary
  /// header of the master file; the camera id is cached in
  /// `calibration_tags.camera_id` so each file is parsed at most once.
  /// Enrichment is best-effort — a missing or malformed file never breaks the
  /// listing.
  Future<List<CalibrationMasterRecord>> listMasters({
    CalibrationLibraryFilter filter = const CalibrationLibraryFilter(),
    bool enrichFromHeaders = true,
  }) async {
    var records = await _loadAll();

    if (filter.mastersOnly) {
      records = records.where((r) => r.isMaster).toList();
    }
    if (filter.type != null) {
      records = records.where((r) => r.type == filter.type).toList();
    }
    if (filter.gain != null) {
      records = records.where((r) => r.gain == filter.gain).toList();
    }
    if (filter.binX != null) {
      records = records.where((r) => r.binX == filter.binX).toList();
    }
    if (filter.binY != null) {
      records = records.where((r) => r.binY == filter.binY).toList();
    }
    if (filter.exposureSeconds != null) {
      records = records
          .where((r) =>
              r.exposureSeconds != null &&
              (r.exposureSeconds! - filter.exposureSeconds!).abs() <=
                  filter.exposureToleranceSecs)
          .toList();
    }
    if (filter.temperatureMin != null) {
      records = records
          .where((r) =>
              r.temperature != null && r.temperature! >= filter.temperatureMin!)
          .toList();
    }
    if (filter.temperatureMax != null) {
      records = records
          .where((r) =>
              r.temperature != null && r.temperature! <= filter.temperatureMax!)
          .toList();
    }
    final filterName = filter.filter?.trim();
    if (filterName != null && filterName.isNotEmpty) {
      records = records
          .where((r) =>
              r.filter != null &&
              r.filter!.trim().toLowerCase() == filterName.toLowerCase())
          .toList();
    }

    if (enrichFromHeaders) {
      records = [for (final r in records) await _enrich(r)];
    }

    final cameraId = filter.cameraId?.trim();
    if (cameraId != null && cameraId.isNotEmpty) {
      records = records.where((r) => r.cameraId == cameraId).toList();
    }

    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  /// One record by identity, or null. Enriched from the FITS header.
  Future<CalibrationMasterRecord?> getRecord(
      CalibrationMasterType type, int id) async {
    final all = await _loadAll();
    for (final record in all) {
      if (record.type == type && record.id == id) {
        return _enrich(record);
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Matching
  // ---------------------------------------------------------------------------

  /// Pick the best master per type for [context].
  ///
  /// Rules (each deviation is scored down and surfaced in `reasons` /
  /// `warnings` — the match is transparent by design):
  ///  * **Darks**: gain, offset, and binning must match *exactly*. Exposure
  ///    within ±[CalibrationMatchTolerances.dark]`.exposureSecs` is an exact
  ///    match; otherwise the nearest-exposure dark is returned with
  ///    `exposureScaled = true` and a warning. Temperature within tolerance
  ///    preferred; out-of-tolerance candidates only win when nothing closer
  ///    exists (with a warning). Stacked masters beat raw frames. Older than
  ///    [CalibrationStalenessThresholds.darkStaleDays] warns.
  ///  * **Bias**: exact gain / offset / binning; newest wins.
  ///  * **Flats**: matched by filter (exact, when the context has one) +
  ///    recency; gain / offset / binning exact (mirrors
  ///    [FlatLibraryDao.findBestMatch]). Older than `flatStaleDays` (7 d)
  ///    warns — flats go bad with any dust or optical-train change. A flat
  ///    without an optical-train tag matched against a context that has one
  ///    also warns.
  ///  * **Defect maps**: per camera id; nearest temperature bucket.
  Future<CalibrationMatchSet> match(
    LightFrameContext context, {
    CalibrationMatchTolerances tolerances = CalibrationMatchTolerances.defaults,
  }) async {
    final all = await _loadAll();
    final setWarnings = <String>[];

    final dark = _matchDark(
      all.where((r) => r.type == CalibrationMasterType.dark),
      context,
      tolerances,
    );
    if (dark == null) {
      setWarnings.add(
        'No matching master dark (gain ${context.gain}, offset '
        '${context.offset}, bin ${context.binX}x${context.binY}, '
        '${_fmtSecs(context.exposureSeconds)}) — dark subtraction will be '
        'skipped.',
      );
    }

    final bias = _matchBias(
      all.where((r) => r.type == CalibrationMasterType.bias),
      context,
      tolerances,
    );

    final flat = _matchFlat(
      all.where((r) => r.type == CalibrationMasterType.flat),
      context,
      tolerances,
    );
    if (flat == null) {
      final filterPart = (context.filter == null ||
              context.filter!.trim().isEmpty)
          ? ''
          : ' for filter ${context.filter!.trim()}';
      setWarnings.add(
        'No matching master flat$filterPart (gain ${context.gain}, bin '
        '${context.binX}x${context.binY}) — flat-field correction will be '
        'skipped.',
      );
    }

    final defectMap = _matchDefectMap(
      all.where((r) => r.type == CalibrationMasterType.defectMap),
      context,
    );

    return CalibrationMatchSet(
      context: context,
      dark: dark,
      bias: bias,
      flat: flat,
      defectMap: defectMap,
      warnings: setWarnings,
    );
  }

  // ---------------------------------------------------------------------------
  // Tagging
  // ---------------------------------------------------------------------------

  /// Replace the user tags of one master.
  Future<void> setTags(
      CalibrationMasterType type, int id, List<String> tags) async {
    final cleaned = [
      for (final t in tags)
        if (t.trim().isNotEmpty) t.trim()
    ];
    await _tagsDao.upsert(type, id, tags: cleaned);
  }

  /// Replace the notes of one master (null/empty clears them).
  Future<void> setNotes(
      CalibrationMasterType type, int id, String? notes) async {
    final cleaned = notes?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      await _tagsDao.upsert(type, id, clearNotes: true);
    } else {
      await _tagsDao.upsert(type, id, notes: cleaned);
    }
  }

  // ---------------------------------------------------------------------------
  // Deletion
  // ---------------------------------------------------------------------------

  /// Delete one master's DB row (plus its `calibration_tags` annotation) and,
  /// when [deleteFile] is set, the on-disk artifact(s). Returns false when no
  /// row with that identity exists.
  Future<bool> deleteMaster(
    CalibrationMasterType type,
    int id, {
    bool deleteFile = false,
  }) async {
    var found = false;
    switch (type) {
      case CalibrationMasterType.dark:
      case CalibrationMasterType.bias:
        final entry = await (_db.select(_db.darkLibrary)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (entry != null) {
          found = true;
          if (deleteFile) {
            await _deleteFileIfExists(entry.filePath);
            if (entry.masterDarkPath != null) {
              await _deleteFileIfExists(entry.masterDarkPath!);
            }
          }
          await (_db.delete(_db.darkLibrary)..where((t) => t.id.equals(id)))
              .go();
        }
      case CalibrationMasterType.flat:
        final entry = await _flatDao.getEntryById(id);
        if (entry != null) {
          found = true;
          if (deleteFile) {
            await _deleteFileIfExists(entry.filePath);
          }
          await _flatDao.deleteEntry(id);
        }
      case CalibrationMasterType.defectMap:
        final entry = await (_db.select(_db.defectMaps)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (entry != null) {
          found = true;
          if (deleteFile && entry.filePath != null) {
            await _deleteFileIfExists(entry.filePath!);
          }
          await (_db.delete(_db.defectMaps)..where((t) => t.id.equals(id)))
              .go();
        }
    }
    if (found) {
      await _tagsDao.deleteForMaster(type, id);
    }
    return found;
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<List<CalibrationMasterRecord>> _loadAll() async {
    final tags = await _tagsDao.getAllKeyed();

    CalibrationTagEntry? tagFor(CalibrationMasterType type, int id) =>
        tags['${calibrationMasterTypeWireName(type)}:$id'];

    final records = <CalibrationMasterRecord>[];

    final darkRows = await _db.select(_db.darkLibrary).get();
    for (final row in darkRows) {
      final type = row.frameType == 'bias'
          ? CalibrationMasterType.bias
          : CalibrationMasterType.dark;
      final tag = tagFor(type, row.id);
      records.add(CalibrationMasterRecord(
        type: type,
        id: row.id,
        filePath: row.masterDarkPath ?? row.filePath,
        isMaster: row.masterDarkPath != null,
        frameCount: row.masterFrameCount,
        exposureSeconds: row.exposureTime,
        temperature: row.temperature,
        gain: row.gain,
        offset: row.offset,
        binX: row.binX,
        binY: row.binY,
        width: row.width,
        height: row.height,
        cameraId: tag?.cameraId,
        createdAt: row.createdAt,
        tags: tag?.tags ?? const [],
        notes: tag?.notes,
      ));
    }

    final flatRows = await _flatDao.getAllEntries();
    for (final row in flatRows) {
      final tag = tagFor(CalibrationMasterType.flat, row.id);
      records.add(CalibrationMasterRecord(
        type: CalibrationMasterType.flat,
        id: row.id,
        filePath: row.filePath,
        isMaster: true,
        frameCount: row.masterFrameCount,
        temperature: row.temperature,
        gain: row.gain,
        offset: row.offset,
        binX: row.binX,
        binY: row.binY,
        filter: row.filter,
        flatKind: row.flatKind,
        width: row.width,
        height: row.height,
        cameraId: tag?.cameraId,
        opticalTrainId: row.opticalTrainId,
        createdAt: row.createdAt,
        tags: tag?.tags ?? const [],
        notes: tag?.notes,
      ));
    }

    final mapRows = await _db.select(_db.defectMaps).get();
    for (final row in mapRows) {
      final tag = tagFor(CalibrationMasterType.defectMap, row.id);
      records.add(CalibrationMasterRecord(
        type: CalibrationMasterType.defectMap,
        id: row.id,
        filePath: row.filePath,
        isMaster: true,
        frameCount: row.defectivePixelCount,
        temperature: row.temperatureBucketDecicelsius / 10.0,
        width: row.width,
        height: row.height,
        cameraId: row.cameraId,
        createdAt: row.lastRebuiltAt,
        tags: tag?.tags ?? const [],
        notes: tag?.notes,
      ));
    }

    return records;
  }

  /// Fill missing camera id / temperature / filter from the FITS primary
  /// header, caching the camera id in `calibration_tags`. Best-effort:
  /// returns the record unchanged when the file is missing or unreadable.
  Future<CalibrationMasterRecord> _enrich(
      CalibrationMasterRecord record) async {
    if (record.type == CalibrationMasterType.defectMap) return record;
    final needsCamera = record.cameraId == null;
    final needsTemp = record.temperature == null;
    final needsFilter =
        record.type == CalibrationMasterType.flat && record.filter == null;
    if (!needsCamera && !needsTemp && !needsFilter) return record;

    final path = record.filePath;
    if (path == null || path.isEmpty) return record;

    Map<String, String> headers;
    try {
      if (!await File(path).exists()) return record;
      headers = await headerReader.readPrimaryHeader(path);
    } catch (e) {
      developer.log(
        'Calibration enrichment skipped for $path: $e',
        name: 'CalibrationLibraryService',
        level: 900,
      );
      return record;
    }

    final camera = needsCamera
        ? FitsHeaderReader.stringValue(headers, 'INSTRUME')
        : record.cameraId;
    final temperature = needsTemp
        ? FitsHeaderReader.firstDouble(
            headers, const ['CCD-TEMP', 'CCD_TEMP', 'SET-TEMP'])
        : record.temperature;
    final filterName = needsFilter
        ? FitsHeaderReader.stringValue(headers, 'FILTER')
        : record.filter;

    if (needsCamera && camera != null) {
      // Cache so the header is parsed at most once per artifact.
      try {
        await _tagsDao.upsert(record.type, record.id, cameraId: camera);
      } catch (e) {
        developer.log(
          'Failed to cache camera id for ${record.type.name}#${record.id}: $e',
          name: 'CalibrationLibraryService',
          level: 900,
        );
      }
    }

    return record.copyWith(
      cameraId: camera,
      temperature: temperature,
      filter: filterName,
    );
  }

  // ---------------------------------------------------------------------------
  // Per-type matchers
  // ---------------------------------------------------------------------------

  CalibrationMatch? _matchDark(
    Iterable<CalibrationMasterRecord> darks,
    LightFrameContext ctx,
    CalibrationMatchTolerances tol,
  ) {
    // Hard requirements: exact gain / offset / binning, compatible camera.
    final candidates = darks
        .where((r) =>
            r.gain == ctx.gain &&
            r.offset == ctx.offset &&
            r.binX == ctx.binX &&
            r.binY == ctx.binY &&
            _cameraCompatible(r, ctx))
        .toList();
    if (candidates.isEmpty) return null;

    final exposureTol = tol.dark.exposureSecs;
    final exact = candidates
        .where((r) =>
            r.exposureSeconds != null &&
            (r.exposureSeconds! - ctx.exposureSeconds).abs() <= exposureTol)
        .toList();
    final scaled = exact.isEmpty;
    var pool = scaled ? candidates : exact;

    // Temperature gate: prefer within-tolerance; fall back (with a warning,
    // applied at scoring) only when nothing is within tolerance.
    var tempFellBack = false;
    if (ctx.temperature != null) {
      final within = pool
          .where((r) =>
              r.temperature == null ||
              (r.temperature! - ctx.temperature!).abs() <=
                  tol.dark.temperatureC)
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
      reasons.add('Exposure ${_fmtSecs(best.exposureSeconds ?? 0)} '
          '(within ±${exposureTol}s of ${_fmtSecs(ctx.exposureSeconds)})');
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
      warnings.add('Matched a raw dark frame, not a stacked master — '
          'stack your darks to reduce injected noise.');
    } else if (best.frameCount != null) {
      reasons.add('Stacked master of ${best.frameCount} frames');
    }

    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: _clampScore(score),
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
        .where((r) =>
            r.gain == ctx.gain &&
            r.offset == ctx.offset &&
            r.binX == ctx.binX &&
            r.binY == ctx.binY &&
            _cameraCompatible(r, ctx))
        .toList();
    if (pool.isEmpty) return null;

    pool.sort((a, b) {
      if (a.isMaster != b.isMaster) return a.isMaster ? -1 : 1;
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
    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: _clampScore(score),
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
        .where((r) =>
            r.gain == ctx.gain &&
            r.offset == ctx.offset &&
            r.binX == ctx.binX &&
            r.binY == ctx.binY &&
            _cameraCompatible(r, ctx))
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
          .where((r) =>
              r.opticalTrainId == null || r.opticalTrainId!.trim() == wantTrain)
          .toList();
    }
    if (pool.isEmpty) return null;

    // Temperature gate at the flat tolerance, falling back when empty.
    var tempFellBack = false;
    if (ctx.temperature != null) {
      final within = pool
          .where((r) =>
              r.temperature == null ||
              (r.temperature! - ctx.temperature!).abs() <= tol.flatTemperatureC)
          .toList();
      if (within.isNotEmpty) {
        pool = within;
      } else {
        tempFellBack = true;
      }
    }

    // Flats are matched by filter + RECENCY: dust and the optical train
    // drift over days, so the newest qualifying flat wins outright.
    pool.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final best = pool.first;

    final reasons = <String>[
      if (wantFilter != null && wantFilter.isNotEmpty)
        'Filter $wantFilter match (required for flats)',
      'Newest of ${pool.length} qualifying flat${pool.length == 1 ? '' : 's'} '
          '(${_fmtDate(best.createdAt)})',
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
      warnings.add('Flat has no optical-train tag — verify it was shot with '
          'the current optical configuration ($wantTrain).');
    }

    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: _clampScore(score),
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
      reasons.add('Temperature bucket ${best.temperature!.toStringAsFixed(1)}'
          '°C (Δ${delta.toStringAsFixed(1)}°C)');
      if (delta > 5.0) {
        score -= math.min(20.0, 2.0 * delta);
        warnings.add('Defect map was built ${delta.toStringAsFixed(1)}°C from '
            'the current sensor temperature — hot-pixel sets shift with '
            'cooling setpoint.');
      }
    }
    score = _applyStaleness(score, best, reasons, warnings);
    return CalibrationMatch(
      record: best,
      score: _clampScore(score),
      reasons: reasons,
      warnings: warnings,
    );
  }

  // ---------------------------------------------------------------------------
  // Scoring helpers
  // ---------------------------------------------------------------------------

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
          '(Δ${delta.toStringAsFixed(1)}°C, tolerance ±$toleranceC°C)');
      score -= math.min(20.0, 4.0 * delta);
      if (fellBack || delta > toleranceC) {
        warnings.add(
            'Sensor temperature differs by ${delta.toStringAsFixed(1)}°C '
            'from the $label (tolerance ±$toleranceC°C).');
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
        warnings.add('${_typeLabel(record.type)} is $age days old '
            '(recommended refresh: every $staleDays days).');
        return score - 15;
      case CalibrationFreshness.aging:
        reasons.add('$age days old (aging; refresh recommended every '
            '$staleDays days)');
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

  static double _clampScore(double score) => score.clamp(0.0, 100.0);

  static String _fmtSecs(double secs) {
    final isWhole = secs == secs.roundToDouble();
    return isWhole ? '${secs.round()}s' : '${secs.toStringAsFixed(2)}s';
  }

  static String _fmtDate(DateTime when) =>
      when.toLocal().toIso8601String().split('T').first;

  static String _typeLabel(CalibrationMasterType type) {
    return switch (type) {
      CalibrationMasterType.dark => 'Master dark',
      CalibrationMasterType.bias => 'Master bias',
      CalibrationMasterType.flat => 'Master flat',
      CalibrationMasterType.defectMap => 'Defect map',
    };
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Riverpod provider for the [CalibrationLibraryService].
final calibrationLibraryServiceProvider =
    Provider<CalibrationLibraryService>((ref) {
  return CalibrationLibraryService(
    db: ref.watch(databaseProvider),
    flatLibraryDao: ref.watch(flatLibraryDaoProvider),
    tagsDao: ref.watch(calibrationTagsDaoProvider),
  );
});

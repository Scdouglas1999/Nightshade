import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../backend/network_backend.dart';
import '../backend/nightshade_backend.dart';
import '../database/daos/calibration_tags_dao.dart';
import '../database/daos/flat_library_dao.dart';
import '../database/database.dart';
import '../models/calibration/calibration_library_models.dart';
import '../models/calibration/shared_calibration_models.dart';
import '../models/collaboration/collaboration_models.dart';
import '../providers/backend_provider.dart';
import '../providers/constellation_provider.dart';
import '../providers/database_provider.dart';
import 'calibration/fits_header_reader.dart';
import 'calibration/shared_calibration_library.dart';

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
    Ref? ref,
    this.headerReader = const FitsHeaderReader(),
    this.thresholds = CalibrationStalenessThresholds.defaults,
    RemoteCalibrationLibrary? remoteLibrary,
    NightshadeBackend? backend,
    Future<String> Function()? sharedMasterDirResolver,
    DateTime Function()? now,
  }) : _db = db,
       _flatDao = flatLibraryDao,
       _tagsDao = tagsDao,
       _backend = backend ?? ref?.read(backendProvider),
       _backendNotifier = ref?.read(backendProvider.notifier),
       _remoteLibrary = remoteLibrary,
       _sharedMasterDirResolver = sharedMasterDirResolver,
       _now = now ?? DateTime.now;

  final NightshadeDatabase _db;
  final FlatLibraryDao _flatDao;
  final CalibrationTagsDao _tagsDao;
  final NightshadeBackend? _backend;
  final BackendNotifier? _backendNotifier;
  bool _retired = false;

  /// The hub-backed shared calibration library (WS1). When set, [match] folds
  /// ranked REMOTE candidates into the local ranking and [acceptRemoteMaster]
  /// can download + merge a chosen one. Null on a remote client (the appliance
  /// owns matching) and in wirings without a hub.
  final RemoteCalibrationLibrary? _remoteLibrary;

  /// Resolves the directory accepted remote masters are downloaded into. Null in
  /// wirings that never accept remote masters; [acceptRemoteMaster] then refuses
  /// rather than guessing a path.
  final Future<String> Function()? _sharedMasterDirResolver;

  final FitsHeaderReader headerReader;
  final CalibrationStalenessThresholds thresholds;
  final DateTime Function() _now;

  /// The active [NetworkBackend] when this device is a remote client (a tablet
  /// or desktop driving the headless appliance). When non-null, tag/note/
  /// delete/match operations target the APPLIANCE's real calibration library
  /// over `/api/calibration-library/*` instead of this device's local Drift
  /// DB (which on a remote client is empty). Null on the host / local builds,
  /// where the operations run against the local DB.
  NetworkBackend? get _remote {
    final backend = _backend;
    return backend is NetworkBackend ? backend : null;
  }

  bool get _hasAuthority {
    final backend = _backend;
    if (backend == null) return true;
    return !_retired && (_backendNotifier?.isCurrentBackend(backend) ?? false);
  }

  void retire() => _retired = true;

  void _ensureAuthority() {
    if (_hasAuthority) return;
    throw StateError(
      'The imaging host changed while the calibration library was loading. '
      'The stale result was discarded; try again on the current host.',
    );
  }

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
    _ensureAuthority();
    final remote = _remote;
    var records = remote == null
        ? await _loadAll()
        : [
            for (final row in await remote.getCalibrationMasters(
              type: filter.type == null
                  ? null
                  : calibrationMasterTypeWireName(filter.type!),
            ))
              CalibrationMasterRecord.fromJson(row),
          ];
    _ensureAuthority();

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
          .where(
            (r) =>
                r.exposureSeconds != null &&
                (r.exposureSeconds! - filter.exposureSeconds!).abs() <=
                    filter.exposureToleranceSecs,
          )
          .toList();
    }
    if (filter.temperatureMin != null) {
      records = records
          .where(
            (r) =>
                r.temperature != null &&
                r.temperature! >= filter.temperatureMin!,
          )
          .toList();
    }
    if (filter.temperatureMax != null) {
      records = records
          .where(
            (r) =>
                r.temperature != null &&
                r.temperature! <= filter.temperatureMax!,
          )
          .toList();
    }
    final filterName = filter.filter?.trim();
    if (filterName != null && filterName.isNotEmpty) {
      records = records
          .where(
            (r) =>
                r.filter != null &&
                r.filter!.trim().toLowerCase() == filterName.toLowerCase(),
          )
          .toList();
    }

    if (enrichFromHeaders && remote == null) {
      records = [for (final r in records) await _enrich(r)];
      _ensureAuthority();
    }

    final cameraId = filter.cameraId?.trim();
    if (cameraId != null && cameraId.isNotEmpty) {
      records = records.where((r) => r.cameraId == cameraId).toList();
    }

    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _ensureAuthority();
    return records;
  }

  /// One record by identity, or null. Enriched from the FITS header.
  Future<CalibrationMasterRecord?> getRecord(
    CalibrationMasterType type,
    int id,
  ) async {
    _ensureAuthority();
    final remote = _remote;
    final all = remote == null
        ? await _loadAll()
        : [
            for (final row in await remote.getCalibrationMasters(
              type: calibrationMasterTypeWireName(type),
            ))
              CalibrationMasterRecord.fromJson(row),
          ];
    _ensureAuthority();
    for (final record in all) {
      if (record.type == type && record.id == id) {
        if (remote != null) return record;
        final enriched = await _enrich(record);
        _ensureAuthority();
        return enriched;
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
  ///
  /// When a shared calibration library is configured ([_remoteLibrary]) and
  /// [includeRemote] is set, ranked REMOTE candidates are folded into the same
  /// per-type ranking (WS1): a downloaded master is preferred on an exact tuple
  /// tie (local-first), the quality gate refuses any whose sensor/dimensions do
  /// not match, and a REMOTE flat is only ever reused on an EXACT optical-train
  /// match (never across trains). The chosen remote master's provenance (frame
  /// count, dark current, who shot it, license) rides on the result so the user
  /// can trust what they pull, then [acceptRemoteMaster] downloads + merges it.
  Future<CalibrationMatchSet> match(
    LightFrameContext context, {
    CalibrationMatchTolerances tolerances = CalibrationMatchTolerances.defaults,
    bool includeRemote = true,
  }) async {
    final remote = _remote;
    if (remote != null) {
      // Remote client: the appliance owns the real master library, so the
      // host runs the matcher against its own DB and returns the transparent
      // per-type result.
      final result = await remote.matchCalibrationMasters(context);
      _ensureAuthority();
      return result;
    }
    final all = await _loadAll();
    String? remoteWarning;
    if (includeRemote && _remoteLibrary != null) {
      // Signed out is a NORMAL state, not a failure: no exception, no error log
      // — but it still means the shared library was not consulted, and an empty
      // remote set here must never read as "the hub had nothing to offer".
      if (!await _remoteLibrary.isConfigured()) {
        remoteWarning =
            'Not signed in to a shared calibration hub — shared masters were '
            'not consulted; showing local masters only.';
      } else {
        try {
          final candidates = await _remoteLibrary.queryCandidates(context);
          for (final candidate in candidates) {
            if (_remoteCandidatePasses(candidate, context)) all.add(candidate);
          }
        } on Object catch (e) {
          // Folding remote candidates is strictly additive and best-effort: a
          // hub failure must never degrade local matching, but the operator
          // must see that shared masters were not consulted (offline != 'none
          // exist').
          developer.log(
            'Remote calibration candidates skipped: $e',
            name: 'CalibrationLibraryService',
            level: 900,
          );
          remoteWarning =
              'Shared calibration hub unreachable — shared masters were not '
              'consulted; showing local masters only.';
        }
      }
    }
    final setWarnings = <String>[];
    if (remoteWarning != null) setWarnings.add(remoteWarning);

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
      final filterPart =
          (context.filter == null || context.filter!.trim().isEmpty)
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
  // Shared calibration libraries (WS1)
  // ---------------------------------------------------------------------------

  /// Download a REMOTE master surfaced by [match] and merge it into the local
  /// library, applying the WS1 quality + consent gates and conflict resolution:
  ///
  ///  * refuses a non-shareable license, a defect map, or a flat without an
  ///    optical-train tag (a flat is never reusable across trains);
  ///  * CONFLICT RESOLUTION — when a LOCAL master with the exact same tuple
  ///    already exists, prefers the local copy and does NOT download
  ///    ([RemoteMasterAcceptanceKind.preferredLocal]); otherwise downloads,
  ///    writes the file, and inserts a new artifact row + a provenance-stamped
  ///    `calibration_tags` annotation (keeping both)
  ///    ([RemoteMasterAcceptanceKind.merged]).
  ///
  /// AUTHORITY: only [remote]'s `remoteId` is trusted. Everything the matcher
  /// keys on — gain, offset, exposure, temperature, binning, sensor geometry,
  /// filter, optical train, license, provenance — is re-read from the hub's own
  /// row alongside the bytes and it is THAT record which is gated and filed.
  /// [remote] reaches this method across an untrusted boundary (a REST client
  /// posts a `/match` result back to `/api/calibration-library/accept`), so
  /// filing the caller's copy would let a mutated payload register real master
  /// bytes under a tuple they were never shot at — the matcher would then
  /// silently subtract the wrong master from future lights. A hub that supplies
  /// no authoritative record fails CLOSED (refused) rather than falling back to
  /// the caller's metadata.
  Future<RemoteMasterAcceptance> acceptRemoteMaster(
    CalibrationMasterRecord remote,
  ) async {
    if (!remote.isRemote) {
      throw ArgumentError('acceptRemoteMaster requires a remote record');
    }
    final library = _remoteLibrary;
    if (library == null) {
      throw StateError('no shared calibration library is configured');
    }
    // Cheap pre-gates on the caller's copy, purely to avoid spending a download
    // on an ask that cannot be accepted. Both outcomes are conservative — they
    // file nothing — so acting on untrusted metadata here is safe; the
    // authoritative versions of both gates run again after the download.
    final preRefusal = _acceptRefusal(remote);
    if (preRefusal != null) {
      return RemoteMasterAcceptance.refused(preRefusal);
    }
    final preLocal = await _loadAll();
    final preDuplicate = _exactLocalDuplicate(remote, preLocal);
    if (preDuplicate != null) {
      return RemoteMasterAcceptance.preferredLocal(preDuplicate);
    }

    final dirResolver = _sharedMasterDirResolver;
    if (dirResolver == null) {
      throw StateError('no shared-master download directory is configured');
    }
    final download = await library.downloadMaster(remote);
    final authority = download.master?.toMasterRecord(
      remote.sourceHubKey ?? '',
    );
    if (authority == null) {
      return RemoteMasterAcceptance.refused(
        'The hub did not return an authoritative record for this master, so '
        'the calibration tuple it would be filed under cannot be verified.',
      );
    }
    if (authority.remoteId != remote.remoteId) {
      return RemoteMasterAcceptance.refused(
        'The hub returned master ${authority.remoteId} for a request for '
        '${remote.remoteId}; refusing to file mismatched bytes.',
      );
    }

    // Re-run the consent/reuse gates against the HUB's record, not the
    // caller's: a caller could otherwise dress an un-shareable master (or a
    // train-less flat) in an acceptable-looking payload.
    final refusal = _acceptRefusal(authority);
    if (refusal != null) {
      return RemoteMasterAcceptance.refused(refusal);
    }
    // Conflict resolution: prefer a local exact-tuple master over the download.
    final local = await _loadAll();
    final duplicate = _exactLocalDuplicate(authority, local);
    if (duplicate != null) {
      return RemoteMasterAcceptance.preferredLocal(duplicate);
    }

    final dir = await dirResolver();
    final fileName =
        '${calibrationMasterTypeWireName(authority.type)}_'
        '${authority.remoteId}.fits';
    final destPath = '$dir/$fileName';
    final file = File(destPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(download.bytes, flush: true);

    final newId = await _insertAcceptedMaster(authority, destPath);
    return RemoteMasterAcceptance.merged(newId, destPath);
  }

  /// Publish a LOCAL master to the configured hub under [consent]'s license
  /// (consent-gated: refuses when the consent does not permit sharing). The
  /// trust signals (frame count, sensor dimensions, camera) are taken from the
  /// record; [provenance] supplies the rest (e.g. measured dark current).
  Future<SharedCalibrationMaster> publishMaster(
    CalibrationMasterRecord record, {
    required ContributionConsent consent,
    Provenance provenance = const Provenance(),
  }) async {
    final library = _remoteLibrary;
    if (library == null) {
      throw StateError('no shared calibration library is configured');
    }
    if (!consent.permitsSharing) {
      throw StateError(
        'consent does not permit sharing (license '
        '${consent.license.wireName})',
      );
    }
    if (record.type == CalibrationMasterType.defectMap) {
      throw StateError('defect maps cannot be shared');
    }
    if (record.type == CalibrationMasterType.flat &&
        (record.opticalTrainId == null ||
            record.opticalTrainId!.trim().isEmpty)) {
      throw StateError(
        'a flat can only be shared with an optical-train tag (flats are '
        'never reusable across optical trains)',
      );
    }
    final published = await library.publish(
      record: record,
      consent: consent,
      provenance: provenance,
    );
    // Record the hub master id locally so the master can later be retracted
    // (un-shared) — this is the owner-scoped retract handle the UI surfaces.
    await _tagsDao.upsert(
      record.type,
      record.id,
      publishedRemoteId: published.id,
    );
    return published;
  }

  /// Retract (un-share) a LOCAL master the user previously published to the hub.
  ///
  /// On a remote client the call routes to the appliance over REST (the rig owns
  /// the published row + its retract handle); locally it resolves the hub master
  /// id recorded at publish time, calls the hub's owner-scoped delete, and clears
  /// the local retract handle so the master shows as un-shared again. Throws a
  /// [StateError] when the master was never published or no hub is configured.
  Future<void> retractPublishedMaster(CalibrationMasterRecord record) async {
    final remote = _remote;
    if (remote != null) {
      await remote.retractCalibrationMaster(
        type: calibrationMasterTypeWireName(record.type),
        id: record.id,
      );
      return;
    }
    final library = _remoteLibrary;
    if (library == null) {
      throw StateError('no shared calibration library is configured');
    }
    final remoteId =
        record.publishedRemoteId ??
        (await _tagsDao.getForMaster(
          record.type,
          record.id,
        ))?.publishedRemoteId;
    if (remoteId == null || remoteId.isEmpty) {
      throw StateError('this master has not been published to a hub');
    }
    await library.retract(remoteId);
    await _tagsDao.upsert(record.type, record.id, clearPublishedRemoteId: true);
  }

  /// The reason a remote master is refused outright, or null when it may be
  /// accepted. Defense-in-depth: re-applies the consent + cross-train gates at
  /// accept time, not just at match-folding time.
  String? _acceptRefusal(CalibrationMasterRecord remote) {
    if (remote.type == CalibrationMasterType.defectMap) {
      return 'Defect maps are camera/firmware specific and are not shared.';
    }
    if (remote.license == null || !remote.license!.isShareable) {
      return 'This master is not shared under a reusable license.';
    }
    if (remote.type == CalibrationMasterType.flat &&
        (remote.opticalTrainId == null ||
            remote.opticalTrainId!.trim().isEmpty)) {
      return 'A shared flat without an optical-train tag is never reusable.';
    }
    return null;
  }

  /// The LOCAL master whose tuple exactly matches [remote] (so a download would
  /// be a duplicate), or null when none — the "keep both otherwise" branch.
  CalibrationMasterRecord? _exactLocalDuplicate(
    CalibrationMasterRecord remote,
    List<CalibrationMasterRecord> records,
  ) {
    for (final r in records) {
      if (r.isRemote) continue;
      if (r.type != remote.type) continue;
      if (r.gain != remote.gain ||
          r.offset != remote.offset ||
          r.binX != remote.binX ||
          r.binY != remote.binY) {
        continue;
      }
      if (!_sameOptional(r.cameraId, remote.cameraId)) continue;
      // Sensor dimensions must agree when both sides know them.
      if (r.width != null && remote.width != null && r.width != remote.width) {
        continue;
      }
      if (r.height != null &&
          remote.height != null &&
          r.height != remote.height) {
        continue;
      }
      switch (remote.type) {
        case CalibrationMasterType.dark:
          if (!_sameExposure(r.exposureSeconds, remote.exposureSeconds)) {
            continue;
          }
        case CalibrationMasterType.bias:
          break;
        case CalibrationMasterType.flat:
          if (!_sameOptional(r.filter, remote.filter)) continue;
          if (!_sameOptional(r.opticalTrainId, remote.opticalTrainId)) continue;
        case CalibrationMasterType.defectMap:
          continue;
      }
      return r;
    }
    return null;
  }

  /// Insert a downloaded master into its source table + a provenance-stamped
  /// `calibration_tags` row. Returns the new artifact id.
  Future<int> _insertAcceptedMaster(
    CalibrationMasterRecord remote,
    String destPath,
  ) async {
    final now = _now();
    final int newId;
    switch (remote.type) {
      case CalibrationMasterType.dark:
      case CalibrationMasterType.bias:
        newId = await _db
            .into(_db.darkLibrary)
            .insert(
              DarkLibraryCompanion.insert(
                filePath: destPath,
                exposureTime: remote.exposureSeconds ?? 0,
                frameType: Value(
                  remote.type == CalibrationMasterType.bias ? 'bias' : 'dark',
                ),
                temperature: Value(remote.temperature),
                gain: Value(remote.gain ?? 0),
                offset: Value(remote.offset ?? 0),
                binX: Value(remote.binX),
                binY: Value(remote.binY),
                width: Value(remote.width),
                height: Value(remote.height),
                masterDarkPath: Value(destPath),
                masterFrameCount: Value(remote.frameCount),
                createdAt: Value(now),
              ),
            );
      case CalibrationMasterType.flat:
        newId = await _flatDao.addEntry(
          filePath: destPath,
          filter: remote.filter,
          opticalTrainId: remote.opticalTrainId,
          temperature: remote.temperature,
          gain: remote.gain ?? 0,
          offset: remote.offset ?? 0,
          binX: remote.binX,
          binY: remote.binY,
          width: remote.width,
          height: remote.height,
          masterFrameCount: remote.frameCount ?? 0,
          createdAt: now,
        );
      case CalibrationMasterType.defectMap:
        throw StateError('defect maps cannot be merged');
    }
    final sharedBy =
        remote.sharedBy ??
        remote.provenance?.displayName ??
        remote.provenance?.accountId;
    await _tagsDao.upsert(
      remote.type,
      newId,
      cameraId: remote.cameraId,
      sharedBy: sharedBy,
      sharedAt: now,
      license: remote.license?.wireName,
      provenanceJson: remote.provenance?.toJsonString(),
    );
    return newId;
  }

  /// Whether a REMOTE candidate passes the WS1 quality gate for [ctx]. The gate
  /// FAILS CLOSED on the trust dimensions — a candidate is folded only when it
  /// is provably sensor-compatible, never when identity is merely unknown:
  ///  * a shareable license;
  ///  * a camera identity that the context names AND the candidate matches (an
  ///    unknown camera on either side is refused — a foreign sensor's
  ///    dark-current / hot-pixel / amp-glow pattern would silently corrupt
  ///    calibration);
  ///  * sensor dimensions the candidate advertises (a candidate with no recorded
  ///    geometry can never be proven sensor-matched, so it is refused), matching
  ///    the context's own geometry exactly when the context knows it;
  ///  * for a flat, an EXACT optical-train match (never train-less, never
  ///    cross-train). Cross-account flat reuse on a bare train name is additionally
  ///    prevented hub-side: `SharedCalibrationService.query` scopes flats to the
  ///    requesting owner, so a candidate that reaches here is same-owner already.
  bool _remoteCandidatePasses(
    CalibrationMasterRecord r,
    LightFrameContext ctx,
  ) {
    if (r.type == CalibrationMasterType.defectMap) return false;
    if (r.license == null || !r.license!.isShareable) return false;
    // Camera identity fails closed: refuse cross-/unknown-camera remotes.
    final wantCam = ctx.cameraId?.trim();
    if (wantCam == null || wantCam.isEmpty) return false;
    if (r.cameraId == null || r.cameraId!.trim() != wantCam) return false;
    // Sensor dimensions fail closed: a candidate that does not advertise its
    // geometry is refused; when the context knows its own geometry the candidate
    // must match it exactly.
    if (r.width == null || r.height == null) return false;
    final cw = ctx.sensorWidth;
    final ch = ctx.sensorHeight;
    if (cw != null && r.width != cw) return false;
    if (ch != null && r.height != ch) return false;
    if (r.type == CalibrationMasterType.flat) {
      final wantTrain = ctx.opticalTrainId?.trim();
      if (wantTrain == null || wantTrain.isEmpty) return false;
      if (r.opticalTrainId == null || r.opticalTrainId!.trim() != wantTrain) {
        return false;
      }
    }
    return true;
  }

  /// Append the trust-surfacing provenance lines for a REMOTE pick: who shared
  /// it, the supporting frame count / dark-current, and the reuse license, plus
  /// a soft "this is shared, verify it" warning.
  void _applyRemoteProvenance(
    CalibrationMasterRecord best,
    List<String> reasons,
    List<String> warnings,
  ) {
    if (!best.isRemote) return;
    final prov = best.provenance;
    final who = best.sharedBy ?? prov?.displayName ?? 'another member';
    final buffer = StringBuffer('Shared master from $who');
    final fc = best.frameCount ?? prov?.frameCount;
    if (fc != null) buffer.write(' ($fc frames');
    final dc = prov?.darkCurrent;
    if (dc != null) {
      buffer.write(
        '${fc != null ? ', ' : ' ('}dark current '
        '${dc.toStringAsFixed(3)} e-/px/s',
      );
    }
    if (fc != null || dc != null) buffer.write(')');
    if (best.license != null) {
      buffer.write(' — license ${best.license!.wireName}');
    }
    reasons.add(buffer.toString());
    warnings.add(
      'This is a SHARED master you did not capture — review its provenance '
      'before trusting your calibration to it.',
    );
  }

  static bool _sameOptional(String? a, String? b) {
    final na = a?.trim();
    final nb = b?.trim();
    if ((na == null || na.isEmpty) && (nb == null || nb.isEmpty)) return true;
    return na == nb;
  }

  static bool _sameExposure(double? a, double? b) {
    if (a == null || b == null) return a == b;
    return (a - b).abs() < 0.001;
  }

  // ---------------------------------------------------------------------------
  // Tagging
  // ---------------------------------------------------------------------------

  /// Replace the user tags of one master.
  Future<void> setTags(
    CalibrationMasterType type,
    int id,
    List<String> tags,
  ) async {
    final cleaned = [
      for (final t in tags)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    final remote = _remote;
    if (remote != null) {
      await remote.setCalibrationMasterTags(
        type: calibrationMasterTypeWireName(type),
        id: id,
        tags: cleaned,
      );
      return;
    }
    await _tagsDao.upsert(type, id, tags: cleaned);
  }

  /// Replace the notes of one master (null/empty clears them).
  Future<void> setNotes(
    CalibrationMasterType type,
    int id,
    String? notes,
  ) async {
    final cleaned = notes?.trim();
    final remote = _remote;
    if (remote != null) {
      await remote.setCalibrationMasterNotes(
        type: calibrationMasterTypeWireName(type),
        id: id,
        notes: cleaned,
      );
      return;
    }
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
    final remote = _remote;
    if (remote != null) {
      // The appliance owns the row + file. A 404 there surfaces as a thrown
      // ServerError (no_calibration_master); the caller reloads either way, so
      // success here means the host accepted the delete.
      await remote.deleteCalibrationMaster(
        type: calibrationMasterTypeWireName(type),
        id: id,
        deleteFile: deleteFile,
      );
      return true;
    }
    var found = false;
    switch (type) {
      case CalibrationMasterType.dark:
      case CalibrationMasterType.bias:
        final entry = await (_db.select(
          _db.darkLibrary,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (entry != null) {
          found = true;
          if (deleteFile) {
            await _deleteFileIfExists(entry.filePath);
            if (entry.masterDarkPath != null) {
              await _deleteFileIfExists(entry.masterDarkPath!);
            }
          }
          await (_db.delete(
            _db.darkLibrary,
          )..where((t) => t.id.equals(id))).go();
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
        final entry = await (_db.select(
          _db.defectMaps,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (entry != null) {
          found = true;
          if (deleteFile && entry.filePath != null) {
            await _deleteFileIfExists(entry.filePath!);
          }
          await (_db.delete(
            _db.defectMaps,
          )..where((t) => t.id.equals(id))).go();
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
      records.add(
        CalibrationMasterRecord(
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
          provenance: _provenanceFromTag(tag),
          license: _licenseFromTag(tag),
          sharedBy: tag?.sharedBy,
          publishedRemoteId: tag?.publishedRemoteId,
        ),
      );
    }

    final flatRows = await _flatDao.getAllEntries();
    for (final row in flatRows) {
      final tag = tagFor(CalibrationMasterType.flat, row.id);
      records.add(
        CalibrationMasterRecord(
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
          provenance: _provenanceFromTag(tag),
          license: _licenseFromTag(tag),
          sharedBy: tag?.sharedBy,
          publishedRemoteId: tag?.publishedRemoteId,
        ),
      );
    }

    final mapRows = await _db.select(_db.defectMaps).get();
    for (final row in mapRows) {
      final tag = tagFor(CalibrationMasterType.defectMap, row.id);
      records.add(
        CalibrationMasterRecord(
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
        ),
      );
    }

    return records;
  }

  /// Fill missing camera id / temperature / filter from the FITS primary
  /// header, caching the camera id in `calibration_tags`. Best-effort:
  /// returns the record unchanged when the file is missing or unreadable.
  Future<CalibrationMasterRecord> _enrich(
    CalibrationMasterRecord record,
  ) async {
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
        ? FitsHeaderReader.firstDouble(headers, const [
            'CCD-TEMP',
            'CCD_TEMP',
            'SET-TEMP',
          ])
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
      warnings.add(
        'Flat has no optical-train tag — verify it was shot with '
        'the current optical configuration ($wantTrain).',
      );
    }

    _applyRemoteProvenance(best, reasons, warnings);
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

  static Provenance? _provenanceFromTag(CalibrationTagEntry? tag) {
    final raw = tag?.provenanceJson;
    if (raw == null || raw.trim().isEmpty) return null;
    return Provenance.fromJsonString(raw);
  }

  static ContributionLicense? _licenseFromTag(CalibrationTagEntry? tag) {
    final raw = tag?.license;
    if (raw == null || raw.trim().isEmpty) return null;
    return ContributionLicense.fromWire(raw);
  }
}

/// What happened when a REMOTE master was accepted into the local library.
enum RemoteMasterAcceptanceKind {
  /// The master was downloaded and merged in as a new local artifact.
  merged,

  /// An exact-tuple LOCAL master already existed, so the local copy was kept and
  /// nothing was downloaded (conflict resolution: prefer local).
  preferredLocal,

  /// The master was refused by the quality/consent gate (e.g. non-shareable
  /// license, or a flat without an optical-train tag).
  refused,
}

/// The outcome of [CalibrationLibraryService.acceptRemoteMaster].
class RemoteMasterAcceptance {
  const RemoteMasterAcceptance._(
    this.kind, {
    this.mergedId,
    this.filePath,
    this.existing,
    this.reason,
  });

  factory RemoteMasterAcceptance.merged(int id, String filePath) =>
      RemoteMasterAcceptance._(
        RemoteMasterAcceptanceKind.merged,
        mergedId: id,
        filePath: filePath,
      );

  factory RemoteMasterAcceptance.preferredLocal(
    CalibrationMasterRecord existing,
  ) => RemoteMasterAcceptance._(
    RemoteMasterAcceptanceKind.preferredLocal,
    existing: existing,
  );

  factory RemoteMasterAcceptance.refused(String reason) =>
      RemoteMasterAcceptance._(
        RemoteMasterAcceptanceKind.refused,
        reason: reason,
      );

  final RemoteMasterAcceptanceKind kind;

  /// The new local artifact id (set only when [kind] is `merged`).
  final int? mergedId;

  /// The downloaded file path (set only when [kind] is `merged`).
  final String? filePath;

  /// The kept local master (set only when [kind] is `preferredLocal`).
  final CalibrationMasterRecord? existing;

  /// Why the master was refused (set only when [kind] is `refused`).
  final String? reason;

  bool get accepted => kind == RemoteMasterAcceptanceKind.merged;
}

/// Riverpod provider for the [CalibrationLibraryService].
final calibrationLibraryServiceProvider = Provider<CalibrationLibraryService>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  final settings = ref.watch(settingsDaoProvider);
  final service = CalibrationLibraryService(
    db: ref.watch(databaseProvider),
    flatLibraryDao: ref.watch(flatLibraryDaoProvider),
    tagsDao: ref.watch(calibrationTagsDaoProvider),
    ref: ref,
    backend: backend,
    // WS1: fold ranked masters shared on the configured Constellation hub into
    // the local ranking, and download-on-accept. Reuses the same settings-backed
    // hub credentials Pillar C resolves; a no-hub config simply yields no remote
    // candidates.
    remoteLibrary: HubCalibrationLibrary(
      credentialsResolver: () => resolveConstellationCredentials(settings),
    ),
    sharedMasterDirResolver: () async {
      final dir = await getApplicationSupportDirectory();
      return p.join(dir.path, 'shared_calibration');
    },
  );
  ref.onDispose(service.retire);
  return service;
});

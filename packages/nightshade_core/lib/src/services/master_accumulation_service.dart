import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/integrated_masters_dao.dart';
import '../database/database.dart';
import '../models/calibration/dark_library_match_tolerances.dart';
import '../models/imaging/integrated_master.dart';
import '../models/imaging/integration_settings.dart';
import '../providers/dark_library_provider.dart';
import 'dark_library_service.dart';
import 'flat_library_service.dart';
import 'post_session_seam.dart';

/// Drives the **multi-night accumulating master** workflow on top of the native
/// `api_master_accumulate` (create / add / finalize / info) FFI op.
///
/// The headline post-session feature: keep folding new nights' accepted subs
/// into an existing master over time without re-reading old subs. The resumable
/// accumulator state lives in a `.nsmaster` sidecar (the native side owns it);
/// this service owns the *bookkeeping* — the `integrated_masters` row (status
/// `accumulating`, mode `runningWeightedMean`), the per-sub `integrated_master_frames`
/// fold records, and the dedup that prevents a sub being folded twice.
///
/// Idempotency / dedup: [addNight] subtracts the already-folded `image_id`s
/// (from [IntegratedMastersDao.getFoldedImageIds]) from the supplied subs before
/// the native `add`, so re-running an add with overlapping subs never
/// double-counts. This echoes the cross-stream dedup concern in project memory.
class MasterAccumulationService {
  MasterAccumulationService({
    required IntegratedMastersDao mastersDao,
    required DarkLibraryService darkLibrary,
    required FlatLibraryService flatLibrary,
    required PostSessionSeam seam,
    DarkLibraryMatchTolerances darkTolerances =
        DarkLibraryMatchTolerances.defaults,
  }) : _mastersDao = mastersDao,
       _darkLibrary = darkLibrary,
       _flatLibrary = flatLibrary,
       _seam = seam,
       _darkTolerances = darkTolerances;

  final IntegratedMastersDao _mastersDao;
  final DarkLibraryService _darkLibrary;
  final FlatLibraryService _flatLibrary;
  final PostSessionSeam _seam;

  /// Dark-frame match tolerances, resolved from
  /// [darkLibraryMatchTolerancesProvider] at the provider boundary so this
  /// post-session accumulation matcher agrees with the coverage UI and the live
  /// calibration path. Previously this call used the code defaults (±1.0°C),
  /// which could silently disagree with the ±2.0°C the rest of the app uses.
  final DarkLibraryMatchTolerances _darkTolerances;

  /// Create a new accumulating master for [targetId] / [filter] from a
  /// [referenceSub] (the frozen geometric + photometric anchor).
  ///
  /// Writes the sidecar at [sidecarPath] and inserts the `integrated_masters`
  /// row in status `accumulating`. Returns the new master id.
  Future<int> createMaster({
    required CapturedImage referenceSub,
    required String sidecarPath,
    IntegrationSettings settings = IntegrationSettings.defaults,
    int? targetId,
    String? targetName,
    String? filter,
    double? onlineClipLow = 4.0,
    double? onlineClipHigh = 4.0,
  }) async {
    final result = await _seam.masterAccumulate({
      'op': 'create',
      'referencePath': referenceSub.filePath,
      'sidecarPath': sidecarPath,
      'settings': {
        if (onlineClipLow != null) 'onlineClipLow': onlineClipLow,
        if (onlineClipHigh != null) 'onlineClipHigh': onlineClipHigh,
      },
      if (filter != null && filter.trim().isNotEmpty) 'filter': filter.trim(),
      if (targetName != null && targetName.trim().isNotEmpty)
        'target': targetName.trim(),
    });

    return _mastersDao.insertMaster(
      targetId: targetId,
      name: _masterName(targetName: targetName, filter: filter),
      masterFitsPath: null,
      previewPngPath: null,
      sidecarPath: result.sidecarPath,
      rejectionMapPath: null,
      status: IntegratedMasterStatus.accumulating,
      accumulationMode: AccumulationMode.runningWeightedMean,
      channels: result.channels,
      width: result.width,
      height: result.height,
      frameCount: result.frameCount,
      totalIntegrationSeconds: result.totalIntegrationSec,
      filter: (filter != null && filter.trim().isNotEmpty)
          ? filter.trim()
          : null,
      settingsJson: settings.toJsonString(),
      statsJson: '{}',
    );
  }

  /// Fold a new night's accepted [subs] into the accumulating master [masterId].
  ///
  /// Subs already folded (tracked in `integrated_master_frames`) are skipped.
  /// Calibration is resolved per sub-group from the master's filter + the subs'
  /// shared capture parameters. The master's running totals + fold records are
  /// updated. [label] is recorded in the native fold log (an ISO date / session
  /// id). [biasPath] is the optional master-bias override.
  ///
  /// Returns the [MasterAccumulateResult] from the native add. Throws
  /// [StateError] when the master is missing or has no sidecar, and
  /// [ArgumentError] when [subs] is empty.
  Future<MasterAccumulateResult> addNight({
    required int masterId,
    required List<CapturedImage> subs,
    required String label,
    IntegrationSettings settings = IntegrationSettings.defaults,
    String? biasPath,
  }) async {
    if (subs.isEmpty) {
      throw ArgumentError.value(subs, 'subs', 'must not be empty');
    }
    final master = await _mastersDao.getById(masterId);
    if (master == null) {
      throw StateError('Integrated master $masterId not found');
    }
    final sidecar = master.sidecarPath;
    if (sidecar == null || sidecar.trim().isEmpty) {
      throw StateError(
        'Master $masterId has no accumulator sidecar; it is not an '
        'accumulating master',
      );
    }

    // Dedup: drop subs already folded into this master.
    final already = await _mastersDao.getFoldedImageIds(masterId);
    final fresh = subs.where((s) => !already.contains(s.id)).toList();
    if (fresh.isEmpty) {
      // Nothing new — return current totals without touching the sidecar.
      return _seam.masterAccumulate({'op': 'info', 'sidecarPath': sidecar});
    }

    final calibration = await _resolveCalibration(
      subs: fresh,
      filter: master.filter,
      biasPath: biasPath,
      cosmeticCorrection: settings.cosmeticCorrection,
    );

    final result = await _seam.masterAccumulate({
      'op': 'add',
      'sidecarPath': sidecar,
      'lightPaths': fresh.map((s) => s.filePath).toList(),
      'exposuresSec': fresh
          .map((s) => s.exposureDuration)
          .toList(growable: false),
      'label': label,
      'calibration': calibration,
      'settings': settings.toBridgeSettings(),
    });

    // Record each freshly-folded sub. The native add path either folds a sub or
    // fails the whole call (it does not partially accept), so on success every
    // `fresh` sub contributed. The native result carries the per-frame
    // integration weight in `lightPaths` order — which is `fresh` order — so we
    // persist each sub's real weight (rather than null) to feed the multi-night
    // growth / best-night intelligence. A weight that came back <= 0 (frame
    // effectively dropped) is stored as null, matching the batch path.
    final weights = result.frameWeights;
    for (var i = 0; i < fresh.length; i++) {
      final w = i < weights.length ? weights[i] : null;
      await _mastersDao.recordFoldedFrame(
        masterId: masterId,
        imageId: fresh[i].id,
        weight: (w != null && w > 0) ? w : null,
        accepted: true,
      );
    }

    await _mastersDao.updateBookkeeping(
      masterId,
      frameCount: result.frameCount,
      totalIntegrationSeconds: result.totalIntegrationSec,
      channels: result.channels,
      width: result.width,
      height: result.height,
    );

    return result;
  }

  /// Finalize the accumulating master [masterId] — write its shareable FITS to
  /// [masterFitsPath] (+ optional preview) and stamp the path/status onto the
  /// `integrated_masters` row.
  ///
  /// The status flips to `finalized`, but the sidecar is retained so more nights
  /// can still be added and the master re-finalized.
  Future<MasterAccumulateResult> finalizeMaster({
    required int masterId,
    required String masterFitsPath,
    String? previewPngPath,
  }) async {
    final master = await _mastersDao.getById(masterId);
    if (master == null) {
      throw StateError('Integrated master $masterId not found');
    }
    final sidecar = master.sidecarPath;
    if (sidecar == null || sidecar.trim().isEmpty) {
      throw StateError('Master $masterId has no accumulator sidecar');
    }

    final result = await _seam.masterAccumulate({
      'op': 'finalize',
      'sidecarPath': sidecar,
      'masterFitsPath': masterFitsPath,
      if (previewPngPath != null && previewPngPath.trim().isNotEmpty)
        'previewPngPath': previewPngPath,
    });

    await _mastersDao.updateBookkeeping(
      masterId,
      masterFitsPath: result.masterPath ?? masterFitsPath,
      previewPngPath: result.previewPath,
      status: IntegratedMasterStatus.finalized,
      frameCount: result.frameCount,
      totalIntegrationSeconds: result.totalIntegrationSec,
      channels: result.channels,
      width: result.width,
      height: result.height,
    );

    return result;
  }

  /// Read the live accumulator totals from the sidecar without modifying it.
  Future<MasterAccumulateResult> info(int masterId) async {
    final master = await _mastersDao.getById(masterId);
    if (master == null) {
      throw StateError('Integrated master $masterId not found');
    }
    final sidecar = master.sidecarPath;
    if (sidecar == null || sidecar.trim().isEmpty) {
      throw StateError('Master $masterId has no accumulator sidecar');
    }
    return _seam.masterAccumulate({'op': 'info', 'sidecarPath': sidecar});
  }

  Future<Map<String, dynamic>> _resolveCalibration({
    required List<CapturedImage> subs,
    String? filter,
    String? biasPath,
    required bool cosmeticCorrection,
  }) async {
    final anchor = subs.first;
    final gain = anchor.gain ?? 0;
    final offset = anchor.offset ?? 0;
    final binX = anchor.binX;
    final binY = anchor.binY;
    final temperature = anchor.sensorTemp;
    final matchFilter = (filter != null && filter.trim().isNotEmpty)
        ? filter.trim()
        : anchor.filter;

    final dark = await _darkLibrary.findMatchingDark(
      exposureTime: anchor.exposureDuration,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
      temperature: temperature,
      tolerances: _darkTolerances,
    );
    final flat = await _flatLibrary.findBestMatch(
      filter: matchFilter,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
      temperature: temperature,
    );

    final darkPath = dark?.masterDarkPath ?? dark?.filePath;
    return {
      if (darkPath != null) 'dark': darkPath,
      if (flat != null) 'flat': flat.filePath,
      if (biasPath != null && biasPath.trim().isNotEmpty) 'bias': biasPath,
      'cosmeticCorrection': cosmeticCorrection,
    };
  }

  String _masterName({String? targetName, String? filter}) {
    final base = (targetName != null && targetName.trim().isNotEmpty)
        ? targetName.trim()
        : 'Master';
    final f = (filter != null && filter.trim().isNotEmpty)
        ? filter.trim()
        : null;
    return f != null ? '$base · $f' : base;
  }
}

/// Provider for the [MasterAccumulationService].
final masterAccumulationServiceProvider = Provider<MasterAccumulationService>((
  ref,
) {
  return MasterAccumulationService(
    mastersDao: ref.watch(integratedMastersDaoProvider),
    darkLibrary: ref.watch(darkLibraryServiceProvider),
    flatLibrary: ref.watch(flatLibraryServiceProvider),
    seam: ref.watch(postSessionSeamProvider),
    darkTolerances: ref.watch(darkLibraryMatchTolerancesProvider),
  );
});

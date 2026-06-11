part of '../science_provider.dart';

class ScienceSessionConfigController {
  final Ref _ref;

  ScienceSessionConfigController(this._ref);

  Future<void> save(int sessionId, ScienceSessionConfig config) async {
    final backend = _ref.read(backendProvider);
    final resolved = config.copyWith(sessionId: sessionId);
    if (backend is NetworkBackend) {
      await backend.updateScienceSessionConfig(sessionId, resolved);
      return;
    }
    await _ref.read(scienceDaoProvider).upsertSessionConfig(resolved);
  }
}

final scienceSessionConfigControllerProvider =
    Provider<ScienceSessionConfigController>((ref) {
      return ScienceSessionConfigController(ref);
    });

final scienceSessionConfigProvider =
    StreamProvider.family<ScienceSessionConfig?, int>((ref, sessionId) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return _pollRemoteScienceSessionConfig(backend, sessionId);
      }
      return ref.watch(scienceDaoProvider).watchSessionConfig(sessionId).map((
        row,
      ) {
        if (row == null) {
          return null;
        }
        return ScienceSessionConfig(
          sessionId: row.sessionId,
          photometryEnabled: row.photometryEnabled,
          calibrationEnabled: row.calibrationEnabled,
          transparencyEnabled: row.transparencyEnabled,
          psfMapEnabled: row.psfMapEnabled,
          residualsEnabled: row.residualsEnabled,
          movingObjectsEnabled: row.movingObjectsEnabled,
          narrowbandEnabled: row.narrowbandEnabled,
          psfGridRows: row.psfGridRows,
          psfGridCols: row.psfGridCols,
          transparencyAlertThreshold: row.transparencyAlertThreshold,
        );
      });
    });

final activeScienceSessionConfigProvider =
    Provider<AsyncValue<ScienceSessionConfig?>>((ref) {
      final sessionId = ref.watch(sessionStateProvider).dbSessionId;
      if (sessionId == null) {
        return const AsyncValue.data(null);
      }
      return ref.watch(scienceSessionConfigProvider(sessionId));
    });

final _remoteScienceSessionBundleProvider =
    FutureProvider.family<RemoteScienceBundle, int>((ref, sessionId) async {
      final backend = ref.watch(backendProvider);
      if (backend is! NetworkBackend) {
        throw StateError('Remote science bundle requested in local mode');
      }
      final bundle = await backend.getScienceSessionBundle(sessionId);
      Timer? timer;
      ref.onDispose(() => timer?.cancel());
      timer = Timer.periodic(const Duration(seconds: 10), (_) {
        ref.invalidateSelf();
      });
      return bundle;
    });

final _remoteSessionlessScienceBundleProvider =
    FutureProvider<RemoteScienceBundle>((ref) async {
      final backend = ref.watch(backendProvider);
      if (backend is! NetworkBackend) {
        throw StateError(
          'Remote sessionless science bundle requested in local mode',
        );
      }
      final bundle = await backend.getSessionlessScienceBundle();
      Timer? timer;
      ref.onDispose(() => timer?.cancel());
      timer = Timer.periodic(const Duration(seconds: 10), (_) {
        ref.invalidateSelf();
      });
      return bundle;
    });

final sessionPhotometryProvider =
    StreamProvider.family<List<PhotometryMeasurementRow>, int>((
      ref,
      sessionId,
    ) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.photometry),
              loading: () => Stream.value(const <PhotometryMeasurementRow>[]),
              error: (_, __) =>
                  Stream.value(const <PhotometryMeasurementRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchPhotometryForSession(sessionId);
    });

final sessionFrameCalibrationsProvider =
    StreamProvider.family<List<FramePhotometricCalibrationRow>, int>((
      ref,
      sessionId,
    ) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.calibrations),
              loading: () =>
                  Stream.value(const <FramePhotometricCalibrationRow>[]),
              error: (_, __) =>
                  Stream.value(const <FramePhotometricCalibrationRow>[]),
            );
      }
      return ref
          .watch(scienceDaoProvider)
          .watchCalibrationsForSession(sessionId);
    });

final sessionTransparencySamplesProvider =
    StreamProvider.family<List<TransparencySampleRow>, int>((ref, sessionId) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.transparency),
              loading: () => Stream.value(const <TransparencySampleRow>[]),
              error: (_, __) => Stream.value(const <TransparencySampleRow>[]),
            );
      }
      return ref
          .watch(scienceDaoProvider)
          .watchTransparencyForSession(sessionId);
    });

final sessionPsfTilesProvider =
    StreamProvider.family<List<PsfFieldTileRow>, int>((ref, sessionId) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.psfTiles),
              loading: () => Stream.value(const <PsfFieldTileRow>[]),
              error: (_, __) => Stream.value(const <PsfFieldTileRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchPsfTilesForSession(sessionId);
    });

final sessionFrameQualityMetricsProvider =
    StreamProvider.family<List<ScienceFrameQualityMetricsRow>, int>((
      ref,
      sessionId,
    ) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.frameQuality),
              loading: () =>
                  Stream.value(const <ScienceFrameQualityMetricsRow>[]),
              error: (_, __) =>
                  Stream.value(const <ScienceFrameQualityMetricsRow>[]),
            );
      }
      return ref
          .watch(scienceDaoProvider)
          .watchFrameQualityMetricsForSession(sessionId);
    });

final sessionTileMetricsProvider =
    StreamProvider.family<List<ScienceTileMetricRow>, int>((ref, sessionId) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.tileMetrics),
              loading: () => Stream.value(const <ScienceTileMetricRow>[]),
              error: (_, __) => Stream.value(const <ScienceTileMetricRow>[]),
            );
      }
      return ref
          .watch(scienceDaoProvider)
          .watchTileMetricsForSession(sessionId);
    });

final sessionResidualVectorsProvider =
    StreamProvider.family<List<AstrometryResidualVectorRow>, int>((
      ref,
      sessionId,
    ) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.residuals),
              loading: () =>
                  Stream.value(const <AstrometryResidualVectorRow>[]),
              error: (_, __) =>
                  Stream.value(const <AstrometryResidualVectorRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchResidualsForSession(sessionId);
    });

final sessionMovingObjectCandidatesProvider =
    StreamProvider.family<List<MovingObjectCandidateRow>, int>((
      ref,
      sessionId,
    ) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.movingObjects),
              loading: () => Stream.value(const <MovingObjectCandidateRow>[]),
              error: (_, __) =>
                  Stream.value(const <MovingObjectCandidateRow>[]),
            );
      }
      return ref
          .watch(scienceDaoProvider)
          .watchMovingObjectsForSession(sessionId);
    });

final sessionLineRatioProductsProvider =
    StreamProvider.family<List<LineRatioProductRow>, int>((ref, sessionId) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteScienceSessionBundleProvider(sessionId))
            .when(
              data: (bundle) => Stream.value(bundle.lineRatios),
              loading: () => Stream.value(const <LineRatioProductRow>[]),
              error: (_, __) => Stream.value(const <LineRatioProductRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchLineRatiosForSession(sessionId);
    });

final sessionLightCurveProvider =
    Provider.family<List<LightCurvePoint>, (int sessionId, String objectId)>((
      ref,
      args,
    ) {
      final photometry =
          ref.watch(sessionPhotometryProvider(args.$1)).valueOrNull ?? const [];

      return photometry
          // Drop rows with no measured magnitude: a coerced 0.0 is junk for the
          // charts (a spurious mag-0 point) and triggers a false ~14-mag
          // "brightening" in the Narrator's LightCurveEventDetector.
          .where(
            (row) =>
                row.objectId == args.$2 && row.differentialMagnitude != null,
          )
          .map(
            (row) => LightCurvePoint(
              timestamp: row.timestamp,
              flux: row.flux,
              differentialMagnitude: row.differentialMagnitude!,
              snr: row.snr ?? 0.0,
              uncertainty: row.uncertainty ?? 0.0,
            ),
          )
          .toList(growable: false);
    });

final sessionTransparencyTrendProvider =
    Provider.family<List<TransparencyTrendPoint>, int>((ref, sessionId) {
      final rows =
          ref
              .watch(sessionTransparencySamplesProvider(sessionId))
              .valueOrNull ??
          const [];
      return rows
          .map(
            (row) => TransparencyTrendPoint(
              timestamp: row.timestamp,
              transparencyPercent: row.transparencyPercent,
              extinctionCoefficient: row.extinctionCoefficient,
            ),
          )
          .toList(growable: false);
    });

final sessionMovingObjectTrendProvider =
    Provider.family<List<MovingObjectCandidate>, int>((ref, sessionId) {
      final rows =
          ref
              .watch(sessionMovingObjectCandidatesProvider(sessionId))
              .valueOrNull ??
          const [];
      return rows
          .map(
            (row) => MovingObjectCandidate(
              timestamp: row.timestamp,
              candidateId: row.candidateId,
              confidence: row.confidence,
              motionArcsecPerMinute: row.motionArcsecPerMinute,
              objectName: row.objectName,
            ),
          )
          .toList(growable: false);
    });

// =========================================================================
// Sessionless (standalone snapshot) providers
// =========================================================================

final sessionlessCalibrationsProvider =
    StreamProvider<List<FramePhotometricCalibrationRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.calibrations),
              loading: () =>
                  Stream.value(const <FramePhotometricCalibrationRow>[]),
              error: (_, __) =>
                  Stream.value(const <FramePhotometricCalibrationRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchSessionlessCalibrationsRecent();
    });

final sessionlessTransparencySamplesProvider =
    StreamProvider<List<TransparencySampleRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.transparency),
              loading: () => Stream.value(const <TransparencySampleRow>[]),
              error: (_, __) => Stream.value(const <TransparencySampleRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchSessionlessTransparencyRecent();
    });

final sessionlessPsfTilesProvider = StreamProvider<List<PsfFieldTileRow>>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref
        .watch(_remoteSessionlessScienceBundleProvider)
        .when(
          data: (bundle) => Stream.value(bundle.psfTiles),
          loading: () => Stream.value(const <PsfFieldTileRow>[]),
          error: (_, __) => Stream.value(const <PsfFieldTileRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchSessionlessPsfTilesRecent();
});

final sessionlessFrameQualityMetricsProvider =
    StreamProvider<List<ScienceFrameQualityMetricsRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.frameQuality),
              loading: () =>
                  Stream.value(const <ScienceFrameQualityMetricsRow>[]),
              error: (_, __) =>
                  Stream.value(const <ScienceFrameQualityMetricsRow>[]),
            );
      }
      return ref
          .watch(scienceDaoProvider)
          .watchSessionlessFrameQualityMetricsRecent();
    });

final sessionlessTileMetricsProvider =
    StreamProvider<List<ScienceTileMetricRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.tileMetrics),
              loading: () => Stream.value(const <ScienceTileMetricRow>[]),
              error: (_, __) => Stream.value(const <ScienceTileMetricRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchSessionlessTileMetricsRecent();
    });

final sessionlessResidualVectorsProvider =
    StreamProvider<List<AstrometryResidualVectorRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.residuals),
              loading: () =>
                  Stream.value(const <AstrometryResidualVectorRow>[]),
              error: (_, __) =>
                  Stream.value(const <AstrometryResidualVectorRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchSessionlessResidualsRecent();
    });

final sessionlessMovingObjectCandidatesProvider =
    StreamProvider<List<MovingObjectCandidateRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.movingObjects),
              loading: () => Stream.value(const <MovingObjectCandidateRow>[]),
              error: (_, __) =>
                  Stream.value(const <MovingObjectCandidateRow>[]),
            );
      }
      return ref
          .watch(scienceDaoProvider)
          .watchSessionlessMovingObjectsRecent();
    });

final sessionlessPhotometryProvider =
    StreamProvider<List<PhotometryMeasurementRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.photometry),
              loading: () => Stream.value(const <PhotometryMeasurementRow>[]),
              error: (_, __) =>
                  Stream.value(const <PhotometryMeasurementRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchSessionlessPhotometryRecent();
    });

final sessionlessLineRatioProductsProvider =
    StreamProvider<List<LineRatioProductRow>>((ref) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return ref
            .watch(_remoteSessionlessScienceBundleProvider)
            .when(
              data: (bundle) => Stream.value(bundle.lineRatios),
              loading: () => Stream.value(const <LineRatioProductRow>[]),
              error: (_, __) => Stream.value(const <LineRatioProductRow>[]),
            );
      }
      return ref.watch(scienceDaoProvider).watchSessionlessLineRatiosRecent();
    });

final sessionlessLightCurveProvider =
    Provider.family<List<LightCurvePoint>, String>((ref, objectId) {
      final photometry =
          ref.watch(sessionlessPhotometryProvider).valueOrNull ?? const [];

      return photometry
          // Drop rows with no measured magnitude (see sessionLightCurveProvider).
          .where(
            (row) =>
                row.objectId == objectId && row.differentialMagnitude != null,
          )
          .map(
            (row) => LightCurvePoint(
              timestamp: row.timestamp,
              flux: row.flux,
              differentialMagnitude: row.differentialMagnitude!,
              snr: row.snr ?? 0.0,
              uncertainty: row.uncertainty ?? 0.0,
            ),
          )
          .toList(growable: false);
    });

final sessionlessTransparencyTrendProvider =
    Provider<List<TransparencyTrendPoint>>((ref) {
      final rows =
          ref.watch(sessionlessTransparencySamplesProvider).valueOrNull ??
          const [];
      return rows
          .map(
            (row) => TransparencyTrendPoint(
              timestamp: row.timestamp,
              transparencyPercent: row.transparencyPercent,
              extinctionCoefficient: row.extinctionCoefficient,
            ),
          )
          .toList(growable: false);
    });

final currentScienceSnapshotProvider =
    Provider<(FramePhotometricCalibrationRow?, TransparencySampleRow?)>((ref) {
      final sessionId = ref.watch(sessionStateProvider).dbSessionId;

      List<FramePhotometricCalibrationRow> calibrations;
      List<TransparencySampleRow> transparency;

      if (sessionId != null) {
        calibrations =
            ref
                .watch(sessionFrameCalibrationsProvider(sessionId))
                .valueOrNull ??
            const [];
        transparency =
            ref
                .watch(sessionTransparencySamplesProvider(sessionId))
                .valueOrNull ??
            const [];
      } else {
        // Fall back to sessionless data for standalone captures
        calibrations =
            ref.watch(sessionlessCalibrationsProvider).valueOrNull ?? const [];
        transparency =
            ref.watch(sessionlessTransparencySamplesProvider).valueOrNull ??
            const [];
      }

      return (
        calibrations.isEmpty ? null : calibrations.last,
        transparency.isEmpty ? null : transparency.last,
      );
    });

final currentScienceFrameProductsProvider =
    Provider.family<
      (ScienceFrameQualityMetricsRow?, List<ScienceTileMetricRow>),
      (int sessionId, int? capturedImageId)
    >((ref, args) {
      final frameMetrics =
          ref.watch(sessionFrameQualityMetricsProvider(args.$1)).valueOrNull ??
          const <ScienceFrameQualityMetricsRow>[];
      final tileMetrics =
          ref.watch(sessionTileMetricsProvider(args.$1)).valueOrNull ??
          const <ScienceTileMetricRow>[];

      ScienceFrameQualityMetricsRow? selectedMetric;
      if (args.$2 != null) {
        for (final metric in frameMetrics.reversed) {
          if (metric.capturedImageId == args.$2) {
            selectedMetric = metric;
            break;
          }
        }
      }
      selectedMetric ??= frameMetrics.isEmpty ? null : frameMetrics.last;

      final targetImageId = args.$2 ?? selectedMetric?.capturedImageId;
      final selectedTiles = targetImageId == null
          ? const <ScienceTileMetricRow>[]
          : tileMetrics
                .where((tile) => tile.capturedImageId == targetImageId)
                .toList(growable: false);

      return (selectedMetric, selectedTiles);
    });

Future<Map<String, String>> _loadScienceSettingsMap(Ref ref) async {
  final backend = ref.read(backendProvider);
  if (backend is NetworkBackend) {
    return backend.getScienceSettings();
  }
  return ref.read(settingsDaoProvider).getAllSettings();
}

Future<void> _writeScienceSettings(
  Ref ref,
  Map<String, String> settings,
) async {
  final backend = ref.read(backendProvider);
  if (backend is NetworkBackend) {
    await backend.updateScienceSettings(settings);
    ref.invalidate(scienceSettingsProvider);
    ref.invalidate(sciencePhotometrySelectionProvider);
    ref.invalidate(scienceVisualizationPrefsProvider);
    return;
  }
  await ref.read(settingsDaoProvider).setSettings(settings);
}

Stream<ScienceSessionConfig?> _pollRemoteScienceSessionConfig(
  NetworkBackend backend,
  int sessionId,
) async* {
  yield await backend.getScienceSessionConfig(sessionId);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await backend.getScienceSessionConfig(sessionId);
  }
}

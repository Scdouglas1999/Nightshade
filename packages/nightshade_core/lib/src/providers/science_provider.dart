import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart'
    show
        PhotometryMeasurementRow,
        FramePhotometricCalibrationRow,
        TransparencySampleRow,
        PsfFieldTileRow,
        ScienceFrameQualityMetricsRow,
        ScienceTileMetricRow,
        AstrometryResidualVectorRow,
        MovingObjectCandidateRow,
        LineRatioProductRow;
import '../models/science/science_models.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import '../backend/network_backend.dart';
import 'session_provider.dart';

class ScienceSettings {
  final bool advancedModeEnabled;
  final bool overlayEnabled;
  final bool photometryEnabled;
  final bool photometricCalibrationEnabled;
  final bool transparencyEnabled;
  final bool psfMapEnabled;
  final bool astrometricResidualsEnabled;
  final bool movingObjectsEnabled;
  final bool narrowbandRatiosEnabled;
  final bool frameQualityMapsEnabled;
  final bool surface3dEnabled;
  final bool manualPurgeOnly;

  /// MPC observatory code (3 characters, e.g. "G40").
  /// Required for generating Minor Planet Center reports.
  final String mpcObservatoryCode;

  /// AAVSO observer code (up to 5 characters, e.g. "XYZ").
  /// Required for generating AAVSO Extended Format reports.
  final String aavsoObserverCode;

  const ScienceSettings({
    this.advancedModeEnabled = false,
    this.overlayEnabled = true,
    this.photometryEnabled = true,
    this.photometricCalibrationEnabled = true,
    this.transparencyEnabled = true,
    this.psfMapEnabled = true,
    this.astrometricResidualsEnabled = true,
    this.movingObjectsEnabled = false,
    this.narrowbandRatiosEnabled = false,
    this.frameQualityMapsEnabled = true,
    this.surface3dEnabled = true,
    this.manualPurgeOnly = true,
    this.mpcObservatoryCode = '',
    this.aavsoObserverCode = '',
  });

  ScienceSettings copyWith({
    bool? advancedModeEnabled,
    bool? overlayEnabled,
    bool? photometryEnabled,
    bool? photometricCalibrationEnabled,
    bool? transparencyEnabled,
    bool? psfMapEnabled,
    bool? astrometricResidualsEnabled,
    bool? movingObjectsEnabled,
    bool? narrowbandRatiosEnabled,
    bool? frameQualityMapsEnabled,
    bool? surface3dEnabled,
    bool? manualPurgeOnly,
    String? mpcObservatoryCode,
    String? aavsoObserverCode,
  }) {
    return ScienceSettings(
      advancedModeEnabled: advancedModeEnabled ?? this.advancedModeEnabled,
      overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      photometryEnabled: photometryEnabled ?? this.photometryEnabled,
      photometricCalibrationEnabled:
          photometricCalibrationEnabled ?? this.photometricCalibrationEnabled,
      transparencyEnabled: transparencyEnabled ?? this.transparencyEnabled,
      psfMapEnabled: psfMapEnabled ?? this.psfMapEnabled,
      astrometricResidualsEnabled:
          astrometricResidualsEnabled ?? this.astrometricResidualsEnabled,
      movingObjectsEnabled: movingObjectsEnabled ?? this.movingObjectsEnabled,
      narrowbandRatiosEnabled:
          narrowbandRatiosEnabled ?? this.narrowbandRatiosEnabled,
      frameQualityMapsEnabled:
          frameQualityMapsEnabled ?? this.frameQualityMapsEnabled,
      surface3dEnabled: surface3dEnabled ?? this.surface3dEnabled,
      manualPurgeOnly: manualPurgeOnly ?? this.manualPurgeOnly,
      mpcObservatoryCode: mpcObservatoryCode ?? this.mpcObservatoryCode,
      aavsoObserverCode: aavsoObserverCode ?? this.aavsoObserverCode,
    );
  }
}

class ScienceSettingsNotifier extends AsyncNotifier<ScienceSettings> {
  static const _keys = {
    'advancedMode': 'science.advanced_mode.enabled',
    'overlay': 'science.overlay.enabled',
    'photometry': 'science.feature.photometry',
    'photometricCalibration': 'science.feature.photometric_calibration',
    'transparency': 'science.feature.transparency',
    'psfMap': 'science.feature.psf_map',
    'astrometricResiduals': 'science.feature.astrometric_residuals',
    'movingObjects': 'science.feature.moving_objects',
    'narrowbandRatios': 'science.feature.narrowband_ratios',
    'frameQualityMaps': 'science.feature.frame_quality_maps',
    'surface3d': 'science.feature.surface3d',
    'manualPurgeOnly': 'science.retention.manual_purge_only',
    'mpcObservatoryCode': 'science.mpc.observatory_code',
    'aavsoObserverCode': 'science.aavso.observer_code',
  };

  @override
  Future<ScienceSettings> build() async {
    final settings = await _loadScienceSettingsMap(ref);

    return ScienceSettings(
      advancedModeEnabled: _parseBool(settings[_keys['advancedMode']], false),
      overlayEnabled: _parseBool(settings[_keys['overlay']], true),
      photometryEnabled: _parseBool(settings[_keys['photometry']], true),
      photometricCalibrationEnabled:
          _parseBool(settings[_keys['photometricCalibration']], true),
      transparencyEnabled: _parseBool(settings[_keys['transparency']], true),
      psfMapEnabled: _parseBool(settings[_keys['psfMap']], true),
      astrometricResidualsEnabled:
          _parseBool(settings[_keys['astrometricResiduals']], true),
      movingObjectsEnabled: _parseBool(settings[_keys['movingObjects']], false),
      narrowbandRatiosEnabled:
          _parseBool(settings[_keys['narrowbandRatios']], false),
      frameQualityMapsEnabled:
          _parseBool(settings[_keys['frameQualityMaps']], true),
      surface3dEnabled: _parseBool(settings[_keys['surface3d']], true),
      manualPurgeOnly: _parseBool(settings[_keys['manualPurgeOnly']], true),
      mpcObservatoryCode:
          settings[_keys['mpcObservatoryCode']] ?? '',
      aavsoObserverCode:
          settings[_keys['aavsoObserverCode']] ?? '',
    );
  }

  Future<void> _setSetting(String key, bool value) async {
    await _writeScienceSettings(ref, {key: value.toString()});
  }

  Future<void> _setStringSetting(String key, String value) async {
    await _writeScienceSettings(ref, {key: value});
  }

  Future<void> setAdvancedModeEnabled(bool enabled) async {
    await _setSetting(_keys['advancedMode']!, enabled);
    state = AsyncData((state.value ?? const ScienceSettings())
        .copyWith(advancedModeEnabled: enabled));
  }

  Future<void> setOverlayEnabled(bool enabled) async {
    await _setSetting(_keys['overlay']!, enabled);
    state = AsyncData((state.value ?? const ScienceSettings())
        .copyWith(overlayEnabled: enabled));
  }

  Future<void> setFeatureEnabled(ScienceFeature feature, bool enabled) async {
    switch (feature) {
      case ScienceFeature.photometry:
        await _setSetting(_keys['photometry']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(photometryEnabled: enabled));
        break;
      case ScienceFeature.photometricCalibration:
        await _setSetting(_keys['photometricCalibration']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(photometricCalibrationEnabled: enabled));
        break;
      case ScienceFeature.transparency:
        await _setSetting(_keys['transparency']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(transparencyEnabled: enabled));
        break;
      case ScienceFeature.psfMap:
        await _setSetting(_keys['psfMap']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(psfMapEnabled: enabled));
        break;
      case ScienceFeature.astrometricResiduals:
        await _setSetting(_keys['astrometricResiduals']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(astrometricResidualsEnabled: enabled));
        break;
      case ScienceFeature.movingObjects:
        await _setSetting(_keys['movingObjects']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(movingObjectsEnabled: enabled));
        break;
      case ScienceFeature.narrowbandRatios:
        await _setSetting(_keys['narrowbandRatios']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(narrowbandRatiosEnabled: enabled));
        break;
      case ScienceFeature.frameQualityMaps:
        await _setSetting(_keys['frameQualityMaps']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(frameQualityMapsEnabled: enabled));
        break;
      case ScienceFeature.surface3d:
        await _setSetting(_keys['surface3d']!, enabled);
        state = AsyncData((state.value ?? const ScienceSettings())
            .copyWith(surface3dEnabled: enabled));
        break;
    }
  }

  Future<void> setMpcObservatoryCode(String code) async {
    await _setStringSetting(_keys['mpcObservatoryCode']!, code);
    state = AsyncData((state.value ?? const ScienceSettings())
        .copyWith(mpcObservatoryCode: code));
  }

  Future<void> setAavsoObserverCode(String code) async {
    await _setStringSetting(_keys['aavsoObserverCode']!, code);
    state = AsyncData((state.value ?? const ScienceSettings())
        .copyWith(aavsoObserverCode: code));
  }

  bool _parseBool(String? value, bool fallback) {
    if (value == null) {
      return fallback;
    }
    return value.toLowerCase() == 'true';
  }
}

final scienceSettingsProvider =
    AsyncNotifierProvider<ScienceSettingsNotifier, ScienceSettings>(
  ScienceSettingsNotifier.new,
);

class SciencePhotometrySelectionNotifier
    extends AsyncNotifier<SciencePhotometrySelection> {
  static const _enabledKey = 'science.photometry.differential_active';
  static const _targetKey = 'science.photometry.target_anchor';
  static const _comparisonsKey = 'science.photometry.comparison_anchors';

  @override
  Future<SciencePhotometrySelection> build() async {
    final settings = await _loadScienceSettingsMap(ref);
    final enabled = _parseBool(settings[_enabledKey], false);
    final target = _decodeAnchor(settings[_targetKey]);
    final comparisons =
        _decodeAnchors(settings[_comparisonsKey], maxItems: 8);

    return SciencePhotometrySelection(
      differentialEnabled: enabled,
      target: target,
      comparisons: comparisons,
    );
  }

  Future<void> setDifferentialEnabled(bool enabled) async {
    await _writeScienceSettings(ref, {_enabledKey: enabled.toString()});
    state = AsyncData(
      (state.value ?? const SciencePhotometrySelection())
          .copyWith(differentialEnabled: enabled),
    );
  }

  Future<void> setTarget(PhotometryAnchor? target) async {
    final value = target == null ? '' : jsonEncode(target.toJson());

    final current = state.value ?? const SciencePhotometrySelection();
    final comparisons = current.comparisons
        .where((entry) => entry.objectId != target?.objectId)
        .toList(growable: false);

    await _writeScienceSettings(ref, {
      _targetKey: value,
      _comparisonsKey:
          jsonEncode(comparisons.map((entry) => entry.toJson()).toList()),
    });

    state = AsyncData(
      current.copyWith(
        target: target,
        clearTarget: target == null,
        comparisons: comparisons,
      ),
    );
  }

  Future<void> toggleComparison(
    PhotometryAnchor anchor, {
    int maxComparisons = 8,
  }) async {
    final current = state.value ?? const SciencePhotometrySelection();
    final mutable = current.comparisons.toList(growable: true);

    final existingIndex =
        mutable.indexWhere((entry) => entry.objectId == anchor.objectId);
    if (existingIndex >= 0) {
      mutable.removeAt(existingIndex);
    } else if (mutable.length < maxComparisons) {
      mutable.add(anchor);
    }

    final filtered = mutable
        .where((entry) => entry.objectId != current.target?.objectId)
        .toList(growable: false);

    await _writeScienceSettings(ref, {
      _comparisonsKey:
          jsonEncode(filtered.map((entry) => entry.toJson()).toList()),
    });
    state = AsyncData(current.copyWith(comparisons: filtered));
  }

  Future<void> clearComparisons() async {
    await _writeScienceSettings(ref, {_comparisonsKey: '[]'});
    final current = state.value ?? const SciencePhotometrySelection();
    state = AsyncData(current.copyWith(comparisons: const []));
  }

  Future<void> clearAll() async {
    await _writeScienceSettings(ref, {
      _enabledKey: 'false',
      _targetKey: '',
      _comparisonsKey: '[]',
    });
    state = const AsyncData(SciencePhotometrySelection());
  }

  bool _parseBool(String? value, bool fallback) {
    if (value == null || value.isEmpty) {
      return fallback;
    }
    return value.toLowerCase() == 'true';
  }

  PhotometryAnchor? _decodeAnchor(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PhotometryAnchor.fromJson(decoded);
      }
      if (decoded is Map) {
        return PhotometryAnchor.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (error, stack) {
      developer.log(
        'SciencePhotometrySelectionNotifier: failed to decode target anchor '
        'from persisted JSON "$raw": $error',
        name: 'SciencePhotometrySelectionNotifier',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
    }
    return null;
  }

  List<PhotometryAnchor> _decodeAnchors(
    String? raw, {
    int maxItems = 8,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final anchors = <PhotometryAnchor>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          anchors.add(PhotometryAnchor.fromJson(item));
        } else if (item is Map) {
          anchors.add(PhotometryAnchor.fromJson(item.cast<String, dynamic>()));
        }
        if (anchors.length >= maxItems) {
          break;
        }
      }
      return anchors;
    } catch (error, stack) {
      developer.log(
        'SciencePhotometrySelectionNotifier: failed to decode comparison anchors '
        'from persisted JSON "$raw": $error',
        name: 'SciencePhotometrySelectionNotifier',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return const [];
    }
  }
}

final sciencePhotometrySelectionProvider = AsyncNotifierProvider<
    SciencePhotometrySelectionNotifier, SciencePhotometrySelection>(
  SciencePhotometrySelectionNotifier.new,
);

final activePhotometryTargetObjectIdProvider = Provider<String>((ref) {
  final selection = ref.watch(sciencePhotometrySelectionProvider).valueOrNull;
  return selection?.target?.objectId ?? 'target_primary';
});

final scienceModeStateProvider =
    StateProvider<ScienceModeState>((_) => const ScienceModeState());

final scienceOverlayStateProvider =
    StateProvider<ScienceOverlayState>((_) => const ScienceOverlayState());

class ScienceVisualizationPrefsNotifier
    extends AsyncNotifier<ScienceVisualizationPrefs> {
  static const _overlayOpacityKey = 'science.overlay.opacity';
  static const _liveGridRowsKey = 'science.overlay.live_grid_rows';
  static const _liveGridColsKey = 'science.overlay.live_grid_cols';
  static const _analysisGridRowsKey = 'science.overlay.analysis_grid_rows';
  static const _analysisGridColsKey = 'science.overlay.analysis_grid_cols';

  @override
  Future<ScienceVisualizationPrefs> build() async {
    final raw = await _loadScienceSettingsMap(ref);

    return ScienceVisualizationPrefs(
      overlayOpacity: _parseDouble(raw[_overlayOpacityKey], 0.35)
          .clamp(0.05, 0.95)
          .toDouble(),
      liveGridRows: _parseInt(raw[_liveGridRowsKey], 12).clamp(4, 64),
      liveGridCols: _parseInt(raw[_liveGridColsKey], 16).clamp(4, 64),
      analysisGridRows: _parseInt(raw[_analysisGridRowsKey], 24).clamp(4, 96),
      analysisGridCols: _parseInt(raw[_analysisGridColsKey], 32).clamp(4, 96),
    );
  }

  Future<void> savePrefs(ScienceVisualizationPrefs prefs) async {
    await _writeScienceSettings(ref, {
      _overlayOpacityKey: prefs.overlayOpacity.toString(),
      _liveGridRowsKey: prefs.liveGridRows.toString(),
      _liveGridColsKey: prefs.liveGridCols.toString(),
      _analysisGridRowsKey: prefs.analysisGridRows.toString(),
      _analysisGridColsKey: prefs.analysisGridCols.toString(),
    });
    state = AsyncData(prefs);
  }

  double _parseDouble(String? value, double fallback) {
    final parsed = value == null ? null : double.tryParse(value);
    return parsed ?? fallback;
  }

  int _parseInt(String? value, int fallback) {
    final parsed = value == null ? null : int.tryParse(value);
    return parsed ?? fallback;
  }
}

final scienceVisualizationPrefsProvider = AsyncNotifierProvider<
    ScienceVisualizationPrefsNotifier, ScienceVisualizationPrefs>(
  ScienceVisualizationPrefsNotifier.new,
);

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
  return ref.watch(scienceDaoProvider).watchSessionConfig(sessionId).map((row) {
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
    throw StateError('Remote sessionless science bundle requested in local mode');
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
    StreamProvider.family<List<PhotometryMeasurementRow>, int>(
        (ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.photometry),
          loading: () => Stream.value(const <PhotometryMeasurementRow>[]),
          error: (_, __) => Stream.value(const <PhotometryMeasurementRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchPhotometryForSession(sessionId);
});

final sessionFrameCalibrationsProvider =
    StreamProvider.family<List<FramePhotometricCalibrationRow>, int>(
        (ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.calibrations),
          loading: () =>
              Stream.value(const <FramePhotometricCalibrationRow>[]),
          error: (_, __) =>
              Stream.value(const <FramePhotometricCalibrationRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchCalibrationsForSession(sessionId);
});

final sessionTransparencySamplesProvider =
    StreamProvider.family<List<TransparencySampleRow>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.transparency),
          loading: () => Stream.value(const <TransparencySampleRow>[]),
          error: (_, __) => Stream.value(const <TransparencySampleRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchTransparencyForSession(sessionId);
});

final sessionPsfTilesProvider =
    StreamProvider.family<List<PsfFieldTileRow>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.psfTiles),
          loading: () => Stream.value(const <PsfFieldTileRow>[]),
          error: (_, __) => Stream.value(const <PsfFieldTileRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchPsfTilesForSession(sessionId);
});

final sessionFrameQualityMetricsProvider =
    StreamProvider.family<List<ScienceFrameQualityMetricsRow>, int>(
        (ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
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
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.tileMetrics),
          loading: () => Stream.value(const <ScienceTileMetricRow>[]),
          error: (_, __) => Stream.value(const <ScienceTileMetricRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchTileMetricsForSession(sessionId);
});

final sessionResidualVectorsProvider =
    StreamProvider.family<List<AstrometryResidualVectorRow>, int>(
        (ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.residuals),
          loading: () => Stream.value(const <AstrometryResidualVectorRow>[]),
          error: (_, __) => Stream.value(const <AstrometryResidualVectorRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchResidualsForSession(sessionId);
});

final sessionMovingObjectCandidatesProvider =
    StreamProvider.family<List<MovingObjectCandidateRow>, int>(
        (ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.movingObjects),
          loading: () => Stream.value(const <MovingObjectCandidateRow>[]),
          error: (_, __) => Stream.value(const <MovingObjectCandidateRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchMovingObjectsForSession(sessionId);
});

final sessionLineRatioProductsProvider =
    StreamProvider.family<List<LineRatioProductRow>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteScienceSessionBundleProvider(sessionId)).when(
          data: (bundle) => Stream.value(bundle.lineRatios),
          loading: () => Stream.value(const <LineRatioProductRow>[]),
          error: (_, __) => Stream.value(const <LineRatioProductRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchLineRatiosForSession(sessionId);
});

final sessionLightCurveProvider =
    Provider.family<List<LightCurvePoint>, (int sessionId, String objectId)>(
        (ref, args) {
  final photometry =
      ref.watch(sessionPhotometryProvider(args.$1)).valueOrNull ?? const [];

  return photometry
      .where((row) => row.objectId == args.$2)
      .map(
        (row) => LightCurvePoint(
          timestamp: row.timestamp,
          flux: row.flux,
          differentialMagnitude: row.differentialMagnitude ?? 0.0,
          snr: row.snr ?? 0.0,
          uncertainty: row.uncertainty ?? 0.0,
        ),
      )
      .toList(growable: false);
});

final sessionTransparencyTrendProvider =
    Provider.family<List<TransparencyTrendPoint>, int>((ref, sessionId) {
  final rows =
      ref.watch(sessionTransparencySamplesProvider(sessionId)).valueOrNull ??
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
      ref.watch(sessionMovingObjectCandidatesProvider(sessionId)).valueOrNull ??
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
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
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
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
          data: (bundle) => Stream.value(bundle.transparency),
          loading: () => Stream.value(const <TransparencySampleRow>[]),
          error: (_, __) => Stream.value(const <TransparencySampleRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchSessionlessTransparencyRecent();
});

final sessionlessPsfTilesProvider =
    StreamProvider<List<PsfFieldTileRow>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
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
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
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
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
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
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
          data: (bundle) => Stream.value(bundle.residuals),
          loading: () => Stream.value(const <AstrometryResidualVectorRow>[]),
          error: (_, __) => Stream.value(const <AstrometryResidualVectorRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchSessionlessResidualsRecent();
});

final sessionlessMovingObjectCandidatesProvider =
    StreamProvider<List<MovingObjectCandidateRow>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
          data: (bundle) => Stream.value(bundle.movingObjects),
          loading: () => Stream.value(const <MovingObjectCandidateRow>[]),
          error: (_, __) => Stream.value(const <MovingObjectCandidateRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchSessionlessMovingObjectsRecent();
});

final sessionlessPhotometryProvider =
    StreamProvider<List<PhotometryMeasurementRow>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
          data: (bundle) => Stream.value(bundle.photometry),
          loading: () => Stream.value(const <PhotometryMeasurementRow>[]),
          error: (_, __) => Stream.value(const <PhotometryMeasurementRow>[]),
        );
  }
  return ref.watch(scienceDaoProvider).watchSessionlessPhotometryRecent();
});

final sessionlessLineRatioProductsProvider =
    StreamProvider<List<LineRatioProductRow>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ref.watch(_remoteSessionlessScienceBundleProvider).when(
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
      .where((row) => row.objectId == objectId)
      .map(
        (row) => LightCurvePoint(
          timestamp: row.timestamp,
          flux: row.flux,
          differentialMagnitude: row.differentialMagnitude ?? 0.0,
          snr: row.snr ?? 0.0,
          uncertainty: row.uncertainty ?? 0.0,
        ),
      )
      .toList(growable: false);
});

final sessionlessTransparencyTrendProvider =
    Provider<List<TransparencyTrendPoint>>((ref) {
  final rows =
      ref.watch(sessionlessTransparencySamplesProvider).valueOrNull ?? const [];
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
        ref.watch(sessionFrameCalibrationsProvider(sessionId)).valueOrNull ??
            const [];
    transparency =
        ref.watch(sessionTransparencySamplesProvider(sessionId)).valueOrNull ??
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

final currentScienceFrameProductsProvider = Provider.family<
    (ScienceFrameQualityMetricsRow?, List<ScienceTileMetricRow>),
    (int sessionId, int? capturedImageId)>((ref, args) {
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

Future<void> _writeScienceSettings(Ref ref, Map<String, String> settings) async {
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

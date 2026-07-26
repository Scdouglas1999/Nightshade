import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/network_backend.dart';
import '../database/database.dart' as db;
import '../models/imaging/imaging_models.dart';
import '../models/imaging/auto_stretch_settings.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'profiles_provider.dart';
import 'session_optimizer_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';

/// Current exposure settings
final exposureSettingsProvider = StateProvider<ExposureSettings>((ref) {
  return const ExposureSettings(
    exposureTime: 120,
    gain: 100,
    offset: 50,
    binningX: 1,
    binningY: 1,
    frameType: FrameType.light,
  );
});

/// Set true the moment the user manually edits exposure/gain/offset; gates all
/// auto-seeding.
///
/// Once the user touches an exposure control, neither the active equipment
/// profile's gain/offset defaults nor the Smart Night recommended exposure may
/// overwrite their values. The flag is flipped to `true` by the camera capture
/// panel and the camera-preset selector; this provider only declares
/// the state and is read here to gate seeding. It deliberately replaces the old
/// `exposureTime == 120` heuristic, which silently re-seeded whenever a user
/// genuinely wanted a 120 s light frame.
final exposureSettingsUserDirtyProvider = StateProvider<bool>((ref) => false);

/// Tracks the profile ID whose defaults were last applied to exposure settings.
/// This prevents re-applying defaults when navigating back to the imaging screen
/// while still allowing a profile switch to re-initialize the controls.
final _lastAppliedProfileIdProvider = StateProvider<int?>((ref) => null);
final _lastAppliedSmartExposureProfileIdProvider = StateProvider<int?>(
  (ref) => null,
);

/// Call this provider from the imaging screen's initState/build to ensure
/// snapshot controls are initialized from the active equipment profile.
///
/// On first call (or when the active profile changes), this reads the profile's
/// defaultGain, defaultOffset, and defaultBinX/Y and pushes them into
/// [exposureSettingsProvider]. Subsequent calls with the same profile are no-ops,
/// so manual user edits are preserved.
final syncExposureFromProfileProvider = Provider<void>((ref) {
  final profile = ref.watch(activeEquipmentProfileProvider);
  if (profile == null) return;

  final exposureContext = ref
      .watch(smartNightExposureContextProvider)
      .valueOrNull;

  var disposed = false;
  ref.onDispose(() => disposed = true);

  Future<void>.microtask(() {
    if (disposed) return;

    // Once the user has manually edited any exposure control, no auto-seeding
    // (profile defaults or Smart Night) may overwrite their values.
    final userDirty = ref.read(exposureSettingsUserDirtyProvider);

    final profileId = profile.id;
    final lastApplied = ref.read(_lastAppliedProfileIdProvider);
    if (!userDirty && lastApplied != profileId) {
      ref.read(_lastAppliedProfileIdProvider.notifier).state = profileId;

      final current = ref.read(exposureSettingsProvider);
      ref.read(exposureSettingsProvider.notifier).state = current.copyWith(
        gain: profile.defaultGain ?? current.gain,
        offset: profile.defaultOffset ?? current.offset,
        binningX: profile.defaultBinX,
        binningY: profile.defaultBinY,
      );
    }

    if (exposureContext == null) return;
    if (userDirty) return;

    final lastSmart = ref.read(_lastAppliedSmartExposureProfileIdProvider);
    if (lastSmart == profileId) return;

    final current = ref.read(exposureSettingsProvider);
    if (current.frameType != FrameType.light) return;

    ref.read(_lastAppliedSmartExposureProfileIdProvider.notifier).state =
        profileId;
    ref.read(exposureSettingsProvider.notifier).state = current.copyWith(
      exposureTime: exposureContext.recommendForFilter(current.filter).seconds,
    );
  });
});

/// Last captured image stats
final lastImageStatsProvider = StateProvider<ImageStats?>((ref) => null);

/// Auto-stretch settings with method selection and advanced parameters.
///
/// Settings are persisted to the database and loaded on startup.
final autoStretchSettingsProvider =
    StateNotifierProvider<AutoStretchSettingsNotifier, AutoStretchSettings>(
      (ref) => AutoStretchSettingsNotifier(ref),
    );

/// StateNotifier for auto-stretch settings with database persistence.
class AutoStretchSettingsNotifier extends StateNotifier<AutoStretchSettings> {
  final Ref _ref;
  bool _isLoaded = false;
  AutoStretchSettings _confirmedSettings = AutoStretchSettings.defaults();
  AutoStretchSettings _requestedSettings = AutoStretchSettings.defaults();
  int _requestRevision = 0;
  Future<void> _writeTail = Future<void>.value();
  Future<void> _requestedWrite = Future<void>.value();

  AutoStretchSettingsNotifier(this._ref)
    : super(AutoStretchSettings.defaults()) {
    _loadSettings();
  }

  /// Load settings from database on startup.
  Future<void> _loadSettings() async {
    if (_isLoaded) return;
    _isLoaded = true;
    final revisionAtStart = _requestRevision;

    try {
      final dao = _ref.read(settingsDaoProvider);
      final json = await dao.getAutoStretchSettings();
      if (json != null &&
          json.isNotEmpty &&
          revisionAtStart == _requestRevision &&
          mounted) {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final loaded = AutoStretchSettings.fromJson(decoded);
        _confirmedSettings = loaded;
        _requestedSettings = loaded;
        state = loaded;
      }
    } catch (e) {
      developer.log(
        'Failed to load auto-stretch settings: $e',
        name: 'AutoStretch',
        level: 1000,
      );
    }
  }

  /// Update settings and persist to database.
  ///
  /// Skips the state update (and downstream rebuild of stretched image
  /// providers) when the new settings are identical to the current ones.
  Future<void> update(AutoStretchSettings newSettings) {
    if (_requestedSettings == newSettings) return _requestedWrite;

    _requestedSettings = newSettings;
    final revision = ++_requestRevision;
    state = newSettings;
    final operation = _writeTail.then((_) async {
      try {
        await _persistSettings(newSettings);
        _confirmedSettings = newSettings;
      } catch (_) {
        if (revision == _requestRevision && mounted) {
          _requestedSettings = _confirmedSettings;
          state = _confirmedSettings;
        }
        rethrow;
      }
    });
    _writeTail = operation.then<void>((_) {}, onError: (_, __) {});
    _requestedWrite = operation;
    return operation;
  }

  /// Persist a captured settings snapshot to the database.
  Future<void> _persistSettings(AutoStretchSettings settings) async {
    try {
      final dao = _ref.read(settingsDaoProvider);
      final json = jsonEncode(settings.toJson());
      await dao.setAutoStretchSettings(json);
    } catch (e) {
      developer.log(
        'Failed to save auto-stretch settings: $e',
        name: 'AutoStretch',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Reset to default settings.
  Future<void> reset() => update(AutoStretchSettings.defaults());
}

/// Cooling settings
final coolingSettingsProvider = StateProvider<CoolingSettings>((ref) {
  return const CoolingSettings();
});

/// Cooling status (read from camera)
final coolingStatusProvider = StateProvider<CoolingStatus>((ref) {
  return const CoolingStatus();
});

/// Focus/Autofocus settings (persists across navigation).
///
/// Initial values are loaded once from the persisted AppSettings autofocus
/// fields. After initialization, user edits are held in memory and are NOT
/// reset when unrelated app settings are saved.
final focusSettingsProvider =
    StateNotifierProvider<FocusSettingsNotifier, FocusSettings>((ref) {
      return FocusSettingsNotifier(ref);
    });

/// StateNotifier for focus settings that reads from AppSettings only once.
///
/// Prevents the bug where every AppSettings save would reset user edits
/// because `ref.watch(appSettingsProvider)` triggered a full rebuild.
class FocusSettingsNotifier extends StateNotifier<FocusSettings> {
  final Ref _ref;
  bool _initialized = false;
  bool _userEdited = false;

  FocusSettingsNotifier(this._ref) : super(const FocusSettings()) {
    _loadFromAppSettings();
  }

  Future<void> _loadFromAppSettings() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // App settings normally load asynchronously from Drift or the remote
      // host. Reading valueOrNull once during construction races that load and
      // permanently leaves autofocus at generic defaults. Await the real
      // snapshot, but never let its late arrival overwrite panel edits made in
      // the meantime.
      final settings = await _ref.read(appSettingsProvider.future);
      if (!mounted || _userEdited) return;
      state = FocusSettings(
        stepSize: settings.afStepSize,
        method: settings.afMethod,
        afStepSize: settings.afStepSize,
        stepsOut: settings.afInitialOffsetSteps,
        exposuresPerPoint: settings.afExposuresPerPoint,
        exposureTime: settings.afExposureTime,
      );
    } catch (e) {
      developer.log(
        'Failed to initialize focus settings from app settings: $e',
        name: 'FocusSettings',
        level: 1000,
      );
    }
  }

  /// Update focus settings (user edits at runtime).
  void update(FocusSettings newSettings) {
    _userEdited = true;
    state = newSettings;
  }
}

/// Dither settings for guiding (persists across navigation)
final ditherSettingsProvider = StateProvider<DitherSettings>((ref) {
  return const DitherSettings();
});

/// Slew coordinates for mount tab (persists across navigation)
final slewCoordinatesProvider = StateProvider<SlewCoordinates>((ref) {
  return const SlewCoordinates();
});

/// Selected imaging panel index (persists across navigation)
/// 0 = Capture, 1 = Focus, 2 = Mount, 3 = Guider
final selectedImagingPanelProvider = StateProvider<int>((ref) => 0);

/// File naming pattern derived from persisted settings
final namingPatternProvider = Provider<NamingPattern>((ref) {
  final settings = ref.watch(
    appSettingsProvider.select(
      (settingsAsync) => settingsAsync.valueOrNull == null
          ? null
          : (
              pattern: settingsAsync.valueOrNull!.fileNamingPattern,
              outputPath: settingsAsync.valueOrNull!.imageOutputPath,
              format: settingsAsync.valueOrNull!.imageFormat,
            ),
    ),
  );

  if (settings == null) {
    return const NamingPattern();
  }

  // Captures are currently persisted through the native FITS writer. This
  // defensive coercion also protects callers while a legacy/remote settings
  // snapshot is being migrated by appSettingsProvider.
  const format = ImageFileFormat.fits;
  final baseDir = settings.outputPath.isEmpty ? '.' : settings.outputPath;

  return NamingPattern(
    pattern: settings.pattern,
    baseDir: baseDir,
    format: format,
  );
});

/// Last star detection result
final starDetectionResultProvider = StateProvider<StarDetectionResult?>(
  (ref) => null,
);

/// Session captured images
final sessionImagesProvider =
    StateNotifierProvider<SessionImagesNotifier, List<CapturedImage>>((ref) {
      return SessionImagesNotifier();
    });

class SessionImagesNotifier extends StateNotifier<List<CapturedImage>> {
  SessionImagesNotifier() : super([]);

  void addImage(CapturedImage image) {
    state = [...state, image];
  }

  void removeImage(String id) {
    state = state.where((img) => img.id != id).toList();
  }

  void clearSession() {
    state = [];
  }

  int get count => state.length;

  Duration get totalExposureTime {
    return state.fold(
      Duration.zero,
      (total, img) =>
          total + Duration(seconds: img.settings.exposureTime.round()),
    );
  }
}

/// Recent frames for the active session, remote-aware.
///
/// On the host this is exactly the in-memory [sessionImagesProvider] list (the
/// local capture loop populates it). On a slave (NetworkBackend) the master is
/// the node actually imaging, so those frames never reach the local in-memory
/// list — instead this branches onto the already remote-aware
/// [allDbImagesProvider] (which polls the host's `/api/images`), filters to the
/// active session's `dbSessionId`, and maps each Drift row back onto the
/// in-memory [CapturedImage] shape the cockpit/strip widgets render. Ordering
/// matches [sessionImagesProvider]: oldest-first (capture order), so the
/// consumers' "take the tail, reverse to newest-first" logic is unchanged.
///
/// The session id itself is also remote-aware. `dbSessionId` is only ever set
/// locally by [SessionStateNotifier.startSession] / `recoverSession`, so a
/// phone or tablet that merely *watches* a host-started run never has one — the
/// strip rendered "No frames captured this session yet" for the whole night
/// while the host's `/api/images` already held every frame. When the local id is
/// absent we fall back to the host's own active session, using the same
/// `status == 'active'` invariant `SessionsDao.getActiveSessions` relies on.
final recentSessionFramesProvider = Provider<List<CapturedImage>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is! NetworkBackend) {
    return ref.watch(sessionImagesProvider);
  }

  var sessionId = ref.watch(
    sessionStateProvider.select((state) => state.dbSessionId),
  );
  if (sessionId == null) {
    // `allSessionsProvider` is already sorted newest-first on both the local
    // and the remote path, so the first active row is the current session. A
    // genuinely idle host yields null and the strip stays empty — which is then
    // the truth, not a false negative.
    final sessions = ref.watch(allSessionsProvider).valueOrNull;
    if (sessions != null) {
      for (final session in sessions) {
        if (session.status == 'active') {
          sessionId = session.id;
          break;
        }
      }
    }
  }
  if (sessionId == null) {
    return const <CapturedImage>[];
  }

  final rows = ref.watch(allDbImagesProvider).valueOrNull;
  if (rows == null) {
    return const <CapturedImage>[];
  }

  final sessionRows =
      rows.where((row) => row.sessionId == sessionId).toList(growable: false)
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return sessionRows.map(capturedImageFromDbRow).toList(growable: false);
});

/// Map a persisted `captured_images` row onto the in-memory [CapturedImage]
/// shape the cockpit/strip widgets render.
///
/// Package-public because the sequencer's frame-registration path needs the same
/// mapping to push freshly persisted sequence frames into
/// [sessionImagesProvider]; duplicating it there would let the two views of a
/// frame drift apart.
CapturedImage capturedImageFromDbRow(db.CapturedImage row) {
  return CapturedImage(
    id: row.id.toString(),
    filePath: row.filePath,
    capturedAt: row.capturedAt,
    settings: ExposureSettings(
      exposureTime: row.exposureDuration,
      gain: row.gain ?? 0,
      offset: row.offset ?? 0,
      binningX: row.binX,
      binningY: row.binY,
      filter: row.filter,
      frameType: _frameTypeFromDbString(row.frameType),
    ),
    stats: row.hfr != null || row.starCount != null
        ? ImageStats(
            hfr: row.hfr,
            starCount: row.starCount,
            background: row.background,
            noise: row.noise,
          )
        : null,
    format: _imageFormatFromDbString(row.fileFormat),
  );
}

FrameType _frameTypeFromDbString(String str) {
  switch (str.toLowerCase()) {
    case 'dark':
      return FrameType.dark;
    case 'flat':
      return FrameType.flat;
    case 'bias':
      return FrameType.bias;
    case 'darkflat':
      return FrameType.darkFlat;
    case 'snapshot':
      return FrameType.snapshot;
    default:
      return FrameType.light;
  }
}

ImageFileFormat _imageFormatFromDbString(String str) {
  switch (str.toLowerCase()) {
    case 'xisf':
      return ImageFileFormat.xisf;
    case 'tiff':
      return ImageFileFormat.tiff;
    case 'png':
      return ImageFileFormat.png;
    case 'jpeg':
    case 'jpg':
      return ImageFileFormat.jpeg;
    default:
      return ImageFileFormat.fits;
  }
}

// =============================================================================
// TEMPERATURE HISTORY TRACKING
// =============================================================================

/// A point in the temperature history
class TemperaturePoint {
  final double temperature;
  final double? targetTemp;
  final double? coolerPower;
  final DateTime time;

  TemperaturePoint({
    required this.temperature,
    this.targetTemp,
    this.coolerPower,
    required this.time,
  });
}

/// Provider for temperature history (last N points)
final temperatureHistoryProvider =
    StateNotifierProvider<TemperatureHistoryNotifier, List<TemperaturePoint>>((
      ref,
    ) {
      return TemperatureHistoryNotifier();
    });

class TemperatureHistoryNotifier extends StateNotifier<List<TemperaturePoint>> {
  static const int maxPoints = 120; // 10 minutes at 5-second intervals

  TemperatureHistoryNotifier() : super([]);

  void addPoint(double temperature, {double? targetTemp, double? coolerPower}) {
    final point = TemperaturePoint(
      temperature: temperature,
      targetTemp: targetTemp,
      coolerPower: coolerPower,
      time: DateTime.now(),
    );

    if (state.length >= maxPoints) {
      state = [...state.sublist(1), point];
    } else {
      state = [...state, point];
    }
  }

  void clear() {
    state = [];
  }

  /// Get the minimum and maximum temperature in the history
  (double, double) get tempRange {
    if (state.isEmpty) return (-30.0, 30.0);

    double minTemp = state.first.temperature;
    double maxTemp = state.first.temperature;

    for (final point in state) {
      if (point.temperature < minTemp) minTemp = point.temperature;
      if (point.temperature > maxTemp) maxTemp = point.temperature;
      if (point.targetTemp != null) {
        if (point.targetTemp! < minTemp) minTemp = point.targetTemp!;
        if (point.targetTemp! > maxTemp) maxTemp = point.targetTemp!;
      }
    }

    // Add some padding
    return (minTemp - 5, maxTemp + 5);
  }
}

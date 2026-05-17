import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/imaging/imaging_models.dart';
import '../models/imaging/auto_stretch_settings.dart';
import 'database_provider.dart';
import 'profiles_provider.dart';
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

/// Tracks the profile ID whose defaults were last applied to exposure settings.
/// This prevents re-applying defaults when navigating back to the imaging screen
/// while still allowing a profile switch to re-initialize the controls.
final _lastAppliedProfileIdProvider = StateProvider<int?>((ref) => null);

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

  final lastApplied = ref.read(_lastAppliedProfileIdProvider);
  if (lastApplied == profile.id) return;

  // Mark this profile as applied so we don't overwrite user edits
  ref.read(_lastAppliedProfileIdProvider.notifier).state = profile.id;

  final current = ref.read(exposureSettingsProvider);
  ref.read(exposureSettingsProvider.notifier).state = current.copyWith(
    gain: profile.defaultGain ?? current.gain,
    offset: profile.defaultOffset ?? current.offset,
    binningX: profile.defaultBinX,
    binningY: profile.defaultBinY,
  );
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

  AutoStretchSettingsNotifier(this._ref)
      : super(AutoStretchSettings.defaults()) {
    _loadSettings();
  }

  /// Load settings from database on startup.
  Future<void> _loadSettings() async {
    if (_isLoaded) return;
    _isLoaded = true;

    try {
      final db = _ref.read(databaseProvider);
      final json = await db.settingsDao.getAutoStretchSettings();
      if (json != null && json.isNotEmpty) {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        state = AutoStretchSettings.fromJson(decoded);
      }
    } catch (e) {
      developer.log('Failed to load auto-stretch settings: $e',
          name: 'AutoStretch', level: 1000);
    }
  }

  /// Update settings and persist to database.
  ///
  /// Skips the state update (and downstream rebuild of stretched image
  /// providers) when the new settings are identical to the current ones.
  void update(AutoStretchSettings newSettings) {
    if (state == newSettings) return;
    state = newSettings;
    _persistSettings();
  }

  /// Persist current settings to database.
  Future<void> _persistSettings() async {
    try {
      final db = _ref.read(databaseProvider);
      final json = jsonEncode(state.toJson());
      await db.settingsDao.setAutoStretchSettings(json);
    } catch (e) {
      developer.log('Failed to save auto-stretch settings: $e',
          name: 'AutoStretch', level: 1000);
    }
  }

  /// Reset to default settings.
  void reset() {
    update(AutoStretchSettings.defaults());
  }
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

  FocusSettingsNotifier(this._ref) : super(const FocusSettings()) {
    _loadFromAppSettings();
  }

  Future<void> _loadFromAppSettings() async {
    if (_initialized) return;
    _initialized = true;

    final settingsAsync = _ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (settings != null) {
      state = FocusSettings(
        stepSize: settings.afStepSize,
        method: settings.afMethod,
        afStepSize: settings.afStepSize,
        stepsOut: settings.afInitialOffsetSteps,
        exposuresPerPoint: settings.afExposuresPerPoint,
        exposureTime: settings.afExposureTime,
      );
    }
  }

  /// Update focus settings (user edits at runtime).
  void update(FocusSettings newSettings) {
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

  final format = ImageFileFormatSettingsX.fromSettings(settings.format);
  final baseDir = settings.outputPath.isEmpty ? '.' : settings.outputPath;

  return NamingPattern(
    pattern: settings.pattern,
    baseDir: baseDir,
    format: format,
  );
});

/// Last star detection result
final starDetectionResultProvider =
    StateProvider<StarDetectionResult?>((ref) => null);

/// Debayer settings for color cameras
final debayerEnabledProvider = StateProvider<bool>((ref) => false);

final bayerPatternProvider = StateProvider<BayerPattern>((ref) {
  return BayerPattern.rggb;
});

final debayerAlgorithmProvider = StateProvider<DebayerAlgorithm>((ref) {
  return DebayerAlgorithm.bilinear;
});

/// Auto-detect Bayer pattern from FITS headers
final autoDetectBayerPatternProvider = StateProvider<bool>((ref) => true);

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
    StateNotifierProvider<TemperatureHistoryNotifier, List<TemperaturePoint>>(
        (ref) {
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

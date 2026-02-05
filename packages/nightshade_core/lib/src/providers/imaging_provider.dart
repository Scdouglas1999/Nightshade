import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/imaging/imaging_models.dart';
import '../models/imaging/auto_stretch_settings.dart';
import 'database_provider.dart';
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

/// Last captured image stats
final lastImageStatsProvider = StateProvider<ImageStats?>((ref) => null);

/// Current stretch parameters
final stretchParamsProvider = StateProvider<StretchParams>((ref) {
  return const StretchParams();
});

/// Auto stretch enabled
final autoStretchProvider = StateProvider<bool>((ref) => true);

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

  AutoStretchSettingsNotifier(this._ref) : super(AutoStretchSettings.defaults()) {
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
      // Use default settings if loading fails
    }
  }

  /// Update settings and persist to database.
  void update(AutoStretchSettings newSettings) {
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
      // Silently fail persistence - settings will still work in-memory
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

/// Focus/Autofocus settings (persists across navigation)
final focusSettingsProvider = StateProvider<FocusSettings>((ref) {
  return const FocusSettings();
});

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
  final settingsAsync = ref.watch(appSettingsProvider);
  final settings = settingsAsync.valueOrNull;

  if (settings == null) {
    return const NamingPattern();
  }

  final format = ImageFileFormatSettingsX.fromSettings(settings.imageFormat);
  final baseDir = settings.imageOutputPath.isEmpty ? '.' : settings.imageOutputPath;

  return NamingPattern(
    pattern: settings.fileNamingPattern,
    baseDir: baseDir,
    format: format,
  );
});

/// Current capture mode
final captureModeProvider = StateProvider<CaptureMode>((ref) {
  return CaptureMode.single;
});

/// Frame count for count mode
final frameCountTargetProvider = StateProvider<int>((ref) => 10);

/// Star detection configuration
final starDetectionConfigProvider = StateProvider<StarDetectionConfig>((ref) {
  return const StarDetectionConfig();
});

/// Last star detection result
final starDetectionResultProvider = StateProvider<StarDetectionResult?>((ref) => null);

/// Show star overlay on image
final showStarOverlayProvider = StateProvider<bool>((ref) => false);

/// Show histogram overlay
final showHistogramOverlayProvider = StateProvider<bool>((ref) => true);

/// Show statistics overlay
final showStatsOverlayProvider = StateProvider<bool>((ref) => true);

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
final sessionImagesProvider = StateNotifierProvider<SessionImagesNotifier, List<CapturedImage>>((ref) {
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
      (total, img) => total + Duration(seconds: img.settings.exposureTime.round()),
    );
  }
}

/// Image zoom level
final imageZoomProvider = StateProvider<double>((ref) => 1.0);

/// Image pan offset (dx, dy)
final imagePanOffsetProvider = StateProvider<(double, double)>((ref) => (0.0, 0.0));

/// Image fit mode
enum ImageFitMode {
  fit,      // Fit entire image in view
  fill,     // Fill view (may crop)
  oneToOne, // 1:1 pixel mapping
  custom,   // Custom zoom level
}

final imageFitModeProvider = StateProvider<ImageFitMode>((ref) => ImageFitMode.fit);

/// Crosshair enabled
final showCrosshairProvider = StateProvider<bool>((ref) => false);

/// Grid overlay enabled  
final showGridOverlayProvider = StateProvider<bool>((ref) => false);

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
final temperatureHistoryProvider = StateNotifierProvider<TemperatureHistoryNotifier, List<TemperaturePoint>>((ref) {
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

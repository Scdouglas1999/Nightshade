import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:path/path.dart' as path;

import '../providers/dark_library_provider.dart';
import '../services/dark_library_service.dart';
import '../services/logging_service.dart';
import '../providers/database_provider.dart';

/// Sentinel object used by [CalibrationSettings.copyWith] to distinguish
/// "parameter not passed" from an explicit `null`.
const Object _sentinel = Object();

/// Settings for how calibration is applied.
class CalibrationSettings {
  /// Whether to auto-calibrate captured light frames.
  final bool autoCalibrate;

  /// Path to a master flat file (null = skip flat correction).
  final String? masterFlatPath;

  /// Path to a master bias file (null = skip bias correction).
  final String? masterBiasPath;

  /// Whether to auto-find darks from the dark library.
  final bool autoDarkFromLibrary;

  /// Manual dark path override (used if [autoDarkFromLibrary] is false).
  final String? manualDarkPath;

  const CalibrationSettings({
    this.autoCalibrate = false,
    this.masterFlatPath,
    this.masterBiasPath,
    this.autoDarkFromLibrary = true,
    this.manualDarkPath,
  });

  /// Returns a copy with the given fields replaced.
  ///
  /// For nullable String fields, pass an empty string to explicitly clear them.
  CalibrationSettings copyWith({
    bool? autoCalibrate,
    Object? masterFlatPath = _sentinel,
    Object? masterBiasPath = _sentinel,
    bool? autoDarkFromLibrary,
    Object? manualDarkPath = _sentinel,
  }) {
    return CalibrationSettings(
      autoCalibrate: autoCalibrate ?? this.autoCalibrate,
      masterFlatPath: masterFlatPath == _sentinel
          ? this.masterFlatPath
          : masterFlatPath as String?,
      masterBiasPath: masterBiasPath == _sentinel
          ? this.masterBiasPath
          : masterBiasPath as String?,
      autoDarkFromLibrary: autoDarkFromLibrary ?? this.autoDarkFromLibrary,
      manualDarkPath: manualDarkPath == _sentinel
          ? this.manualDarkPath
          : manualDarkPath as String?,
    );
  }
}

/// Result of a calibration operation.
class CalibrationResult {
  /// Path to the calibrated output file.
  final String outputPath;

  /// Whether a dark frame was applied.
  final bool darkApplied;

  /// Whether a flat frame was applied.
  final bool flatApplied;

  /// Whether a bias frame was applied.
  final bool biasApplied;

  /// Path of the dark used, if any.
  final String? darkUsed;

  /// Path of the flat used, if any.
  final String? flatUsed;

  /// Path of the bias used, if any.
  final String? biasUsed;

  const CalibrationResult({
    required this.outputPath,
    required this.darkApplied,
    required this.flatApplied,
    required this.biasApplied,
    this.darkUsed,
    this.flatUsed,
    this.biasUsed,
  });
}

/// Service for calibrating captured astrophotography images.
///
/// Integrates with the dark frame library for auto-matching and wraps
/// the native Rust calibration pipeline (dark subtraction, flat division,
/// bias correction) via the FFI bridge.
class CalibrationService {
  final Ref _ref;

  CalibrationService(this._ref);

  LoggingService get _logger => _ref.read(loggingServiceProvider);

  DarkLibraryService get _darkLibrary => _ref.read(darkLibraryServiceProvider);

  /// Calibrate a light frame file using the provided settings.
  ///
  /// If [settings.autoDarkFromLibrary] is true, the best-matching dark
  /// will be found from the dark library based on the light frame's
  /// exposure parameters.
  ///
  /// The calibrated image is saved to [outputPath]. If [outputPath] is null,
  /// a sibling `*_cal` file is generated and the original light frame is
  /// preserved (with a `.uncal` backup created once for recovery).
  Future<CalibrationResult> calibrateFile({
    required String lightPath,
    required CalibrationSettings settings,
    String? outputPath,
    double? exposureTime,
    int? gain,
    int? offset,
    int binX = 1,
    int binY = 1,
    double? sensorTemperature,
  }) async {
    _logger.info('Calibrating: $lightPath', source: 'CalibrationService');

    // Determine dark frame path
    String? darkPath = settings.manualDarkPath;
    if (settings.autoDarkFromLibrary &&
        darkPath == null &&
        exposureTime != null &&
        gain != null) {
      final matchingDark = await _darkLibrary.findMatchingDark(
        exposureTime: exposureTime,
        gain: gain,
        offset: offset ?? 0,
        binX: binX,
        binY: binY,
        temperature: sensorTemperature,
      );
      if (matchingDark != null) {
        darkPath = matchingDark.filePath;
        _logger.info(
            'Auto-matched dark: ${matchingDark.filePath} '
            '(exposure=${matchingDark.exposureTime}s, '
            'temp=${matchingDark.temperature}C)',
            source: 'CalibrationService');
      } else {
        _logger.info('No matching dark found in library',
            source: 'CalibrationService');
      }
    }

    // Determine flat and bias paths
    final flatPath = settings.masterFlatPath;
    final biasPath = settings.masterBiasPath;

    // Validate that at least one calibration frame is provided
    if (darkPath == null && flatPath == null && biasPath == null) {
      throw StateError('No calibration frames available. '
          'Provide a dark, flat, or bias frame.');
    }

    // Validate files exist
    if (darkPath != null && !File(darkPath).existsSync()) {
      throw FileSystemException('Dark frame file not found', darkPath);
    }
    if (flatPath != null && !File(flatPath).existsSync()) {
      throw FileSystemException('Flat frame file not found', flatPath);
    }
    if (biasPath != null && !File(biasPath).existsSync()) {
      throw FileSystemException('Bias frame file not found', biasPath);
    }

    // Determine output path
    final effectiveOutputPath = outputPath ?? _generateCalOutputPath(lightPath);

    // Ensure output directory exists
    final outDir = Directory(path.dirname(effectiveOutputPath));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    // If overwriting in place, back up original
    if (outputPath == null) {
      final backupPath = '${lightPath}.uncal';
      if (!File(backupPath).existsSync()) {
        await File(lightPath).copy(backupPath);
        _logger.info('Backed up original to: $backupPath',
            source: 'CalibrationService');
      }
    }

    // Call the native calibration pipeline
    await bridge.apiCalibrateImageFile(
      lightPath: lightPath,
      darkPath: darkPath,
      flatPath: flatPath,
      biasPath: biasPath,
      outputPath: effectiveOutputPath,
    );

    _logger.info(
        'Calibration complete: $effectiveOutputPath '
        '(dark=${darkPath != null}, flat=${flatPath != null}, '
        'bias=${biasPath != null})',
        source: 'CalibrationService');

    return CalibrationResult(
      outputPath: effectiveOutputPath,
      darkApplied: darkPath != null,
      flatApplied: flatPath != null,
      biasApplied: biasPath != null,
      darkUsed: darkPath,
      flatUsed: flatPath,
      biasUsed: biasPath,
    );
  }

  /// Calibrate raw pixel data in memory.
  ///
  /// Takes u16 pixel data directly and returns calibrated u16 pixel data.
  /// This is useful for live preview calibration without disk I/O.
  Uint16List calibrateData({
    required int width,
    required int height,
    required List<int> lightData,
    Uint16List? darkData,
    Uint16List? flatData,
    Uint16List? biasData,
  }) {
    if (darkData == null && flatData == null && biasData == null) {
      return Uint16List.fromList(lightData);
    }

    return bridge.apiCalibrateImageData(
      width: width,
      height: height,
      lightData: lightData,
      darkData: darkData,
      flatData: flatData,
      biasData: biasData,
    );
  }

  /// Generate a calibrated output path from a light frame path.
  ///
  /// Adds "_cal" suffix before the extension:
  ///   "image_001.fits" -> "image_001_cal.fits"
  String _generateCalOutputPath(String lightPath) {
    final dir = path.dirname(lightPath);
    final ext = path.extension(lightPath);
    final baseName = path.basenameWithoutExtension(lightPath);
    return path.join(dir, '${baseName}_cal$ext');
  }
}

/// Provider for the CalibrationService.
final calibrationServiceProvider = Provider<CalibrationService>((ref) {
  return CalibrationService(ref);
});

/// Provider for calibration settings, loaded from app settings.
final calibrationSettingsProvider =
    StateNotifierProvider<CalibrationSettingsNotifier, CalibrationSettings>(
        (ref) {
  return CalibrationSettingsNotifier(ref);
});

/// Manages calibration settings with persistence via app settings.
class CalibrationSettingsNotifier extends StateNotifier<CalibrationSettings> {
  final Ref _ref;

  CalibrationSettingsNotifier(this._ref) : super(const CalibrationSettings()) {
    _loadFromSettings();
  }

  void _loadFromSettings() {
    final settingsAsync = _ref.read(allSettingsProvider);
    settingsAsync.whenData((settings) {
      state = CalibrationSettings(
        autoCalibrate: settings['calibration.auto_calibrate'] == 'true',
        masterFlatPath: _nonEmpty(settings['calibration.master_flat_path']),
        masterBiasPath: _nonEmpty(settings['calibration.master_bias_path']),
        autoDarkFromLibrary:
            settings['calibration.auto_dark_from_library'] != 'false',
        manualDarkPath: _nonEmpty(settings['calibration.manual_dark_path']),
      );
    });
  }

  /// Returns the string if non-null and non-empty, otherwise null.
  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> setAutoCalibrate(bool enabled) async {
    state = state.copyWith(autoCalibrate: enabled);
    await _saveSetting('calibration.auto_calibrate', enabled.toString());
  }

  Future<void> setMasterFlatPath(String? path) async {
    state = state.copyWith(masterFlatPath: path);
    await _saveSetting('calibration.master_flat_path', path ?? '');
  }

  Future<void> setMasterBiasPath(String? path) async {
    state = state.copyWith(masterBiasPath: path);
    await _saveSetting('calibration.master_bias_path', path ?? '');
  }

  Future<void> setAutoDarkFromLibrary(bool enabled) async {
    state = state.copyWith(autoDarkFromLibrary: enabled);
    await _saveSetting(
        'calibration.auto_dark_from_library', enabled.toString());
  }

  Future<void> setManualDarkPath(String? path) async {
    state = state.copyWith(manualDarkPath: path);
    await _saveSetting('calibration.manual_dark_path', path ?? '');
  }

  Future<void> _saveSetting(String key, String value) async {
    final dao = _ref.read(settingsDaoProvider);
    await dao.setSetting(key, value);
  }
}

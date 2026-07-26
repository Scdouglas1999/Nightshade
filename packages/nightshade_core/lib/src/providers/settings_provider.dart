import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show immutable, kReleaseMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/network_backend.dart';
import '../models/backend/event_types.dart'
    show EventCategory, NightshadeEvent, settingsChangedEventType;
import 'database_provider.dart';
import 'backend_provider.dart';
import '../models/settings/app_settings.dart' as models;
import '../models/settings/app_settings.dart'
    show SafetyFailMode, kDefaultAccentColorHex;
import '../models/imaging/imaging_models.dart'
    show AutofocusSettings, FilterAutofocusConfig;

// ============================================================================
// Section parts — AppSettingsNotifier is split across multiple `part` files
// under `settings_sections/`. Each section file holds the public setters for
// one UI / domain section. This keeps each section file â‰¤ ~250 LOC and lets
// new settings land next to their siblings rather than in a 3900-line conflict
// hotspot.
//
// The split deliberately uses Dart's `part` mechanism instead of separate
// notifiers because:
//   * the underlying `app_settings` row is a single Drift record, so
//     coordinating writes across multiple notifiers would re-introduce the
//     same coupling without the benefit of separation;
//   * the remote-sync subscription in `build()` applies per-field
//     `settings.changed` events to one in-memory state — splitting the
//     notifier would force every section notifier to mirror that wiring;
//   * `part of` lets section files share the notifier's private helpers
//     (`_saveSetting`, `_patchState`, `_unset`, parse helpers) without
//     leaking them to the public API.
//
// Adding a new setting? Find the matching section file under
// `settings_sections/` and add the setter there. Add its state field and
// copyWith wiring in `app_settings_state.dart`, then add persistence /
// remote-sync mapping in `app_settings_notifier.dart`. Those declarations
// remain single sources of truth without crowding this library entry file.
// ============================================================================
part 'settings_sections/general.dart';
part 'settings_sections/appearance.dart';
part 'settings_sections/location.dart';
part 'settings_sections/environment.dart';
part 'settings_sections/recovery.dart';
part 'settings_sections/image_grading.dart';
part 'settings_sections/adaptive_exposure.dart';
part 'settings_sections/preflight.dart';
part 'settings_sections/smart_night.dart';
part 'settings_sections/session_lifecycle.dart';
part 'settings_sections/autofocus.dart';
part 'settings_sections/equipment.dart';
part 'settings_sections/file_paths.dart';
part 'settings_sections/imaging.dart';
part 'settings_sections/notifications.dart';
part 'settings_sections/phd2.dart';
part 'settings_sections/plate_solve.dart';
part 'settings_sections/protocol.dart';
part 'settings_sections/remote_access.dart';
part 'settings_sections/sequencer.dart';
part 'settings_sections/app_settings_state.dart';
part 'settings_sections/app_settings_remote_mapping.dart';
part 'settings_sections/app_settings_stored_snapshot_mapping.dart';
part 'settings_sections/app_settings_partial_persistence_mapping.dart';
part 'settings_sections/app_settings_notifier.dart';

@immutable
class AppSettingsWriteFailure {
  final String setting;
  final Object error;
  final DateTime occurredAt;

  const AppSettingsWriteFailure({
    required this.setting,
    required this.error,
    required this.occurredAt,
  });

  String get message =>
      'Could not save $setting. The displayed value may not match the host.';
}

/// Central error channel for settings controls whose async setter callback is
/// intentionally fire-and-forget (switches, sliders, and text fields).
final appSettingsWriteFailureProvider = StateProvider<AppSettingsWriteFailure?>(
  (ref) => null,
);

/// Simulation is a development-only capability. Normalize every persisted,
/// remote, and UI-facing value through one function so a release build cannot
/// display or transmit an enabled state that its executor and native bridge
/// will refuse to honor.
bool effectiveSimulationMode(
  bool requested, {
  bool releaseMode = kReleaseMode,
}) {
  return !releaseMode && requested;
}

// ============================================================================
// Pre-flight strictness
// ============================================================================

/// Pre-flight validation strictness mode. Tunes how aggressively the
/// pre-flight dialog should warn (or block) on questionable conditions:
///
///   * [lax]     — only obvious hardware errors block. Missing darks, stale
///                 polar alignment, mild time drift all surface as `info`.
///                 Suitable for "experienced user, knows what they're doing".
///   * [normal]  — default. Missing darks / stale alignment / cooler ambient
///                 issues become `warning`. Sequence can still start.
///   * [strict]  — production / unattended imaging. Missing darks and stale
///                 polar alignment become `error` (sequence won't start).
///                 Time-sync drift > 30 s is always an error regardless of
///                 strictness (it would falsify FITS timestamps).
enum PreflightStrictness { lax, normal, strict }

extension PreflightStrictnessLabel on PreflightStrictness {
  String get persistedName {
    switch (this) {
      case PreflightStrictness.lax:
        return 'lax';
      case PreflightStrictness.normal:
        return 'normal';
      case PreflightStrictness.strict:
        return 'strict';
    }
  }

  String get displayName {
    switch (this) {
      case PreflightStrictness.lax:
        return 'Lax';
      case PreflightStrictness.normal:
        return 'Normal';
      case PreflightStrictness.strict:
        return 'Strict';
    }
  }

  String get description {
    switch (this) {
      case PreflightStrictness.lax:
        return 'Soft warnings only. Missing darks and stale calibration surface as info.';
      case PreflightStrictness.normal:
        return 'Default. Missing darks and stale calibration are warnings; severe issues block.';
      case PreflightStrictness.strict:
        return 'Production / unattended. Missing darks and stale alignment block the start.';
    }
  }
}

PreflightStrictness _parsePreflightStrictness(String? value) {
  switch (value) {
    case 'lax':
      return PreflightStrictness.lax;
    case 'strict':
      return PreflightStrictness.strict;
    case 'normal':
    case null:
      return PreflightStrictness.normal;
    default:
      return PreflightStrictness.normal;
  }
}

// ============================================================================
// App Settings - Complete settings model
// ============================================================================

/// Runtime, in-memory application-settings state owned by
/// [AppSettingsNotifier]. Distinct from the persisted/freezed
/// `AppSettings` model in `models/settings/app_settings.dart`, which is the
/// Sentinel used by `AppSettingsState.copyWith` to distinguish
/// "no change" from "explicitly clear the nullable field". Dart's
/// `T?` parameter cannot express both "leave alone" and "set to null"
/// without this trick. Keep this private to the file so callers always
/// go through `copyWith`.
const Object _unset = Object();

/// Rust-bridge / JSON-persisted snapshot. Renamed from `AppSettings` to
/// disambiguate (audit-arch §2.2).

/// Main app settings provider
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettingsState>(() {
      return AppSettingsNotifier();
    });

/// Effective horizon in degrees selected from [appSettingsProvider].
///
/// The same value is consumed by the Run Dashboard's "time-to-set"
/// statistic and by the planetarium target-card so both surfaces display
/// the same number to the second. Falls back to 0° (mathematical horizon)
/// before settings have loaded.
final effectiveHorizonDegProvider = Provider<double>((ref) {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  return settings?.effectiveHorizonDeg ?? 0.0;
});

/// Focused observer-location selector derived from [appSettingsProvider].
///
/// Watching this provider avoids rebuilding weather/suggestion chains when
/// unrelated settings change.
final appObserverLocationProvider = Provider<LocationSettings?>((ref) {
  final location = ref.watch(
    appSettingsProvider.select(
      (settingsAsync) => settingsAsync.valueOrNull == null
          ? null
          : (
              latitude: settingsAsync.valueOrNull!.latitude,
              longitude: settingsAsync.valueOrNull!.longitude,
              elevation: settingsAsync.valueOrNull!.elevation,
            ),
    ),
  );

  if (location == null) {
    return null;
  }
  if (location.latitude == 0.0 && location.longitude == 0.0) {
    return null;
  }

  return LocationSettings(
    latitude: location.latitude,
    longitude: location.longitude,
    elevation: location.elevation,
  );
});

// ============================================================================
// Autofocus Settings Provider (convenience)
// ============================================================================

/// Convenience provider that derives a typed [AutofocusSettings] from the
/// persisted [AppSettingsState] autofocus fields.
///
/// This avoids every consumer needing to manually pluck out individual
/// `af_*` fields and parse the filter settings JSON.
final autofocusSettingsProvider = Provider<AutofocusSettings>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  final settings = settingsAsync.valueOrNull;
  if (settings == null) {
    return const AutofocusSettings();
  }

  return AutofocusSettings(
    method: settings.afMethod,
    curveFitting: settings.afCurveFitting,
    stepSize: settings.afStepSize,
    exposureTime: settings.afExposureTime,
    initialOffsetSteps: settings.afInitialOffsetSteps,
    numberOfAttempts: settings.afNumberOfAttempts,
    useBrightestNStars: settings.afUseBrightestNStars,
    outerCropRatio: settings.afOuterCropRatio,
    innerCropRatio: settings.afInnerCropRatio,
    binning: settings.afBinning,
    rSquaredThreshold: settings.afRSquaredThreshold,
    disableGuidingDuringAf: settings.afDisableGuidingDuringAf,
    focuserSettleTimeMs: settings.afFocuserSettleTimeMs,
    exposuresPerPoint: settings.afExposuresPerPoint,
    backlashCompMethod: settings.afBacklashCompMethod,
    backlashIn: settings.afBacklashIn,
    backlashOut: settings.afBacklashOut,
    autofocusFilterName: settings.afAutofocusFilterName,
    filterSettings: AutofocusSettings.parseFilterSettingsJson(
      settings.afFilterSettingsJson,
    ),
  );
});

// ============================================================================
// Legacy Providers (for backwards compatibility)
// ============================================================================

/// Location settings for observer position
class LocationSettings {
  final double latitude;
  final double longitude;
  final double elevation;

  const LocationSettings({
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.elevation = 0.0,
  });

  LocationSettings copyWith({
    double? latitude,
    double? longitude,
    double? elevation,
  }) {
    return LocationSettings(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
    );
  }
}

// ============================================================================
// Theme Settings
// ============================================================================

/// Theme mode setting
class ThemeSettingsNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final dao = ref.read(settingsDaoProvider);
    return await dao.getTheme();
  }

  Future<void> setTheme(String theme) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setTheme(theme);
    state = AsyncData(theme);
  }
}

final themeSettingsProvider =
    AsyncNotifierProvider<ThemeSettingsNotifier, String>(() {
      return ThemeSettingsNotifier();
    });

// ============================================================================
// Auto Connect Settings
// ============================================================================

/// Auto connect equipment setting
class AutoConnectSettingsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final dao = ref.read(settingsDaoProvider);
    return await dao.getAutoConnectEquipment();
  }

  Future<void> setAutoConnect(bool enabled) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setAutoConnectEquipment(enabled);
    state = AsyncData(enabled);
  }
}

final autoConnectSettingsProvider =
    AsyncNotifierProvider<AutoConnectSettingsNotifier, bool>(() {
      return AutoConnectSettingsNotifier();
    });

// ============================================================================
// Horizon Profile Utilities
// ============================================================================

/// 8 compass directions for horizon profile definition
const List<String> horizonDirections = [
  'N',
  'NE',
  'E',
  'SE',
  'S',
  'SW',
  'W',
  'NW',
];

/// Azimuth angles corresponding to each compass direction
const List<double> horizonDirectionAzimuths = [
  0.0,
  45.0,
  90.0,
  135.0,
  180.0,
  225.0,
  270.0,
  315.0,
];

/// Bortle scale descriptions and limiting magnitudes
class BortleScale {
  static const Map<int, String> descriptions = {
    1: 'Excellent dark-sky site',
    2: 'Typical truly dark site',
    3: 'Rural sky',
    4: 'Rural/suburban transition',
    5: 'Suburban sky',
    6: 'Bright suburban sky',
    7: 'Suburban/urban transition',
    8: 'City sky',
    9: 'Inner-city sky',
  };

  static const Map<int, double> limitingMagnitudes = {
    1: 7.6,
    2: 7.1,
    3: 6.6,
    4: 6.2,
    5: 5.9,
    6: 5.5,
    7: 5.0,
    8: 4.5,
    9: 4.0,
  };

  /// Get limiting magnitude for a Bortle class (1-9)
  static double limitingMagnitude(int bortleClass) {
    return limitingMagnitudes[bortleClass.clamp(1, 9)] ?? 5.9;
  }

  /// Get description for a Bortle class (1-9)
  static String description(int bortleClass) {
    return descriptions[bortleClass.clamp(1, 9)] ?? 'Unknown';
  }
}

/// Utility for parsing and interpolating horizon profiles.
///
/// A horizon profile is stored as a JSON map with 8 compass direction keys
/// (N, NE, E, SE, S, SW, W, NW) mapped to altitude values in degrees.
class HorizonProfile {
  final Map<String, double> _altitudes;

  HorizonProfile(this._altitudes);

  /// Parse a horizon profile from JSON string.
  factory HorizonProfile.fromJson(String json) {
    try {
      final decoded = Map<String, dynamic>.from(
        // Using dart:convert would require an import; parse manually for simple JSON
        _parseSimpleJson(json),
      );
      final altitudes = <String, double>{};
      for (final dir in horizonDirections) {
        final val = decoded[dir];
        if (val is num) {
          altitudes[dir] = val.toDouble().clamp(0.0, 89.0);
        } else {
          altitudes[dir] = 0.0;
        }
      }
      return HorizonProfile(altitudes);
    } catch (_) {
      // Return flat horizon on parse failure - this is a data error,
      // not something we should silently swallow. Log it.
      return HorizonProfile._default();
    }
  }

  factory HorizonProfile._default() {
    final altitudes = <String, double>{};
    for (final dir in horizonDirections) {
      altitudes[dir] = 0.0;
    }
    return HorizonProfile(altitudes);
  }

  /// Get the altitude at a specific compass direction
  double altitudeAt(String direction) => _altitudes[direction] ?? 0.0;

  /// Get interpolated horizon altitude at any azimuth (0-360 degrees).
  /// Uses cubic-like smooth interpolation between compass points.
  double altitudeAtAzimuth(double azimuthDeg) {
    // Normalize azimuth to 0-360
    var az = azimuthDeg % 360.0;
    if (az < 0) az += 360.0;

    // Find which two compass points we're between
    const segmentSize = 360.0 / 8.0; // 45 degrees per segment
    final segmentIndex = (az / segmentSize).floor() % 8;
    final nextIndex = (segmentIndex + 1) % 8;

    // Fraction within this segment (0.0 to 1.0)
    final fraction = (az - segmentIndex * segmentSize) / segmentSize;

    final alt1 = _altitudes[horizonDirections[segmentIndex]] ?? 0.0;
    final alt2 = _altitudes[horizonDirections[nextIndex]] ?? 0.0;

    // Smoothstep interpolation for natural-looking transitions
    final t = fraction * fraction * (3.0 - 2.0 * fraction);
    return alt1 + (alt2 - alt1) * t;
  }

  /// Check if a given altitude at a given azimuth is above the custom horizon
  bool isAboveHorizon(double altitudeDeg, double azimuthDeg) {
    return altitudeDeg >= altitudeAtAzimuth(azimuthDeg);
  }

  /// Encode back to JSON string
  String toJson() {
    final parts = <String>[];
    for (final dir in horizonDirections) {
      final val = _altitudes[dir] ?? 0.0;
      parts.add('"$dir":${val.toStringAsFixed(1)}');
    }
    return '{${parts.join(',')}}';
  }

  /// Simple JSON parser for flat string->number maps.
  /// Avoids importing dart:convert in this provider file.
  static Map<String, dynamic> _parseSimpleJson(String json) {
    final result = <String, dynamic>{};
    // Strip braces and split by comma
    var trimmed = json.trim();
    if (trimmed.startsWith('{')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('}')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.isEmpty) return result;

    for (final pair in trimmed.split(',')) {
      final colonIdx = pair.indexOf(':');
      if (colonIdx < 0) continue;
      var key = pair.substring(0, colonIdx).trim();
      final value = pair.substring(colonIdx + 1).trim();
      // Strip quotes from key
      if (key.startsWith('"') && key.endsWith('"')) {
        key = key.substring(1, key.length - 1);
      }
      final numVal = double.tryParse(value);
      if (numVal != null) {
        result[key] = numVal;
      }
    }
    return result;
  }

  /// Whether this profile is all zeros (flat horizon)
  bool get isFlat => _altitudes.values.every((v) => v == 0.0);

  /// Build a profile from arbitrary (azimuth, altitude) samples by binning
  /// them onto the eight compass directions.
  ///
  /// Each compass sector spans 45° centred on its azimuth (e.g. N covers
  /// 337.5°–22.5°). Within a sector the HIGHEST sampled altitude wins, so an
  /// imported skyline never under-reports an obstruction. Sectors with no
  /// samples default to 0° (open sky).
  factory HorizonProfile.fromSamples(
    List<({double azimuth, double altitude})> samples,
  ) {
    final altitudes = <String, double>{
      for (final dir in horizonDirections) dir: 0.0,
    };
    for (final s in samples) {
      var az = s.azimuth % 360.0;
      if (az < 0) az += 360.0;
      // Round to the nearest of the 8 directions (45° sectors, N straddles 0°).
      final index = (((az + 22.5) % 360.0) / 45.0).floor() % 8;
      final dir = horizonDirections[index];
      final alt = s.altitude.clamp(0.0, 89.0);
      if (alt > altitudes[dir]!) altitudes[dir] = alt;
    }
    return HorizonProfile(altitudes);
  }

  /// Parse a horizon dump (CSV or whitespace-separated "azimuth altitude"
  /// pairs, one per line) into a profile.
  ///
  /// Accepts the common Stellarium-style `.hor` format and plain CSV:
  ///   * comma OR whitespace separates the azimuth and altitude on each line;
  ///   * blank lines and comment lines (starting with `#`, `//`, or `;`) are
  ///     ignored;
  ///   * each data line must contain at least two numeric fields.
  ///
  /// Throws [FormatException] on a malformed line or if no samples are found.
  factory HorizonProfile.parseHorizonText(String text) {
    final samples = <({double azimuth, double altitude})>[];
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#') ||
          trimmed.startsWith('//') ||
          trimmed.startsWith(';')) {
        continue;
      }
      final parts = trimmed
          .split(RegExp(r'[\s,]+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length < 2) {
        throw FormatException(
          'Horizon import line ${i + 1}: expected "azimuth altitude", '
          'got "$trimmed"',
        );
      }
      final az = double.tryParse(parts[0]);
      final alt = double.tryParse(parts[1]);
      if (az == null || alt == null) {
        throw FormatException(
          'Horizon import line ${i + 1}: non-numeric value in "$trimmed"',
        );
      }
      samples.add((azimuth: az, altitude: alt));
    }
    if (samples.isEmpty) {
      throw const FormatException(
        'Horizon import contained no usable azimuth/altitude pairs',
      );
    }
    return HorizonProfile.fromSamples(samples);
  }
}

/// Focused provider for Bortle class.
final bortleClassProvider = Provider<int>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  return settingsAsync.valueOrNull?.bortleClass ?? 5;
});

/// Focused provider for parsed horizon profile.
final horizonProfileProvider = Provider<HorizonProfile>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  final json =
      settingsAsync.valueOrNull?.horizonProfileJson ??
      '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}';
  return HorizonProfile.fromJson(json);
});

import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// Defines how the safety system behaves when weather/safety devices fail or are unavailable
enum SafetyFailMode {
  /// Treat unavailable safety data as safe; allow imaging to continue uninterrupted.
  failOpen,
  /// Treat unavailable safety data as unsafe; pause imaging and optionally park the mount.
  failClosed,
  /// Treat unavailable safety data as safe but emit a UI warning so the user is aware.
  warnOnly,
}

@freezed
class ObserverLocation with _$ObserverLocation {
  const factory ObserverLocation({
    required double latitude,
    required double longitude,
    required double elevation,
  }) = _ObserverLocation;

  factory ObserverLocation.fromJson(Map<String, dynamic> json) =>
      _$ObserverLocationFromJson(json);
}

@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    ObserverLocation? location,
    @Default('dark') String theme,
    @Default('en') String language,
    @Default(true) bool autoConnect,
    // Additional fields for compatibility with provider AppSettings
    @Default(0.0) double latitude,
    @Default(0.0) double longitude,
    @Default(0.0) double elevation,
    @Default('') String fileNamingPattern,
    @Default(5) int meridianFlipMinutes,
    @Default(60) int autoFocusEveryMinutes,
    @Default(3) int ditherEveryFrames,
    @Default(60) int plateSolveTimeout,
    @Default(30.0) double plateSolveSearchRadius,
    @Default('') String discordWebhook,
    @Default('') String pushoverKey,
    @Default('') String pushoverUser,
    @Default('') String astapPath,
    // Discovery settings
    @Default(true) bool autoDiscoverOnLaunch,
    @Default('') String accentColor,
    @Default('Medium') String fontSize,
    @Default('Auto') String uiScale, // Auto, Small (0.8x), Normal (1.0x), Large (1.2x), Extra Large (1.4x)
    // Protocol settings
    @Default('localhost') String indiServerHost,
    @Default(7624) int indiServerPort,
    @Default(false) bool indiAutoConnect,
    @Default('localhost') String alpacaServerHost,
    @Default(11111) int alpacaServerPort,
    @Default(false) bool alpacaAutoDiscover,
    // Sequencer execution settings
    @Default(true) bool useNativeExecution,
    @Default(false) bool useSimulationMode,
    // Image capture settings
    @Default('') String imageOutputPath,
    @Default('') String observer,
    @Default('') String telescope,
    @Default('') String instrument,
    // Update settings
    @Default(true) bool updateCheckEnabled,
    @Default('') String updateServerUrl,
    @Default('stable') String updateChannel,
    @Default(24) int updateCheckIntervalHours,
    @Default('') String skippedUpdateVersion,
    // Safety settings
    @Default(SafetyFailMode.failClosed) SafetyFailMode safetyFailMode,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}

// Extension to provide compatibility getters
extension AppSettingsExtension on AppSettings {
  /// Get latitude from location or direct field
  double get effectiveLatitude => this.location?.latitude ?? this.latitude;
  
  /// Get longitude from location or direct field
  double get effectiveLongitude => this.location?.longitude ?? this.longitude;
  
  /// Get elevation from location or direct field
  double get effectiveElevation => this.location?.elevation ?? this.elevation;
}

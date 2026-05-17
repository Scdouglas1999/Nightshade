import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/network_backend.dart';
import 'database_provider.dart';
import 'backend_provider.dart';
import '../models/settings/app_settings.dart' as models;
import '../models/settings/app_settings.dart' show SafetyFailMode;
import '../models/imaging/imaging_models.dart'
    show AutofocusSettings, FilterAutofocusConfig;

// ============================================================================
// App Settings - Complete settings model
// ============================================================================

/// Runtime, in-memory application-settings state owned by
/// [AppSettingsNotifier]. Distinct from the persisted/freezed
/// `AppSettings` model in `models/settings/app_settings.dart`, which is the
/// Rust-bridge / JSON-persisted snapshot. Renamed from `AppSettings` to
/// disambiguate (audit-arch §2.2).
class AppSettingsState {
  // General
  final bool startMinimized;
  final bool autoConnectEquipment;
  final bool autoSaveSequences;
  final bool confirmBeforeClosing;
  final bool autoDiscoverOnLaunch;

  // Appearance
  final String theme; // 'dark' or 'light'
  final String language; // 'en', 'es'
  final String accentColor; // hex color
  final String fontSize; // 'Small', 'Medium', 'Large'
  final String
      uiScale; // 'Auto', 'Small (0.8x)', 'Normal (1.0x)', 'Large (1.2x)', 'Extra Large (1.4x)'
  final bool sidebarCollapsed;

  // Location
  final double latitude;
  final double longitude;
  final double elevation;
  final String timezone;
  final bool useSystemTime;

  // Imaging
  final String imageFormat; // 'FITS', 'XISF', 'TIFF'
  final String fileNamingPattern;
  final String bitDepth; // '16-bit', '32-bit'

  // Sequencer
  final bool parkOnUnsafeWeather;
  final bool parkBeforeDawn;
  final int meridianFlipMinutes; // minutes before meridian
  final bool autoFocusOnFilterChange;
  final bool useFilterFocusOffsets; // Apply focus offsets when changing filters
  final int autoFocusEveryMinutes;
  final bool ditherEnabled;
  final int ditherEveryFrames;
  final SafetyFailMode
      safetyFailMode; // How to behave when safety data unavailable

  // Plate Solving
  final String plateSolver; // 'ASTAP', 'Astrometry.net', 'PlateSolve2'
  final String astapPath;
  final String astrometryPath;
  final int plateSolveTimeout;
  final double plateSolveSearchRadius;
  final bool blindSolve;

  // PHD2 Guiding
  final String phd2Path;
  final String phd2Host;
  final int phd2Port;

  // Notifications
  final bool notificationsEnabled;
  final String discordWebhook;
  final String pushoverKey;
  final String pushoverUser;
  final bool notifyOnSequenceComplete;
  final bool notifyOnError;
  final bool notifyOnMeridianFlip;
  final bool soundEnabled;

  // File Paths
  final String imageOutputPath;
  final String sequencesPath;
  final String databasePath;
  final String logsPath;

  // Protocol Settings
  final String indiServerHost;
  final int indiServerPort;
  final bool indiAutoConnect;
  final String alpacaServerHost;
  final int alpacaServerPort;
  final bool alpacaAutoDiscover;

  // Sequencer Execution Settings
  final bool useNativeExecution;
  final bool useSimulationMode;

  // Remote Access / Web Server Settings
  final bool webServerEnabled;
  final int webServerPort;

  // Equipment Settings - Camera
  final String coolingBehavior; // 'On Connect', 'Manual', 'Never'
  final int defaultGain;
  final int defaultOffset;

  // Equipment Settings - Mount
  final bool enableMeridianFlip;

  // Equipment Settings - Focuser
  final bool tempCompensation;
  final double tempCoefficient;
  final int backlashCompensation;

  // Equipment Settings - Guider
  final String ditherScale; // 'Small', 'Medium', 'Large'
  final double settleThreshold;
  final int settleTimeout;

  // Observing Environment
  final int bortleClass; // 1-9, Bortle dark-sky scale
  final String
      horizonProfileJson; // JSON: 8 altitude values at N/NE/E/SE/S/SW/W/NW

  // Autofocus Settings
  final String afMethod; // 'Star HFR'
  final String afCurveFitting; // 'Hyperbolic', 'Parabolic', 'Trend Lines'
  final int afStepSize; // step size between measurement points
  final double afExposureTime; // default exposure for AF frames
  final int afInitialOffsetSteps; // how many steps out from center
  final int afNumberOfAttempts; // retry count on failure
  final int afUseBrightestNStars; // 0 = use all
  final double afOuterCropRatio;
  final double afInnerCropRatio;
  final int afBinning;
  final double afRSquaredThreshold;
  final bool afDisableGuidingDuringAf;
  final int afFocuserSettleTimeMs;
  final int afExposuresPerPoint;
  final String afBacklashCompMethod; // 'None', 'Overshoot', 'Absolute'
  final int afBacklashIn;
  final int afBacklashOut;
  final String
      afAutofocusFilterName; // designated filter for AF runs (empty = use current)
  final String
      afFilterSettingsJson; // JSON map of filter name to FilterAutofocusConfig

  const AppSettingsState({
    // General
    this.startMinimized = false,
    this.autoConnectEquipment = true,
    this.autoSaveSequences = true,
    this.confirmBeforeClosing = true,
    this.autoDiscoverOnLaunch = true,

    // Appearance
    this.theme = 'dark',
    this.language = 'en',
    this.accentColor = '#6366F1',
    this.fontSize = 'Medium',
    this.uiScale = 'Auto',
    this.sidebarCollapsed = false,

    // Location
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.elevation = 0.0,
    this.timezone = 'UTC',
    this.useSystemTime = true,

    // Imaging
    this.imageFormat = 'FITS',
    this.fileNamingPattern = r'$TARGET_$FILTER_$DATE_$SEQ',
    this.bitDepth = '16-bit',

    // Sequencer
    this.parkOnUnsafeWeather = true,
    this.parkBeforeDawn = true,
    this.meridianFlipMinutes = 5,
    this.autoFocusOnFilterChange = true,
    this.useFilterFocusOffsets = true,
    this.autoFocusEveryMinutes = 60,
    this.ditherEnabled = true,
    this.ditherEveryFrames = 3,
    this.safetyFailMode = SafetyFailMode.failClosed,

    // Plate Solving
    this.plateSolver = 'ASTAP',
    this.astapPath = '',
    this.astrometryPath = '',
    this.plateSolveTimeout = 60,
    this.plateSolveSearchRadius = 30.0,
    this.blindSolve = false,

    // PHD2 Guiding
    this.phd2Path = '',
    this.phd2Host = 'localhost',
    this.phd2Port = 4400,

    // Notifications
    this.notificationsEnabled = true,
    this.discordWebhook = '',
    this.pushoverKey = '',
    this.pushoverUser = '',
    this.notifyOnSequenceComplete = true,
    this.notifyOnError = true,
    this.notifyOnMeridianFlip = false,
    this.soundEnabled = true,

    // File Paths
    this.imageOutputPath = '',
    this.sequencesPath = '',
    this.databasePath = '',
    this.logsPath = '',

    // Protocol Settings
    this.indiServerHost = 'localhost',
    this.indiServerPort = 7624,
    this.indiAutoConnect = false,
    this.alpacaServerHost = 'localhost',
    this.alpacaServerPort = 11111,
    this.alpacaAutoDiscover = false,

    // Sequencer Execution
    this.useNativeExecution = true,
    this.useSimulationMode = false,

    // Remote Access / Web Server
    this.webServerEnabled = false,
    this.webServerPort = 8080,

    // Equipment Settings - Camera
    this.coolingBehavior = 'On Connect',
    this.defaultGain = 100,
    this.defaultOffset = 50,

    // Equipment Settings - Mount
    this.enableMeridianFlip = true,

    // Equipment Settings - Focuser
    this.tempCompensation = true,
    this.tempCoefficient = -12.0,
    this.backlashCompensation = 0,

    // Equipment Settings - Guider
    this.ditherScale = 'Medium',
    this.settleThreshold = 0.5,
    this.settleTimeout = 30,

    // Observing Environment
    this.bortleClass = 5,
    this.horizonProfileJson =
        '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}',

    // Autofocus Settings
    this.afMethod = 'Star HFR',
    this.afCurveFitting = 'Hyperbolic',
    this.afStepSize = 50,
    this.afExposureTime = 4.0,
    this.afInitialOffsetSteps = 4,
    this.afNumberOfAttempts = 1,
    this.afUseBrightestNStars = 0,
    this.afOuterCropRatio = 1.0,
    this.afInnerCropRatio = 0.0,
    this.afBinning = 1,
    this.afRSquaredThreshold = 0.7,
    this.afDisableGuidingDuringAf = false,
    this.afFocuserSettleTimeMs = 500,
    this.afExposuresPerPoint = 1,
    this.afBacklashCompMethod = 'Overshoot',
    this.afBacklashIn = 350,
    this.afBacklashOut = 0,
    this.afAutofocusFilterName = '',
    this.afFilterSettingsJson = '{}',
  });

  AppSettingsState copyWith({
    bool? startMinimized,
    bool? autoConnectEquipment,
    bool? autoSaveSequences,
    bool? confirmBeforeClosing,
    bool? autoDiscoverOnLaunch,
    String? theme,
    String? language,
    String? accentColor,
    String? fontSize,
    String? uiScale,
    bool? sidebarCollapsed,
    double? latitude,
    double? longitude,
    double? elevation,
    String? timezone,
    bool? useSystemTime,
    String? imageFormat,
    String? fileNamingPattern,
    String? bitDepth,
    bool? parkOnUnsafeWeather,
    bool? parkBeforeDawn,
    int? meridianFlipMinutes,
    bool? autoFocusOnFilterChange,
    bool? useFilterFocusOffsets,
    int? autoFocusEveryMinutes,
    bool? ditherEnabled,
    int? ditherEveryFrames,
    SafetyFailMode? safetyFailMode,
    String? plateSolver,
    String? astapPath,
    String? astrometryPath,
    int? plateSolveTimeout,
    double? plateSolveSearchRadius,
    bool? blindSolve,
    String? phd2Path,
    String? phd2Host,
    int? phd2Port,
    bool? notificationsEnabled,
    String? discordWebhook,
    String? pushoverKey,
    String? pushoverUser,
    bool? notifyOnSequenceComplete,
    bool? notifyOnError,
    bool? notifyOnMeridianFlip,
    bool? soundEnabled,
    String? imageOutputPath,
    String? sequencesPath,
    String? databasePath,
    String? logsPath,
    String? indiServerHost,
    int? indiServerPort,
    bool? indiAutoConnect,
    String? alpacaServerHost,
    int? alpacaServerPort,
    bool? alpacaAutoDiscover,
    bool? useNativeExecution,
    bool? useSimulationMode,
    // Remote Access / Web Server
    bool? webServerEnabled,
    int? webServerPort,
    // Equipment Settings
    String? coolingBehavior,
    int? defaultGain,
    int? defaultOffset,
    bool? enableMeridianFlip,
    bool? tempCompensation,
    double? tempCoefficient,
    int? backlashCompensation,
    String? ditherScale,
    double? settleThreshold,
    int? settleTimeout,
    // Observing Environment
    int? bortleClass,
    String? horizonProfileJson,
    // Autofocus Settings
    String? afMethod,
    String? afCurveFitting,
    int? afStepSize,
    double? afExposureTime,
    int? afInitialOffsetSteps,
    int? afNumberOfAttempts,
    int? afUseBrightestNStars,
    double? afOuterCropRatio,
    double? afInnerCropRatio,
    int? afBinning,
    double? afRSquaredThreshold,
    bool? afDisableGuidingDuringAf,
    int? afFocuserSettleTimeMs,
    int? afExposuresPerPoint,
    String? afBacklashCompMethod,
    int? afBacklashIn,
    int? afBacklashOut,
    String? afAutofocusFilterName,
    String? afFilterSettingsJson,
  }) {
    return AppSettingsState(
      startMinimized: startMinimized ?? this.startMinimized,
      autoConnectEquipment: autoConnectEquipment ?? this.autoConnectEquipment,
      autoSaveSequences: autoSaveSequences ?? this.autoSaveSequences,
      confirmBeforeClosing: confirmBeforeClosing ?? this.confirmBeforeClosing,
      autoDiscoverOnLaunch: autoDiscoverOnLaunch ?? this.autoDiscoverOnLaunch,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      accentColor: accentColor ?? this.accentColor,
      fontSize: fontSize ?? this.fontSize,
      uiScale: uiScale ?? this.uiScale,
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
      timezone: timezone ?? this.timezone,
      useSystemTime: useSystemTime ?? this.useSystemTime,
      imageFormat: imageFormat ?? this.imageFormat,
      fileNamingPattern: fileNamingPattern ?? this.fileNamingPattern,
      bitDepth: bitDepth ?? this.bitDepth,
      parkOnUnsafeWeather: parkOnUnsafeWeather ?? this.parkOnUnsafeWeather,
      parkBeforeDawn: parkBeforeDawn ?? this.parkBeforeDawn,
      meridianFlipMinutes: meridianFlipMinutes ?? this.meridianFlipMinutes,
      autoFocusOnFilterChange:
          autoFocusOnFilterChange ?? this.autoFocusOnFilterChange,
      useFilterFocusOffsets:
          useFilterFocusOffsets ?? this.useFilterFocusOffsets,
      autoFocusEveryMinutes:
          autoFocusEveryMinutes ?? this.autoFocusEveryMinutes,
      ditherEnabled: ditherEnabled ?? this.ditherEnabled,
      ditherEveryFrames: ditherEveryFrames ?? this.ditherEveryFrames,
      safetyFailMode: safetyFailMode ?? this.safetyFailMode,
      plateSolver: plateSolver ?? this.plateSolver,
      astapPath: astapPath ?? this.astapPath,
      astrometryPath: astrometryPath ?? this.astrometryPath,
      plateSolveTimeout: plateSolveTimeout ?? this.plateSolveTimeout,
      plateSolveSearchRadius:
          plateSolveSearchRadius ?? this.plateSolveSearchRadius,
      blindSolve: blindSolve ?? this.blindSolve,
      phd2Path: phd2Path ?? this.phd2Path,
      phd2Host: phd2Host ?? this.phd2Host,
      phd2Port: phd2Port ?? this.phd2Port,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      discordWebhook: discordWebhook ?? this.discordWebhook,
      pushoverKey: pushoverKey ?? this.pushoverKey,
      pushoverUser: pushoverUser ?? this.pushoverUser,
      notifyOnSequenceComplete:
          notifyOnSequenceComplete ?? this.notifyOnSequenceComplete,
      notifyOnError: notifyOnError ?? this.notifyOnError,
      notifyOnMeridianFlip: notifyOnMeridianFlip ?? this.notifyOnMeridianFlip,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      imageOutputPath: imageOutputPath ?? this.imageOutputPath,
      sequencesPath: sequencesPath ?? this.sequencesPath,
      databasePath: databasePath ?? this.databasePath,
      logsPath: logsPath ?? this.logsPath,
      indiServerHost: indiServerHost ?? this.indiServerHost,
      indiServerPort: indiServerPort ?? this.indiServerPort,
      indiAutoConnect: indiAutoConnect ?? this.indiAutoConnect,
      alpacaServerHost: alpacaServerHost ?? this.alpacaServerHost,
      alpacaServerPort: alpacaServerPort ?? this.alpacaServerPort,
      alpacaAutoDiscover: alpacaAutoDiscover ?? this.alpacaAutoDiscover,
      useNativeExecution: useNativeExecution ?? this.useNativeExecution,
      useSimulationMode: useSimulationMode ?? this.useSimulationMode,
      // Remote Access / Web Server
      webServerEnabled: webServerEnabled ?? this.webServerEnabled,
      webServerPort: webServerPort ?? this.webServerPort,
      // Equipment Settings
      coolingBehavior: coolingBehavior ?? this.coolingBehavior,
      defaultGain: defaultGain ?? this.defaultGain,
      defaultOffset: defaultOffset ?? this.defaultOffset,
      enableMeridianFlip: enableMeridianFlip ?? this.enableMeridianFlip,
      tempCompensation: tempCompensation ?? this.tempCompensation,
      tempCoefficient: tempCoefficient ?? this.tempCoefficient,
      backlashCompensation: backlashCompensation ?? this.backlashCompensation,
      ditherScale: ditherScale ?? this.ditherScale,
      settleThreshold: settleThreshold ?? this.settleThreshold,
      settleTimeout: settleTimeout ?? this.settleTimeout,
      // Autofocus Settings
      bortleClass: bortleClass ?? this.bortleClass,
      horizonProfileJson: horizonProfileJson ?? this.horizonProfileJson,
      afMethod: afMethod ?? this.afMethod,
      afCurveFitting: afCurveFitting ?? this.afCurveFitting,
      afStepSize: afStepSize ?? this.afStepSize,
      afExposureTime: afExposureTime ?? this.afExposureTime,
      afInitialOffsetSteps: afInitialOffsetSteps ?? this.afInitialOffsetSteps,
      afNumberOfAttempts: afNumberOfAttempts ?? this.afNumberOfAttempts,
      afUseBrightestNStars: afUseBrightestNStars ?? this.afUseBrightestNStars,
      afOuterCropRatio: afOuterCropRatio ?? this.afOuterCropRatio,
      afInnerCropRatio: afInnerCropRatio ?? this.afInnerCropRatio,
      afBinning: afBinning ?? this.afBinning,
      afRSquaredThreshold: afRSquaredThreshold ?? this.afRSquaredThreshold,
      afDisableGuidingDuringAf:
          afDisableGuidingDuringAf ?? this.afDisableGuidingDuringAf,
      afFocuserSettleTimeMs:
          afFocuserSettleTimeMs ?? this.afFocuserSettleTimeMs,
      afExposuresPerPoint: afExposuresPerPoint ?? this.afExposuresPerPoint,
      afBacklashCompMethod: afBacklashCompMethod ?? this.afBacklashCompMethod,
      afBacklashIn: afBacklashIn ?? this.afBacklashIn,
      afBacklashOut: afBacklashOut ?? this.afBacklashOut,
      afAutofocusFilterName:
          afAutofocusFilterName ?? this.afAutofocusFilterName,
      afFilterSettingsJson: afFilterSettingsJson ?? this.afFilterSettingsJson,
    );
  }
}

/// Main app settings notifier that persists all settings to database
class AppSettingsNotifier extends AsyncNotifier<AppSettingsState> {
  models.AppSettings? _remoteSettingsSnapshot;

  AppSettingsState _fromRemoteSettings(models.AppSettings remote) {
    final location = remote.location;
    return AppSettingsState(
      autoConnectEquipment: remote.autoConnect,
      autoDiscoverOnLaunch: remote.autoDiscoverOnLaunch,
      theme: remote.theme,
      language: remote.language,
      accentColor: remote.accentColor.isEmpty ? '#6366F1' : remote.accentColor,
      fontSize: remote.fontSize,
      uiScale: remote.uiScale,
      latitude: location?.latitude ?? remote.latitude,
      longitude: location?.longitude ?? remote.longitude,
      elevation: location?.elevation ?? remote.elevation,
      fileNamingPattern: remote.fileNamingPattern.isEmpty
          ? r'$TARGET_$FILTER_$DATE_$SEQ'
          : remote.fileNamingPattern,
      meridianFlipMinutes: remote.meridianFlipMinutes,
      autoFocusEveryMinutes: remote.autoFocusEveryMinutes,
      ditherEveryFrames: remote.ditherEveryFrames,
      plateSolveTimeout: remote.plateSolveTimeout,
      plateSolveSearchRadius: remote.plateSolveSearchRadius,
      discordWebhook: remote.discordWebhook,
      pushoverKey: remote.pushoverKey,
      pushoverUser: remote.pushoverUser,
      astapPath: remote.astapPath,
      indiServerHost: remote.indiServerHost,
      indiServerPort: remote.indiServerPort,
      indiAutoConnect: remote.indiAutoConnect,
      alpacaServerHost: remote.alpacaServerHost,
      alpacaServerPort: remote.alpacaServerPort,
      alpacaAutoDiscover: remote.alpacaAutoDiscover,
      useNativeExecution: remote.useNativeExecution,
      useSimulationMode: remote.useSimulationMode,
      imageOutputPath: remote.imageOutputPath,
      safetyFailMode: remote.safetyFailMode,
    );
  }

  models.AppSettings _toRemoteSettings(AppSettingsState settings) {
    final previous = _remoteSettingsSnapshot;
    return models.AppSettings(
      location: models.ObserverLocation(
        latitude: settings.latitude,
        longitude: settings.longitude,
        elevation: settings.elevation,
      ),
      theme: settings.theme,
      language: settings.language,
      autoConnect: settings.autoConnectEquipment,
      latitude: settings.latitude,
      longitude: settings.longitude,
      elevation: settings.elevation,
      fileNamingPattern: settings.fileNamingPattern,
      meridianFlipMinutes: settings.meridianFlipMinutes,
      autoFocusEveryMinutes: settings.autoFocusEveryMinutes,
      ditherEveryFrames: settings.ditherEveryFrames,
      plateSolveTimeout: settings.plateSolveTimeout,
      plateSolveSearchRadius: settings.plateSolveSearchRadius,
      discordWebhook: settings.discordWebhook,
      pushoverKey: settings.pushoverKey,
      pushoverUser: settings.pushoverUser,
      astapPath: settings.astapPath,
      autoDiscoverOnLaunch: settings.autoDiscoverOnLaunch,
      accentColor: settings.accentColor,
      fontSize: settings.fontSize,
      uiScale: settings.uiScale,
      indiServerHost: settings.indiServerHost,
      indiServerPort: settings.indiServerPort,
      indiAutoConnect: settings.indiAutoConnect,
      alpacaServerHost: settings.alpacaServerHost,
      alpacaServerPort: settings.alpacaServerPort,
      alpacaAutoDiscover: settings.alpacaAutoDiscover,
      useNativeExecution: settings.useNativeExecution,
      useSimulationMode: settings.useSimulationMode,
      imageOutputPath: settings.imageOutputPath,
      observer: previous?.observer ?? '',
      telescope: previous?.telescope ?? '',
      instrument: previous?.instrument ?? '',
      updateCheckEnabled: previous?.updateCheckEnabled ?? true,
      updateServerUrl: previous?.updateServerUrl ?? '',
      updateChannel: previous?.updateChannel ?? 'stable',
      updateCheckIntervalHours: previous?.updateCheckIntervalHours ?? 24,
      skippedUpdateVersion: previous?.skippedUpdateVersion ?? '',
      safetyFailMode: settings.safetyFailMode,
    );
  }

  Future<void> _writeRemoteSettings(AppSettingsState settings) async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      throw StateError(
          'Remote settings write requested without network backend');
    }

    final remote = _toRemoteSettings(settings);
    await backend.updateSettings(remote);
    _remoteSettingsSnapshot = remote;
  }

  @override
  Future<AppSettingsState> build() async {
    final backend = ref.watch(backendProvider);
    if (backend is NetworkBackend) {
      final remoteSettings = await backend.getSettings();
      _remoteSettingsSnapshot = remoteSettings;
      return _fromRemoteSettings(remoteSettings);
    }

    _remoteSettingsSnapshot = null;
    final dao = ref.read(settingsDaoProvider);
    final allSettings = await dao.getAllSettings();

    return AppSettingsState(
      // General
      startMinimized: _parseBool(allSettings['start_minimized'], false),
      autoConnectEquipment:
          _parseBool(allSettings['auto_connect_equipment'], true),
      autoSaveSequences: _parseBool(allSettings['auto_save_sequences'], true),
      confirmBeforeClosing:
          _parseBool(allSettings['confirm_before_closing'], true),
      autoDiscoverOnLaunch:
          _parseBool(allSettings['auto_discover_on_launch'], true),

      // Appearance
      theme: allSettings['theme'] ?? 'dark',
      language: allSettings['language'] ?? 'en',
      accentColor: allSettings['accent_color'] ?? '#6366F1',
      fontSize: allSettings['font_size'] ?? 'Medium',
      uiScale: allSettings['ui_scale'] ?? 'Auto',
      sidebarCollapsed: _parseBool(allSettings['sidebar_collapsed'], false),

      // Location
      latitude: _parseDouble(allSettings['observer_latitude'], 0.0),
      longitude: _parseDouble(allSettings['observer_longitude'], 0.0),
      elevation: _parseDouble(allSettings['observer_elevation'], 0.0),
      timezone: allSettings['timezone'] ?? 'UTC',
      useSystemTime: _parseBool(allSettings['use_system_time'], true),

      // Imaging
      imageFormat: allSettings['image_format'] ?? 'FITS',
      fileNamingPattern:
          allSettings['file_naming_pattern'] ?? r'$TARGET_$FILTER_$DATE_$SEQ',
      bitDepth: allSettings['bit_depth'] ?? '16-bit',

      // Sequencer
      parkOnUnsafeWeather:
          _parseBool(allSettings['park_on_unsafe_weather'], true),
      parkBeforeDawn: _parseBool(allSettings['park_before_dawn'], true),
      meridianFlipMinutes: _parseInt(allSettings['meridian_flip_minutes'], 5),
      autoFocusOnFilterChange:
          _parseBool(allSettings['auto_focus_on_filter_change'], true),
      useFilterFocusOffsets:
          _parseBool(allSettings['use_filter_focus_offsets'], true),
      autoFocusEveryMinutes:
          _parseInt(allSettings['auto_focus_every_minutes'], 60),
      ditherEnabled: _parseBool(allSettings['dither_enabled'], true),
      ditherEveryFrames: _parseInt(allSettings['dither_every_frames'], 3),
      safetyFailMode: _parseSafetyFailMode(allSettings['safety_fail_mode']),

      // Plate Solving
      plateSolver: allSettings['plate_solver'] ?? 'ASTAP',
      astapPath: allSettings['astap_path'] ?? '',
      astrometryPath: allSettings['astrometry_path'] ?? '',
      plateSolveTimeout: _parseInt(allSettings['plate_solve_timeout'], 60),
      plateSolveSearchRadius:
          _parseDouble(allSettings['plate_solve_search_radius'], 30.0),
      blindSolve: _parseBool(allSettings['blind_solve'], false),

      // PHD2 Guiding
      phd2Path: allSettings['phd2_path'] ?? '',
      phd2Host: allSettings['phd2_host'] ?? 'localhost',
      phd2Port: _parseInt(allSettings['phd2_port'], 4400),

      // Notifications
      notificationsEnabled:
          _parseBool(allSettings['notifications_enabled'], true),
      discordWebhook: allSettings['discord_webhook'] ?? '',
      pushoverKey: allSettings['pushover_key'] ?? '',
      pushoverUser: allSettings['pushover_user'] ?? '',
      notifyOnSequenceComplete:
          _parseBool(allSettings['notify_on_sequence_complete'], true),
      notifyOnError: _parseBool(allSettings['notify_on_error'], true),
      notifyOnMeridianFlip:
          _parseBool(allSettings['notify_on_meridian_flip'], false),
      soundEnabled: _parseBool(allSettings['sound_enabled'], true),

      // File Paths
      imageOutputPath: allSettings['image_output_path'] ?? '',
      sequencesPath: allSettings['sequences_path'] ?? '',
      databasePath: allSettings['database_path'] ?? '',
      logsPath: allSettings['logs_path'] ?? '',

      // Protocol Settings
      indiServerHost: allSettings['indi_server_host'] ?? 'localhost',
      indiServerPort: _parseInt(allSettings['indi_server_port'], 7624),
      indiAutoConnect: _parseBool(allSettings['indi_auto_connect'], false),
      alpacaServerHost: allSettings['alpaca_server_host'] ?? 'localhost',
      alpacaServerPort: _parseInt(allSettings['alpaca_server_port'], 11111),
      alpacaAutoDiscover:
          _parseBool(allSettings['alpaca_auto_discover'], false),

      // Sequencer Execution
      useNativeExecution: _parseBool(allSettings['use_native_execution'], true),
      useSimulationMode: _parseBool(allSettings['use_simulation_mode'], false),

      // Remote Access / Web Server
      webServerEnabled: _parseBool(allSettings['web_server_enabled'], false),
      webServerPort: _parseInt(allSettings['web_server_port'], 8080),

      // Equipment Settings - Camera
      coolingBehavior: allSettings['cooling_behavior'] ?? 'On Connect',
      defaultGain: _parseInt(allSettings['default_gain'], 100),
      defaultOffset: _parseInt(allSettings['default_offset'], 50),

      // Equipment Settings - Mount
      enableMeridianFlip: _parseBool(allSettings['enable_meridian_flip'], true),

      // Equipment Settings - Focuser
      tempCompensation: _parseBool(allSettings['temp_compensation'], true),
      tempCoefficient: _parseDouble(allSettings['temp_coefficient'], -12.0),
      backlashCompensation: _parseInt(allSettings['backlash_compensation'], 0),

      // Equipment Settings - Guider
      ditherScale: allSettings['dither_scale'] ?? 'Medium',
      settleThreshold: _parseDouble(allSettings['settle_threshold'], 0.5),
      settleTimeout: _parseInt(allSettings['settle_timeout'], 30),

      // Autofocus Settings
      // Observing Environment
      bortleClass: _parseInt(allSettings['bortle_class'], 5),
      horizonProfileJson: allSettings['horizon_profile_json'] ??
          '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}',

      afMethod: allSettings['af_method'] ?? 'Star HFR',
      afCurveFitting: allSettings['af_curve_fitting'] ?? 'Hyperbolic',
      afStepSize: _parseInt(allSettings['af_step_size'], 50),
      afExposureTime: _parseDouble(allSettings['af_exposure_time'], 4.0),
      afInitialOffsetSteps:
          _parseInt(allSettings['af_initial_offset_steps'], 4),
      afNumberOfAttempts: _parseInt(allSettings['af_number_of_attempts'], 1),
      afUseBrightestNStars:
          _parseInt(allSettings['af_use_brightest_n_stars'], 0),
      afOuterCropRatio: _parseDouble(allSettings['af_outer_crop_ratio'], 1.0),
      afInnerCropRatio: _parseDouble(allSettings['af_inner_crop_ratio'], 0.0),
      afBinning: _parseInt(allSettings['af_binning'], 1),
      afRSquaredThreshold:
          _parseDouble(allSettings['af_r_squared_threshold'], 0.7),
      afDisableGuidingDuringAf:
          _parseBool(allSettings['af_disable_guiding'], false),
      afFocuserSettleTimeMs:
          _parseInt(allSettings['af_focuser_settle_time_ms'], 500),
      afExposuresPerPoint: _parseInt(allSettings['af_exposures_per_point'], 1),
      afBacklashCompMethod:
          allSettings['af_backlash_comp_method'] ?? 'Overshoot',
      afBacklashIn: _parseInt(allSettings['af_backlash_in'], 350),
      afBacklashOut: _parseInt(allSettings['af_backlash_out'], 0),
      afAutofocusFilterName: allSettings['af_autofocus_filter_name'] ?? '',
      afFilterSettingsJson: allSettings['af_filter_settings'] ?? '{}',
    );
  }

  bool _parseBool(String? value, bool defaultValue) {
    if (value == null) return defaultValue;
    return value.toLowerCase() == 'true';
  }

  double _parseDouble(String? value, double defaultValue) {
    if (value == null) return defaultValue;
    return double.tryParse(value) ?? defaultValue;
  }

  int _parseInt(String? value, int defaultValue) {
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  SafetyFailMode _parseSafetyFailMode(String? value) {
    if (value == null) return SafetyFailMode.failClosed;
    return switch (value) {
      'failOpen' => SafetyFailMode.failOpen,
      'failClosed' => SafetyFailMode.failClosed,
      'warnOnly' => SafetyFailMode.warnOnly,
      _ => SafetyFailMode.failClosed,
    };
  }

  Future<void> _saveSetting(String key, String value) async {
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final current = state.valueOrNull;
      if (current == null) {
        throw StateError('Settings are not loaded yet');
      }
      final updated = _applySettingsMap(current, {key: value});
      await _writeRemoteSettings(updated);
      return;
    }
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(key, value);
  }

  Future<void> _saveSettings(Map<String, String> settings) async {
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final current = state.valueOrNull;
      if (current == null) {
        throw StateError('Settings are not loaded yet');
      }
      final updated = _applySettingsMap(current, settings);
      await _writeRemoteSettings(updated);
      return;
    }
    final dao = ref.read(settingsDaoProvider);
    await dao.setSettings(settings);
  }

  AppSettingsState _applySettingsMap(
    AppSettingsState current,
    Map<String, String> settings,
  ) {
    return current.copyWith(
      startMinimized: settings.containsKey('start_minimized')
          ? _parseBool(settings['start_minimized'], current.startMinimized)
          : null,
      autoConnectEquipment: settings.containsKey('auto_connect_equipment')
          ? _parseBool(
              settings['auto_connect_equipment'],
              current.autoConnectEquipment,
            )
          : null,
      autoSaveSequences: settings.containsKey('auto_save_sequences')
          ? _parseBool(
              settings['auto_save_sequences'],
              current.autoSaveSequences,
            )
          : null,
      confirmBeforeClosing: settings.containsKey('confirm_before_closing')
          ? _parseBool(
              settings['confirm_before_closing'],
              current.confirmBeforeClosing,
            )
          : null,
      autoDiscoverOnLaunch: settings.containsKey('auto_discover_on_launch')
          ? _parseBool(
              settings['auto_discover_on_launch'],
              current.autoDiscoverOnLaunch,
            )
          : null,
      theme: settings['theme'],
      language: settings['language'],
      accentColor: settings['accent_color'],
      fontSize: settings['font_size'],
      sidebarCollapsed: settings.containsKey('sidebar_collapsed')
          ? _parseBool(settings['sidebar_collapsed'], current.sidebarCollapsed)
          : null,
      latitude: settings.containsKey('observer_latitude')
          ? _parseDouble(settings['observer_latitude'], current.latitude)
          : null,
      longitude: settings.containsKey('observer_longitude')
          ? _parseDouble(settings['observer_longitude'], current.longitude)
          : null,
      elevation: settings.containsKey('observer_elevation')
          ? _parseDouble(settings['observer_elevation'], current.elevation)
          : null,
      timezone: settings['timezone'],
      useSystemTime: settings.containsKey('use_system_time')
          ? _parseBool(settings['use_system_time'], current.useSystemTime)
          : null,
      imageFormat: settings['image_format'],
      fileNamingPattern: settings['file_naming_pattern'],
      bitDepth: settings['bit_depth'],
      parkOnUnsafeWeather: settings.containsKey('park_on_unsafe_weather')
          ? _parseBool(
              settings['park_on_unsafe_weather'],
              current.parkOnUnsafeWeather,
            )
          : null,
      parkBeforeDawn: settings.containsKey('park_before_dawn')
          ? _parseBool(settings['park_before_dawn'], current.parkBeforeDawn)
          : null,
      meridianFlipMinutes: settings.containsKey('meridian_flip_minutes')
          ? _parseInt(
              settings['meridian_flip_minutes'],
              current.meridianFlipMinutes,
            )
          : null,
      autoFocusOnFilterChange:
          settings.containsKey('auto_focus_on_filter_change')
              ? _parseBool(
                  settings['auto_focus_on_filter_change'],
                  current.autoFocusOnFilterChange,
                )
              : null,
      useFilterFocusOffsets: settings.containsKey('use_filter_focus_offsets')
          ? _parseBool(
              settings['use_filter_focus_offsets'],
              current.useFilterFocusOffsets,
            )
          : null,
      autoFocusEveryMinutes: settings.containsKey('auto_focus_every_minutes')
          ? _parseInt(
              settings['auto_focus_every_minutes'],
              current.autoFocusEveryMinutes,
            )
          : null,
      ditherEnabled: settings.containsKey('dither_enabled')
          ? _parseBool(settings['dither_enabled'], current.ditherEnabled)
          : null,
      ditherEveryFrames: settings.containsKey('dither_every_frames')
          ? _parseInt(
              settings['dither_every_frames'],
              current.ditherEveryFrames,
            )
          : null,
      safetyFailMode: settings.containsKey('safety_fail_mode')
          ? _parseSafetyFailMode(settings['safety_fail_mode'])
          : null,
      plateSolver: settings['plate_solver'],
      astapPath: settings['astap_path'],
      astrometryPath: settings['astrometry_path'],
      plateSolveTimeout: settings.containsKey('plate_solve_timeout')
          ? _parseInt(
              settings['plate_solve_timeout'],
              current.plateSolveTimeout,
            )
          : null,
      plateSolveSearchRadius: settings.containsKey('plate_solve_search_radius')
          ? _parseDouble(
              settings['plate_solve_search_radius'],
              current.plateSolveSearchRadius,
            )
          : null,
      blindSolve: settings.containsKey('blind_solve')
          ? _parseBool(settings['blind_solve'], current.blindSolve)
          : null,
      phd2Path: settings['phd2_path'],
      phd2Host: settings['phd2_host'],
      phd2Port: settings.containsKey('phd2_port')
          ? _parseInt(settings['phd2_port'], current.phd2Port)
          : null,
      notificationsEnabled: settings.containsKey('notifications_enabled')
          ? _parseBool(
              settings['notifications_enabled'],
              current.notificationsEnabled,
            )
          : null,
      discordWebhook: settings['discord_webhook'],
      pushoverKey: settings['pushover_key'],
      pushoverUser: settings['pushover_user'],
      notifyOnSequenceComplete:
          settings.containsKey('notify_on_sequence_complete')
              ? _parseBool(
                  settings['notify_on_sequence_complete'],
                  current.notifyOnSequenceComplete,
                )
              : null,
      notifyOnError: settings.containsKey('notify_on_error')
          ? _parseBool(settings['notify_on_error'], current.notifyOnError)
          : null,
      notifyOnMeridianFlip: settings.containsKey('notify_on_meridian_flip')
          ? _parseBool(
              settings['notify_on_meridian_flip'],
              current.notifyOnMeridianFlip,
            )
          : null,
      soundEnabled: settings.containsKey('sound_enabled')
          ? _parseBool(settings['sound_enabled'], current.soundEnabled)
          : null,
      imageOutputPath: settings['image_output_path'],
      sequencesPath: settings['sequences_path'],
      databasePath: settings['database_path'],
      logsPath: settings['logs_path'],
      indiServerHost: settings['indi_server_host'],
      indiServerPort: settings.containsKey('indi_server_port')
          ? _parseInt(settings['indi_server_port'], current.indiServerPort)
          : null,
      indiAutoConnect: settings.containsKey('indi_auto_connect')
          ? _parseBool(settings['indi_auto_connect'], current.indiAutoConnect)
          : null,
      alpacaServerHost: settings['alpaca_server_host'],
      alpacaServerPort: settings.containsKey('alpaca_server_port')
          ? _parseInt(settings['alpaca_server_port'], current.alpacaServerPort)
          : null,
      alpacaAutoDiscover: settings.containsKey('alpaca_auto_discover')
          ? _parseBool(
              settings['alpaca_auto_discover'],
              current.alpacaAutoDiscover,
            )
          : null,
      useNativeExecution: settings.containsKey('use_native_execution')
          ? _parseBool(
              settings['use_native_execution'],
              current.useNativeExecution,
            )
          : null,
      useSimulationMode: settings.containsKey('use_simulation_mode')
          ? _parseBool(
              settings['use_simulation_mode'],
              current.useSimulationMode,
            )
          : null,
      webServerEnabled: settings.containsKey('web_server_enabled')
          ? _parseBool(settings['web_server_enabled'], current.webServerEnabled)
          : null,
      webServerPort: settings.containsKey('web_server_port')
          ? _parseInt(settings['web_server_port'], current.webServerPort)
          : null,
      coolingBehavior: settings['cooling_behavior'],
      defaultGain: settings.containsKey('default_gain')
          ? _parseInt(settings['default_gain'], current.defaultGain)
          : null,
      defaultOffset: settings.containsKey('default_offset')
          ? _parseInt(settings['default_offset'], current.defaultOffset)
          : null,
      enableMeridianFlip: settings.containsKey('enable_meridian_flip')
          ? _parseBool(
              settings['enable_meridian_flip'],
              current.enableMeridianFlip,
            )
          : null,
      tempCompensation: settings.containsKey('temp_compensation')
          ? _parseBool(
              settings['temp_compensation'],
              current.tempCompensation,
            )
          : null,
      tempCoefficient: settings.containsKey('temp_coefficient')
          ? _parseDouble(
              settings['temp_coefficient'],
              current.tempCoefficient,
            )
          : null,
      backlashCompensation: settings.containsKey('backlash_compensation')
          ? _parseInt(
              settings['backlash_compensation'],
              current.backlashCompensation,
            )
          : null,
      ditherScale: settings['dither_scale'],
      settleThreshold: settings.containsKey('settle_threshold')
          ? _parseDouble(settings['settle_threshold'], current.settleThreshold)
          : null,
      settleTimeout: settings.containsKey('settle_timeout')
          ? _parseInt(settings['settle_timeout'], current.settleTimeout)
          : null,
      bortleClass: settings.containsKey('bortle_class')
          ? _parseInt(settings['bortle_class'], current.bortleClass)
          : null,
      horizonProfileJson: settings['horizon_profile_json'],
      afMethod: settings['af_method'],
      afCurveFitting: settings['af_curve_fitting'],
      afStepSize: settings.containsKey('af_step_size')
          ? _parseInt(settings['af_step_size'], current.afStepSize)
          : null,
      afExposureTime: settings.containsKey('af_exposure_time')
          ? _parseDouble(settings['af_exposure_time'], current.afExposureTime)
          : null,
      afInitialOffsetSteps: settings.containsKey('af_initial_offset_steps')
          ? _parseInt(
              settings['af_initial_offset_steps'],
              current.afInitialOffsetSteps,
            )
          : null,
      afNumberOfAttempts: settings.containsKey('af_number_of_attempts')
          ? _parseInt(
              settings['af_number_of_attempts'],
              current.afNumberOfAttempts,
            )
          : null,
      afUseBrightestNStars: settings.containsKey('af_use_brightest_n_stars')
          ? _parseInt(
              settings['af_use_brightest_n_stars'],
              current.afUseBrightestNStars,
            )
          : null,
      afOuterCropRatio: settings.containsKey('af_outer_crop_ratio')
          ? _parseDouble(
              settings['af_outer_crop_ratio'],
              current.afOuterCropRatio,
            )
          : null,
      afInnerCropRatio: settings.containsKey('af_inner_crop_ratio')
          ? _parseDouble(
              settings['af_inner_crop_ratio'],
              current.afInnerCropRatio,
            )
          : null,
      afBinning: settings.containsKey('af_binning')
          ? _parseInt(settings['af_binning'], current.afBinning)
          : null,
      afRSquaredThreshold: settings.containsKey('af_r_squared_threshold')
          ? _parseDouble(
              settings['af_r_squared_threshold'],
              current.afRSquaredThreshold,
            )
          : null,
      afDisableGuidingDuringAf:
          settings.containsKey('af_disable_guiding_during_af')
              ? _parseBool(
                  settings['af_disable_guiding_during_af'],
                  current.afDisableGuidingDuringAf,
                )
              : null,
      afFocuserSettleTimeMs: settings.containsKey('af_focuser_settle_time_ms')
          ? _parseInt(
              settings['af_focuser_settle_time_ms'],
              current.afFocuserSettleTimeMs,
            )
          : null,
      afExposuresPerPoint: settings.containsKey('af_exposures_per_point')
          ? _parseInt(
              settings['af_exposures_per_point'],
              current.afExposuresPerPoint,
            )
          : null,
      afBacklashCompMethod: settings['af_backlash_comp_method'],
      afBacklashIn: settings.containsKey('af_backlash_in')
          ? _parseInt(settings['af_backlash_in'], current.afBacklashIn)
          : null,
      afBacklashOut: settings.containsKey('af_backlash_out')
          ? _parseInt(settings['af_backlash_out'], current.afBacklashOut)
          : null,
      afAutofocusFilterName: settings['af_autofocus_filter_name'],
      afFilterSettingsJson: settings['af_filter_settings'],
    );
  }

  /// Helper to update a single field in the current AppSettingsState.
  ///
  /// If the state hasn't loaded yet (no value), the update is silently skipped
  /// because there's nothing to patch. The database write has already succeeded,
  /// so the next full load will pick up the new value.
  void _patchState(
      AppSettingsState Function(AppSettingsState current) updater) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(updater(current));
  }

  // ========== General Settings ==========

  Future<void> setStartMinimized(bool value) async {
    await _saveSetting('start_minimized', value.toString());
    _patchState((s) => s.copyWith(startMinimized: value));
  }

  Future<void> setAutoConnectEquipment(bool value) async {
    await _saveSetting('auto_connect_equipment', value.toString());
    _patchState((s) => s.copyWith(autoConnectEquipment: value));
  }

  Future<void> setAutoSaveSequences(bool value) async {
    await _saveSetting('auto_save_sequences', value.toString());
    _patchState((s) => s.copyWith(autoSaveSequences: value));
  }

  Future<void> setConfirmBeforeClosing(bool value) async {
    await _saveSetting('confirm_before_closing', value.toString());
    _patchState((s) => s.copyWith(confirmBeforeClosing: value));
  }

  Future<void> setAutoDiscoverOnLaunch(bool value) async {
    await _saveSetting('auto_discover_on_launch', value.toString());
    _patchState((s) => s.copyWith(autoDiscoverOnLaunch: value));
  }

  // ========== Development Settings ==========

  // ========== Appearance Settings ==========

  Future<void> setTheme(String value) async {
    await _saveSetting('theme', value);
    _patchState((s) => s.copyWith(theme: value));
  }

  Future<void> setLanguage(String value) async {
    await _saveSetting('language', value);
    _patchState((s) => s.copyWith(language: value));
  }

  Future<void> setAccentColor(String value) async {
    await _saveSetting('accent_color', value);
    _patchState((s) => s.copyWith(accentColor: value));
  }

  Future<void> setFontSize(String value) async {
    await _saveSetting('font_size', value);
    _patchState((s) => s.copyWith(fontSize: value));
  }

  Future<void> setUiScale(String value) async {
    await _saveSetting('ui_scale', value);
    _patchState((s) => s.copyWith(uiScale: value));
  }

  Future<void> setSidebarCollapsed(bool value) async {
    await _saveSetting('sidebar_collapsed', value.toString());
    _patchState((s) => s.copyWith(sidebarCollapsed: value));
  }

  // ========== Location Settings ==========

  Future<void> setLatitude(double value) async {
    await _saveSetting('observer_latitude', value.toString());
    _patchState((s) => s.copyWith(latitude: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setLongitude(double value) async {
    await _saveSetting('observer_longitude', value.toString());
    _patchState((s) => s.copyWith(longitude: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setElevation(double value) async {
    await _saveSetting('observer_elevation', value.toString());
    _patchState((s) => s.copyWith(elevation: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setTimezone(String value) async {
    await _saveSetting('timezone', value);
    _patchState((s) => s.copyWith(timezone: value));
  }

  Future<void> setUseSystemTime(bool value) async {
    await _saveSetting('use_system_time', value.toString());
    _patchState((s) => s.copyWith(useSystemTime: value));
  }

  Future<void> updateLocation({
    double? latitude,
    double? longitude,
    double? elevation,
  }) async {
    final settings = <String, String>{};
    if (latitude != null) settings['observer_latitude'] = latitude.toString();
    if (longitude != null)
      settings['observer_longitude'] = longitude.toString();
    if (elevation != null)
      settings['observer_elevation'] = elevation.toString();

    if (settings.isNotEmpty) {
      await _saveSettings(settings);
      _patchState((s) => s.copyWith(
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
          ));
    }
  }

  // ========== Observing Environment Settings ==========

  Future<void> setBortleClass(int value) async {
    final clamped = value.clamp(1, 9);
    await _saveSetting('bortle_class', clamped.toString());
    _patchState((s) => s.copyWith(bortleClass: clamped));
  }

  Future<void> setHorizonProfileJson(String value) async {
    await _saveSetting('horizon_profile_json', value);
    _patchState((s) => s.copyWith(horizonProfileJson: value));
  }

  // ========== Imaging Settings ==========

  Future<void> setImageFormat(String value) async {
    await _saveSetting('image_format', value);
    _patchState((s) => s.copyWith(imageFormat: value));
  }

  Future<void> setFileNamingPattern(String value) async {
    await _saveSetting('file_naming_pattern', value);
    _patchState((s) => s.copyWith(fileNamingPattern: value));
  }

  Future<void> setBitDepth(String value) async {
    await _saveSetting('bit_depth', value);
    _patchState((s) => s.copyWith(bitDepth: value));
  }

  // ========== Sequencer Settings ==========

  Future<void> setParkOnUnsafeWeather(bool value) async {
    await _saveSetting('park_on_unsafe_weather', value.toString());
    _patchState((s) => s.copyWith(parkOnUnsafeWeather: value));
  }

  Future<void> setParkBeforeDawn(bool value) async {
    await _saveSetting('park_before_dawn', value.toString());
    _patchState((s) => s.copyWith(parkBeforeDawn: value));
  }

  Future<void> setSafetyFailMode(SafetyFailMode value) async {
    await _saveSetting('safety_fail_mode', value.name);
    _patchState((s) => s.copyWith(safetyFailMode: value));
  }

  Future<void> setMeridianFlipMinutes(int value) async {
    await _saveSetting('meridian_flip_minutes', value.toString());
    _patchState((s) => s.copyWith(meridianFlipMinutes: value));
  }

  Future<void> setAutoFocusOnFilterChange(bool value) async {
    await _saveSetting('auto_focus_on_filter_change', value.toString());
    _patchState((s) => s.copyWith(autoFocusOnFilterChange: value));
  }

  Future<void> setUseFilterFocusOffsets(bool value) async {
    await _saveSetting('use_filter_focus_offsets', value.toString());
    _patchState((s) => s.copyWith(useFilterFocusOffsets: value));
  }

  Future<void> setAutoFocusEveryMinutes(int value) async {
    await _saveSetting('auto_focus_every_minutes', value.toString());
    _patchState((s) => s.copyWith(autoFocusEveryMinutes: value));
  }

  Future<void> setDitherEnabled(bool value) async {
    await _saveSetting('dither_enabled', value.toString());
    _patchState((s) => s.copyWith(ditherEnabled: value));
  }

  Future<void> setDitherEveryFrames(int value) async {
    await _saveSetting('dither_every_frames', value.toString());
    _patchState((s) => s.copyWith(ditherEveryFrames: value));
  }

  Future<void> setUseNativeExecution(bool value) async {
    await _saveSetting('use_native_execution', value.toString());
    _patchState((s) => s.copyWith(useNativeExecution: value));
  }

  Future<void> setUseSimulationMode(bool value) async {
    await _saveSetting('use_simulation_mode', value.toString());
    _patchState((s) => s.copyWith(useSimulationMode: value));
  }

  // ========== Remote Access / Web Server Settings ==========

  Future<void> setWebServerEnabled(bool value) async {
    await _saveSetting('web_server_enabled', value.toString());
    _patchState((s) => s.copyWith(webServerEnabled: value));
  }

  Future<void> setWebServerPort(int value) async {
    await _saveSetting('web_server_port', value.toString());
    _patchState((s) => s.copyWith(webServerPort: value));
  }

  // ========== Plate Solving Settings ==========

  Future<void> setPlateSolver(String value) async {
    await _saveSetting('plate_solver', value);
    _patchState((s) => s.copyWith(plateSolver: value));
  }

  Future<void> setAstapPath(String value) async {
    await _saveSetting('astap_path', value);
    _patchState((s) => s.copyWith(astapPath: value));
  }

  Future<void> setAstrometryPath(String value) async {
    await _saveSetting('astrometry_path', value);
    _patchState((s) => s.copyWith(astrometryPath: value));
  }

  Future<void> setPlateSolveTimeout(int value) async {
    await _saveSetting('plate_solve_timeout', value.toString());
    _patchState((s) => s.copyWith(plateSolveTimeout: value));
  }

  Future<void> setPlateSolveSearchRadius(double value) async {
    await _saveSetting('plate_solve_search_radius', value.toString());
    _patchState((s) => s.copyWith(plateSolveSearchRadius: value));
  }

  Future<void> setBlindSolve(bool value) async {
    await _saveSetting('blind_solve', value.toString());
    _patchState((s) => s.copyWith(blindSolve: value));
  }

  // ========== PHD2 Guiding Settings ==========

  Future<void> setPhd2Path(String value) async {
    await _saveSetting('phd2_path', value);
    _patchState((s) => s.copyWith(phd2Path: value));
  }

  Future<void> setPhd2Host(String value) async {
    await _saveSetting('phd2_host', value);
    _patchState((s) => s.copyWith(phd2Host: value));
  }

  Future<void> setPhd2Port(int value) async {
    await _saveSetting('phd2_port', value.toString());
    _patchState((s) => s.copyWith(phd2Port: value));
  }

  // ========== Notification Settings ==========

  Future<void> setNotificationsEnabled(bool value) async {
    await _saveSetting('notifications_enabled', value.toString());
    _patchState((s) => s.copyWith(notificationsEnabled: value));
  }

  Future<void> setDiscordWebhook(String value) async {
    await _saveSetting('discord_webhook', value);
    _patchState((s) => s.copyWith(discordWebhook: value));
  }

  Future<void> setPushoverKey(String value) async {
    await _saveSetting('pushover_key', value);
    _patchState((s) => s.copyWith(pushoverKey: value));
  }

  Future<void> setPushoverUser(String value) async {
    await _saveSetting('pushover_user', value);
    _patchState((s) => s.copyWith(pushoverUser: value));
  }

  Future<void> setNotifyOnSequenceComplete(bool value) async {
    await _saveSetting('notify_on_sequence_complete', value.toString());
    _patchState((s) => s.copyWith(notifyOnSequenceComplete: value));
  }

  Future<void> setNotifyOnError(bool value) async {
    await _saveSetting('notify_on_error', value.toString());
    _patchState((s) => s.copyWith(notifyOnError: value));
  }

  Future<void> setNotifyOnMeridianFlip(bool value) async {
    await _saveSetting('notify_on_meridian_flip', value.toString());
    _patchState((s) => s.copyWith(notifyOnMeridianFlip: value));
  }

  Future<void> setSoundEnabled(bool value) async {
    await _saveSetting('sound_enabled', value.toString());
    _patchState((s) => s.copyWith(soundEnabled: value));
  }

  // ========== File Path Settings ==========

  Future<void> setImageOutputPath(String value) async {
    await _saveSetting('image_output_path', value);
    _patchState((s) => s.copyWith(imageOutputPath: value));
  }

  Future<void> setSequencesPath(String value) async {
    await _saveSetting('sequences_path', value);
    _patchState((s) => s.copyWith(sequencesPath: value));
  }

  Future<void> setDatabasePath(String value) async {
    await _saveSetting('database_path', value);
    _patchState((s) => s.copyWith(databasePath: value));
  }

  Future<void> setLogsPath(String value) async {
    await _saveSetting('logs_path', value);
    _patchState((s) => s.copyWith(logsPath: value));
  }

  // ========== Network/Protocol Settings ==========

  Future<void> setIndiServerHost(String value) async {
    await _saveSetting('indi_server_host', value);
    _patchState((s) => s.copyWith(indiServerHost: value));
  }

  Future<void> setIndiServerPort(int value) async {
    await _saveSetting('indi_server_port', value.toString());
    _patchState((s) => s.copyWith(indiServerPort: value));
  }

  Future<void> setIndiAutoConnect(bool value) async {
    await _saveSetting('indi_auto_connect', value.toString());
    _patchState((s) => s.copyWith(indiAutoConnect: value));
  }

  Future<void> setAlpacaServerHost(String value) async {
    await _saveSetting('alpaca_server_host', value);
    _patchState((s) => s.copyWith(alpacaServerHost: value));
  }

  Future<void> setAlpacaServerPort(int value) async {
    await _saveSetting('alpaca_server_port', value.toString());
    _patchState((s) => s.copyWith(alpacaServerPort: value));
  }

  Future<void> setAlpacaAutoDiscover(bool value) async {
    await _saveSetting('alpaca_auto_discover', value.toString());
    _patchState((s) => s.copyWith(alpacaAutoDiscover: value));
  }

  // Equipment Settings - Camera
  Future<void> setCoolingBehavior(String value) async {
    await _saveSetting('cooling_behavior', value);
    _patchState((s) => s.copyWith(coolingBehavior: value));
  }

  Future<void> setDefaultGain(int value) async {
    await _saveSetting('default_gain', value.toString());
    _patchState((s) => s.copyWith(defaultGain: value));
  }

  Future<void> setDefaultOffset(int value) async {
    await _saveSetting('default_offset', value.toString());
    _patchState((s) => s.copyWith(defaultOffset: value));
  }

  // Equipment Settings - Mount
  Future<void> setEnableMeridianFlip(bool value) async {
    await _saveSetting('enable_meridian_flip', value.toString());
    _patchState((s) => s.copyWith(enableMeridianFlip: value));
  }

  // Equipment Settings - Focuser
  Future<void> setTempCompensation(bool value) async {
    await _saveSetting('temp_compensation', value.toString());
    _patchState((s) => s.copyWith(tempCompensation: value));
  }

  Future<void> setTempCoefficient(double value) async {
    await _saveSetting('temp_coefficient', value.toString());
    _patchState((s) => s.copyWith(tempCoefficient: value));
  }

  Future<void> setBacklashCompensation(int value) async {
    await _saveSetting('backlash_compensation', value.toString());
    _patchState((s) => s.copyWith(backlashCompensation: value));
  }

  // Equipment Settings - Guider
  Future<void> setDitherScale(String value) async {
    await _saveSetting('dither_scale', value);
    _patchState((s) => s.copyWith(ditherScale: value));
  }

  Future<void> setSettleThreshold(double value) async {
    await _saveSetting('settle_threshold', value.toString());
    _patchState((s) => s.copyWith(settleThreshold: value));
  }

  Future<void> setSettleTimeout(int value) async {
    await _saveSetting('settle_timeout', value.toString());
    _patchState((s) => s.copyWith(settleTimeout: value));
  }

  // ========== Autofocus Settings ==========

  Future<void> setAfMethod(String value) async {
    await _saveSetting('af_method', value);
    _patchState((s) => s.copyWith(afMethod: value));
  }

  Future<void> setAfCurveFitting(String value) async {
    await _saveSetting('af_curve_fitting', value);
    _patchState((s) => s.copyWith(afCurveFitting: value));
  }

  Future<void> setAfStepSize(int value) async {
    await _saveSetting('af_step_size', value.toString());
    _patchState((s) => s.copyWith(afStepSize: value));
  }

  Future<void> setAfExposureTime(double value) async {
    await _saveSetting('af_exposure_time', value.toString());
    _patchState((s) => s.copyWith(afExposureTime: value));
  }

  Future<void> setAfInitialOffsetSteps(int value) async {
    await _saveSetting('af_initial_offset_steps', value.toString());
    _patchState((s) => s.copyWith(afInitialOffsetSteps: value));
  }

  Future<void> setAfNumberOfAttempts(int value) async {
    await _saveSetting('af_number_of_attempts', value.toString());
    _patchState((s) => s.copyWith(afNumberOfAttempts: value));
  }

  Future<void> setAfUseBrightestNStars(int value) async {
    await _saveSetting('af_use_brightest_n_stars', value.toString());
    _patchState((s) => s.copyWith(afUseBrightestNStars: value));
  }

  Future<void> setAfOuterCropRatio(double value) async {
    await _saveSetting('af_outer_crop_ratio', value.toString());
    _patchState((s) => s.copyWith(afOuterCropRatio: value));
  }

  Future<void> setAfInnerCropRatio(double value) async {
    await _saveSetting('af_inner_crop_ratio', value.toString());
    _patchState((s) => s.copyWith(afInnerCropRatio: value));
  }

  Future<void> setAfBinning(int value) async {
    await _saveSetting('af_binning', value.toString());
    _patchState((s) => s.copyWith(afBinning: value));
  }

  Future<void> setAfRSquaredThreshold(double value) async {
    await _saveSetting('af_r_squared_threshold', value.toString());
    _patchState((s) => s.copyWith(afRSquaredThreshold: value));
  }

  Future<void> setAfDisableGuidingDuringAf(bool value) async {
    await _saveSetting('af_disable_guiding', value.toString());
    _patchState((s) => s.copyWith(afDisableGuidingDuringAf: value));
  }

  Future<void> setAfFocuserSettleTimeMs(int value) async {
    await _saveSetting('af_focuser_settle_time_ms', value.toString());
    _patchState((s) => s.copyWith(afFocuserSettleTimeMs: value));
  }

  Future<void> setAfExposuresPerPoint(int value) async {
    await _saveSetting('af_exposures_per_point', value.toString());
    _patchState((s) => s.copyWith(afExposuresPerPoint: value));
  }

  Future<void> setAfBacklashCompMethod(String value) async {
    await _saveSetting('af_backlash_comp_method', value);
    _patchState((s) => s.copyWith(afBacklashCompMethod: value));
  }

  Future<void> setAfBacklashIn(int value) async {
    await _saveSetting('af_backlash_in', value.toString());
    _patchState((s) => s.copyWith(afBacklashIn: value));
  }

  Future<void> setAfBacklashOut(int value) async {
    await _saveSetting('af_backlash_out', value.toString());
    _patchState((s) => s.copyWith(afBacklashOut: value));
  }

  Future<void> setAfAutofocusFilterName(String value) async {
    await _saveSetting('af_autofocus_filter_name', value);
    _patchState((s) => s.copyWith(afAutofocusFilterName: value));
  }

  Future<void> setAfFilterSettingsJson(String value) async {
    await _saveSetting('af_filter_settings', value);
    _patchState((s) => s.copyWith(afFilterSettingsJson: value));
  }

  /// Update a single filter's autofocus configuration.
  ///
  /// Loads the current filter settings map, updates the entry for [filterName],
  /// serializes back to JSON, and persists to the database.
  Future<void> setFilterAutofocusConfig(
      String filterName, FilterAutofocusConfig config) async {
    final currentJson = state.value?.afFilterSettingsJson ?? '{}';
    final map = AutofocusSettings.parseFilterSettingsJson(currentJson);
    map[filterName] = config;
    final newJson = AutofocusSettings.encodeFilterSettingsJson(map);
    await setAfFilterSettingsJson(newJson);
  }

  /// Remove a filter's autofocus configuration.
  Future<void> removeFilterAutofocusConfig(String filterName) async {
    final currentJson = state.value?.afFilterSettingsJson ?? '{}';
    final map = AutofocusSettings.parseFilterSettingsJson(currentJson);
    map.remove(filterName);
    final newJson = AutofocusSettings.encodeFilterSettingsJson(map);
    await setAfFilterSettingsJson(newJson);
  }
}

/// Main app settings provider
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettingsState>(() {
  return AppSettingsNotifier();
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
        settings.afFilterSettingsJson),
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

/// Location settings notifier that persists to database
class LocationSettingsNotifier extends AsyncNotifier<LocationSettings> {
  @override
  Future<LocationSettings> build() async {
    final dao = ref.read(settingsDaoProvider);
    final lat = await dao.getObserverLatitude();
    final lon = await dao.getObserverLongitude();
    final elev = await dao.getObserverElevation();

    return LocationSettings(
      latitude: lat,
      longitude: lon,
      elevation: elev,
    );
  }

  Future<void> updateLocation({
    double? latitude,
    double? longitude,
    double? elevation,
  }) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? const LocationSettings();

    if (latitude != null) {
      await dao.setObserverLatitude(latitude);
    }
    if (longitude != null) {
      await dao.setObserverLongitude(longitude);
    }
    if (elevation != null) {
      await dao.setObserverElevation(elevation);
    }

    state = AsyncData(current.copyWith(
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
    ));
  }
}

final locationSettingsProvider =
    AsyncNotifierProvider<LocationSettingsNotifier, LocationSettings>(() {
  return LocationSettingsNotifier();
});

// ============================================================================
// Output Settings
// ============================================================================

/// Imaging output settings
class OutputSettings {
  final String format; // FITS, XISF, TIFF
  final String bitDepth; // 16-bit, 32-bit
  final String savePath;
  final String filePattern;
  final bool includeTimestamp;
  final bool includeFilter;

  const OutputSettings({
    this.format = 'FITS',
    this.bitDepth = '16-bit',
    this.savePath = '',
    this.filePattern = r'$DATE_$TARGET_$FILTER_$EXPOSURE_###',
    this.includeTimestamp = true,
    this.includeFilter = true,
  });

  OutputSettings copyWith({
    String? format,
    String? bitDepth,
    String? savePath,
    String? filePattern,
    bool? includeTimestamp,
    bool? includeFilter,
  }) {
    return OutputSettings(
      format: format ?? this.format,
      bitDepth: bitDepth ?? this.bitDepth,
      savePath: savePath ?? this.savePath,
      filePattern: filePattern ?? this.filePattern,
      includeTimestamp: includeTimestamp ?? this.includeTimestamp,
      includeFilter: includeFilter ?? this.includeFilter,
    );
  }
}

/// Output settings notifier that persists to database
class OutputSettingsNotifier extends AsyncNotifier<OutputSettings> {
  @override
  Future<OutputSettings> build() async {
    final dao = ref.read(settingsDaoProvider);

    final format = await dao.getSetting('output_format') ?? 'FITS';
    final bitDepth = await dao.getSetting('output_bit_depth') ?? '16-bit';
    final savePath = await dao.getSetting('default_image_directory') ?? '';
    final filePattern = await dao.getSetting('file_pattern') ??
        r'$DATE_$TARGET_$FILTER_$EXPOSURE_###';
    final includeTimestamp =
        (await dao.getSetting('include_timestamp') ?? 'true') == 'true';
    final includeFilter =
        (await dao.getSetting('include_filter') ?? 'true') == 'true';

    return OutputSettings(
      format: format,
      bitDepth: bitDepth,
      savePath: savePath,
      filePattern: filePattern,
      includeTimestamp: includeTimestamp,
      includeFilter: includeFilter,
    );
  }

  Future<void> updateOutput({
    String? format,
    String? bitDepth,
    String? savePath,
    String? filePattern,
    bool? includeTimestamp,
    bool? includeFilter,
  }) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? const OutputSettings();

    final settings = <String, String>{};
    if (format != null) settings['output_format'] = format;
    if (bitDepth != null) settings['output_bit_depth'] = bitDepth;
    if (savePath != null) settings['default_image_directory'] = savePath;
    if (filePattern != null) settings['file_pattern'] = filePattern;
    if (includeTimestamp != null)
      settings['include_timestamp'] = includeTimestamp.toString();
    if (includeFilter != null)
      settings['include_filter'] = includeFilter.toString();

    if (settings.isNotEmpty) {
      await dao.setSettings(settings);
    }

    state = AsyncData(current.copyWith(
      format: format,
      bitDepth: bitDepth,
      savePath: savePath,
      filePattern: filePattern,
      includeTimestamp: includeTimestamp,
      includeFilter: includeFilter,
    ));
  }
}

final outputSettingsProvider =
    AsyncNotifierProvider<OutputSettingsNotifier, OutputSettings>(() {
  return OutputSettingsNotifier();
});

// ============================================================================
// Plate Solve Settings
// ============================================================================

/// Plate solving settings
class PlateSolveSettings {
  final String solver; // ASTAP, Astrometry.net, PlateSolve2
  final String solverPath;
  final int timeoutSeconds;
  final bool autoSolve;
  final double searchRadius;

  const PlateSolveSettings({
    this.solver = 'ASTAP',
    this.solverPath = '',
    this.timeoutSeconds = 60,
    this.autoSolve = true,
    this.searchRadius = 30.0,
  });

  PlateSolveSettings copyWith({
    String? solver,
    String? solverPath,
    int? timeoutSeconds,
    bool? autoSolve,
    double? searchRadius,
  }) {
    return PlateSolveSettings(
      solver: solver ?? this.solver,
      solverPath: solverPath ?? this.solverPath,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      autoSolve: autoSolve ?? this.autoSolve,
      searchRadius: searchRadius ?? this.searchRadius,
    );
  }
}

/// Plate solve settings notifier that persists to database
class PlateSolveSettingsNotifier extends AsyncNotifier<PlateSolveSettings> {
  @override
  Future<PlateSolveSettings> build() async {
    final dao = ref.read(settingsDaoProvider);

    final solver = await dao.getSetting('plate_solve_solver') ?? 'ASTAP';
    final solverPath = await dao.getSetting('plate_solve_path') ?? '';
    final timeoutStr = await dao.getSetting('plate_solve_timeout') ?? '60';
    final autoSolve =
        (await dao.getSetting('plate_solve_auto') ?? 'true') == 'true';
    final searchRadiusStr =
        await dao.getSetting('plate_solve_radius') ?? '30.0';

    return PlateSolveSettings(
      solver: solver,
      solverPath: solverPath,
      timeoutSeconds: int.tryParse(timeoutStr) ?? 60,
      autoSolve: autoSolve,
      searchRadius: double.tryParse(searchRadiusStr) ?? 30.0,
    );
  }

  Future<void> updatePlateSolve({
    String? solver,
    String? solverPath,
    int? timeoutSeconds,
    bool? autoSolve,
    double? searchRadius,
  }) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? const PlateSolveSettings();

    final settings = <String, String>{};
    if (solver != null) settings['plate_solve_solver'] = solver;
    if (solverPath != null) settings['plate_solve_path'] = solverPath;
    if (timeoutSeconds != null)
      settings['plate_solve_timeout'] = timeoutSeconds.toString();
    if (autoSolve != null) settings['plate_solve_auto'] = autoSolve.toString();
    if (searchRadius != null)
      settings['plate_solve_radius'] = searchRadius.toString();

    if (settings.isNotEmpty) {
      await dao.setSettings(settings);
    }

    state = AsyncData(current.copyWith(
      solver: solver,
      solverPath: solverPath,
      timeoutSeconds: timeoutSeconds,
      autoSolve: autoSolve,
      searchRadius: searchRadius,
    ));
  }
}

final plateSolveSettingsProvider =
    AsyncNotifierProvider<PlateSolveSettingsNotifier, PlateSolveSettings>(() {
  return PlateSolveSettingsNotifier();
});

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
  'NW'
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
  315.0
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
    final segmentSize = 360.0 / 8.0; // 45 degrees per segment
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
    if (trimmed.endsWith('}'))
      trimmed = trimmed.substring(0, trimmed.length - 1);
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
}

/// Focused provider for Bortle class.
final bortleClassProvider = Provider<int>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  return settingsAsync.valueOrNull?.bortleClass ?? 5;
});

/// Focused provider for parsed horizon profile.
final horizonProfileProvider = Provider<HorizonProfile>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  final json = settingsAsync.valueOrNull?.horizonProfileJson ??
      '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}';
  return HorizonProfile.fromJson(json);
});

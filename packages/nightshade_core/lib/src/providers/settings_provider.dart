import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_provider.dart';
import '../models/settings/app_settings.dart' show SafetyFailMode;

// ============================================================================
// App Settings - Complete settings model
// ============================================================================

/// Complete application settings
class AppSettings {
  // General
  final bool startMinimized;
  final bool autoConnectEquipment;
  final bool autoSaveSequences;
  final bool confirmBeforeClosing;
  final bool autoDiscoverOnLaunch;
  
  // Appearance
  final String theme; // 'dark' or 'light'
  final String accentColor; // hex color
  final String fontSize; // 'Small', 'Medium', 'Large'
  final String uiScale; // 'Auto', 'Small (0.8x)', 'Normal (1.0x)', 'Large (1.2x)', 'Extra Large (1.4x)'
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
  final SafetyFailMode safetyFailMode; // How to behave when safety data unavailable
  
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

  const AppSettings({
    // General
    this.startMinimized = false,
    this.autoConnectEquipment = true,
    this.autoSaveSequences = true,
    this.confirmBeforeClosing = true,
    this.autoDiscoverOnLaunch = true,
    
    // Appearance
    this.theme = 'dark',
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
    this.safetyFailMode = SafetyFailMode.failOpen,

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
  });

  AppSettings copyWith({
    bool? startMinimized,
    bool? autoConnectEquipment,
    bool? autoSaveSequences,
    bool? confirmBeforeClosing,
    bool? autoDiscoverOnLaunch,
    String? theme,
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
  }) {
    return AppSettings(
      startMinimized: startMinimized ?? this.startMinimized,
      autoConnectEquipment: autoConnectEquipment ?? this.autoConnectEquipment,
      autoSaveSequences: autoSaveSequences ?? this.autoSaveSequences,
      confirmBeforeClosing: confirmBeforeClosing ?? this.confirmBeforeClosing,
      autoDiscoverOnLaunch: autoDiscoverOnLaunch ?? this.autoDiscoverOnLaunch,
      theme: theme ?? this.theme,
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
      autoFocusOnFilterChange: autoFocusOnFilterChange ?? this.autoFocusOnFilterChange,
      useFilterFocusOffsets: useFilterFocusOffsets ?? this.useFilterFocusOffsets,
      autoFocusEveryMinutes: autoFocusEveryMinutes ?? this.autoFocusEveryMinutes,
      ditherEnabled: ditherEnabled ?? this.ditherEnabled,
      ditherEveryFrames: ditherEveryFrames ?? this.ditherEveryFrames,
      safetyFailMode: safetyFailMode ?? this.safetyFailMode,
      plateSolver: plateSolver ?? this.plateSolver,
      astapPath: astapPath ?? this.astapPath,
      astrometryPath: astrometryPath ?? this.astrometryPath,
      plateSolveTimeout: plateSolveTimeout ?? this.plateSolveTimeout,
      plateSolveSearchRadius: plateSolveSearchRadius ?? this.plateSolveSearchRadius,
      blindSolve: blindSolve ?? this.blindSolve,
      phd2Path: phd2Path ?? this.phd2Path,
      phd2Host: phd2Host ?? this.phd2Host,
      phd2Port: phd2Port ?? this.phd2Port,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      discordWebhook: discordWebhook ?? this.discordWebhook,
      pushoverKey: pushoverKey ?? this.pushoverKey,
      pushoverUser: pushoverUser ?? this.pushoverUser,
      notifyOnSequenceComplete: notifyOnSequenceComplete ?? this.notifyOnSequenceComplete,
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
    );
  }
}

/// Main app settings notifier that persists all settings to database
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final dao = ref.read(settingsDaoProvider);
    final allSettings = await dao.getAllSettings();
    
    return AppSettings(
      // General
      startMinimized: _parseBool(allSettings['start_minimized'], false),
      autoConnectEquipment: _parseBool(allSettings['auto_connect_equipment'], true),
      autoSaveSequences: _parseBool(allSettings['auto_save_sequences'], true),
      confirmBeforeClosing: _parseBool(allSettings['confirm_before_closing'], true),
      autoDiscoverOnLaunch: _parseBool(allSettings['auto_discover_on_launch'], true),

      // Appearance
      theme: allSettings['theme'] ?? 'dark',
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
      fileNamingPattern: allSettings['file_naming_pattern'] ?? r'$TARGET_$FILTER_$DATE_$SEQ',
      bitDepth: allSettings['bit_depth'] ?? '16-bit',
      
      // Sequencer
      parkOnUnsafeWeather: _parseBool(allSettings['park_on_unsafe_weather'], true),
      parkBeforeDawn: _parseBool(allSettings['park_before_dawn'], true),
      meridianFlipMinutes: _parseInt(allSettings['meridian_flip_minutes'], 5),
      autoFocusOnFilterChange: _parseBool(allSettings['auto_focus_on_filter_change'], true),
      useFilterFocusOffsets: _parseBool(allSettings['use_filter_focus_offsets'], true),
      autoFocusEveryMinutes: _parseInt(allSettings['auto_focus_every_minutes'], 60),
      ditherEnabled: _parseBool(allSettings['dither_enabled'], true),
      ditherEveryFrames: _parseInt(allSettings['dither_every_frames'], 3),
      safetyFailMode: _parseSafetyFailMode(allSettings['safety_fail_mode']),

      // Plate Solving
      plateSolver: allSettings['plate_solver'] ?? 'ASTAP',
      astapPath: allSettings['astap_path'] ?? '',
      astrometryPath: allSettings['astrometry_path'] ?? '',
      plateSolveTimeout: _parseInt(allSettings['plate_solve_timeout'], 60),
      plateSolveSearchRadius: _parseDouble(allSettings['plate_solve_search_radius'], 30.0),
      blindSolve: _parseBool(allSettings['blind_solve'], false),

      // PHD2 Guiding
      phd2Path: allSettings['phd2_path'] ?? '',
      phd2Host: allSettings['phd2_host'] ?? 'localhost',
      phd2Port: _parseInt(allSettings['phd2_port'], 4400),
      
      // Notifications
      notificationsEnabled: _parseBool(allSettings['notifications_enabled'], true),
      discordWebhook: allSettings['discord_webhook'] ?? '',
      pushoverKey: allSettings['pushover_key'] ?? '',
      pushoverUser: allSettings['pushover_user'] ?? '',
      notifyOnSequenceComplete: _parseBool(allSettings['notify_on_sequence_complete'], true),
      notifyOnError: _parseBool(allSettings['notify_on_error'], true),
      notifyOnMeridianFlip: _parseBool(allSettings['notify_on_meridian_flip'], false),
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
      alpacaAutoDiscover: _parseBool(allSettings['alpaca_auto_discover'], false),

      // Sequencer Execution
      useNativeExecution: _parseBool(allSettings['use_native_execution'], true),
      useSimulationMode: _parseBool(allSettings['use_simulation_mode'], false),

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
    if (value == null) return SafetyFailMode.failOpen;
    return switch (value) {
      'failOpen' => SafetyFailMode.failOpen,
      'failClosed' => SafetyFailMode.failClosed,
      'warnOnly' => SafetyFailMode.warnOnly,
      _ => SafetyFailMode.failOpen,
    };
  }

  Future<void> _saveSetting(String key, String value) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(key, value);
  }

  Future<void> _saveSettings(Map<String, String> settings) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSettings(settings);
  }

  // ========== General Settings ==========
  
  Future<void> setStartMinimized(bool value) async {
    await _saveSetting('start_minimized', value.toString());
    state = AsyncData(state.value!.copyWith(startMinimized: value));
  }

  Future<void> setAutoConnectEquipment(bool value) async {
    await _saveSetting('auto_connect_equipment', value.toString());
    state = AsyncData(state.value!.copyWith(autoConnectEquipment: value));
  }

  Future<void> setAutoSaveSequences(bool value) async {
    await _saveSetting('auto_save_sequences', value.toString());
    state = AsyncData(state.value!.copyWith(autoSaveSequences: value));
  }

  Future<void> setConfirmBeforeClosing(bool value) async {
    await _saveSetting('confirm_before_closing', value.toString());
    state = AsyncData(state.value!.copyWith(confirmBeforeClosing: value));
  }

  Future<void> setAutoDiscoverOnLaunch(bool value) async {
    await _saveSetting('auto_discover_on_launch', value.toString());
    state = AsyncData(state.value!.copyWith(autoDiscoverOnLaunch: value));
  }

  // ========== Development Settings ==========

  // ========== Appearance Settings ==========

  Future<void> setTheme(String value) async {
    await _saveSetting('theme', value);
    state = AsyncData(state.value!.copyWith(theme: value));
  }

  Future<void> setAccentColor(String value) async {
    await _saveSetting('accent_color', value);
    state = AsyncData(state.value!.copyWith(accentColor: value));
  }

  Future<void> setFontSize(String value) async {
    await _saveSetting('font_size', value);
    state = AsyncData(state.value!.copyWith(fontSize: value));
  }

  Future<void> setSidebarCollapsed(bool value) async {
    await _saveSetting('sidebar_collapsed', value.toString());
    state = AsyncData(state.value!.copyWith(sidebarCollapsed: value));
  }

  // ========== Location Settings ==========

  Future<void> setLatitude(double value) async {
    await _saveSetting('observer_latitude', value.toString());
    state = AsyncData(state.value!.copyWith(latitude: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setLongitude(double value) async {
    await _saveSetting('observer_longitude', value.toString());
    state = AsyncData(state.value!.copyWith(longitude: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setElevation(double value) async {
    await _saveSetting('observer_elevation', value.toString());
    state = AsyncData(state.value!.copyWith(elevation: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setTimezone(String value) async {
    await _saveSetting('timezone', value);
    state = AsyncData(state.value!.copyWith(timezone: value));
  }

  Future<void> setUseSystemTime(bool value) async {
    await _saveSetting('use_system_time', value.toString());
    state = AsyncData(state.value!.copyWith(useSystemTime: value));
  }

  Future<void> updateLocation({
    double? latitude,
    double? longitude,
    double? elevation,
  }) async {
    final settings = <String, String>{};
    if (latitude != null) settings['observer_latitude'] = latitude.toString();
    if (longitude != null) settings['observer_longitude'] = longitude.toString();
    if (elevation != null) settings['observer_elevation'] = elevation.toString();
    
    if (settings.isNotEmpty) {
      await _saveSettings(settings);
      state = AsyncData(state.value!.copyWith(
        latitude: latitude,
        longitude: longitude,
        elevation: elevation,
      ));
    }
  }

  // ========== Imaging Settings ==========

  Future<void> setImageFormat(String value) async {
    await _saveSetting('image_format', value);
    state = AsyncData(state.value!.copyWith(imageFormat: value));
  }

  Future<void> setFileNamingPattern(String value) async {
    await _saveSetting('file_naming_pattern', value);
    state = AsyncData(state.value!.copyWith(fileNamingPattern: value));
  }

  Future<void> setBitDepth(String value) async {
    await _saveSetting('bit_depth', value);
    state = AsyncData(state.value!.copyWith(bitDepth: value));
  }

  // ========== Sequencer Settings ==========

  Future<void> setParkOnUnsafeWeather(bool value) async {
    await _saveSetting('park_on_unsafe_weather', value.toString());
    state = AsyncData(state.value!.copyWith(parkOnUnsafeWeather: value));
  }

  Future<void> setParkBeforeDawn(bool value) async {
    await _saveSetting('park_before_dawn', value.toString());
    state = AsyncData(state.value!.copyWith(parkBeforeDawn: value));
  }

  Future<void> setSafetyFailMode(SafetyFailMode value) async {
    await _saveSetting('safety_fail_mode', value.name);
    state = AsyncData(state.value!.copyWith(safetyFailMode: value));
  }

  Future<void> setMeridianFlipMinutes(int value) async {
    await _saveSetting('meridian_flip_minutes', value.toString());
    state = AsyncData(state.value!.copyWith(meridianFlipMinutes: value));
  }

  Future<void> setAutoFocusOnFilterChange(bool value) async {
    await _saveSetting('auto_focus_on_filter_change', value.toString());
    state = AsyncData(state.value!.copyWith(autoFocusOnFilterChange: value));
  }

  Future<void> setUseFilterFocusOffsets(bool value) async {
    await _saveSetting('use_filter_focus_offsets', value.toString());
    state = AsyncData(state.value!.copyWith(useFilterFocusOffsets: value));
  }

  Future<void> setAutoFocusEveryMinutes(int value) async {
    await _saveSetting('auto_focus_every_minutes', value.toString());
    state = AsyncData(state.value!.copyWith(autoFocusEveryMinutes: value));
  }

  Future<void> setDitherEnabled(bool value) async {
    await _saveSetting('dither_enabled', value.toString());
    state = AsyncData(state.value!.copyWith(ditherEnabled: value));
  }

  Future<void> setDitherEveryFrames(int value) async {
    await _saveSetting('dither_every_frames', value.toString());
    state = AsyncData(state.value!.copyWith(ditherEveryFrames: value));
  }

  Future<void> setUseNativeExecution(bool value) async {
    await _saveSetting('use_native_execution', value.toString());
    state = AsyncData(state.value!.copyWith(useNativeExecution: value));
  }

  Future<void> setUseSimulationMode(bool value) async {
    await _saveSetting('use_simulation_mode', value.toString());
    state = AsyncData(state.value!.copyWith(useSimulationMode: value));
  }

  // ========== Plate Solving Settings ==========

  Future<void> setPlateSolver(String value) async {
    await _saveSetting('plate_solver', value);
    state = AsyncData(state.value!.copyWith(plateSolver: value));
  }

  Future<void> setAstapPath(String value) async {
    await _saveSetting('astap_path', value);
    state = AsyncData(state.value!.copyWith(astapPath: value));
  }

  Future<void> setAstrometryPath(String value) async {
    await _saveSetting('astrometry_path', value);
    state = AsyncData(state.value!.copyWith(astrometryPath: value));
  }

  Future<void> setPlateSolveTimeout(int value) async {
    await _saveSetting('plate_solve_timeout', value.toString());
    state = AsyncData(state.value!.copyWith(plateSolveTimeout: value));
  }

  Future<void> setPlateSolveSearchRadius(double value) async {
    await _saveSetting('plate_solve_search_radius', value.toString());
    state = AsyncData(state.value!.copyWith(plateSolveSearchRadius: value));
  }

  Future<void> setBlindSolve(bool value) async {
    await _saveSetting('blind_solve', value.toString());
    state = AsyncData(state.value!.copyWith(blindSolve: value));
  }

  // ========== PHD2 Guiding Settings ==========

  Future<void> setPhd2Path(String value) async {
    await _saveSetting('phd2_path', value);
    state = AsyncData(state.value!.copyWith(phd2Path: value));
  }

  Future<void> setPhd2Host(String value) async {
    await _saveSetting('phd2_host', value);
    state = AsyncData(state.value!.copyWith(phd2Host: value));
  }

  Future<void> setPhd2Port(int value) async {
    await _saveSetting('phd2_port', value.toString());
    state = AsyncData(state.value!.copyWith(phd2Port: value));
  }

  // ========== Notification Settings ==========

  Future<void> setNotificationsEnabled(bool value) async {
    await _saveSetting('notifications_enabled', value.toString());
    state = AsyncData(state.value!.copyWith(notificationsEnabled: value));
  }

  Future<void> setDiscordWebhook(String value) async {
    await _saveSetting('discord_webhook', value);
    state = AsyncData(state.value!.copyWith(discordWebhook: value));
  }

  Future<void> setPushoverKey(String value) async {
    await _saveSetting('pushover_key', value);
    state = AsyncData(state.value!.copyWith(pushoverKey: value));
  }

  Future<void> setPushoverUser(String value) async {
    await _saveSetting('pushover_user', value);
    state = AsyncData(state.value!.copyWith(pushoverUser: value));
  }

  Future<void> setNotifyOnSequenceComplete(bool value) async {
    await _saveSetting('notify_on_sequence_complete', value.toString());
    state = AsyncData(state.value!.copyWith(notifyOnSequenceComplete: value));
  }

  Future<void> setNotifyOnError(bool value) async {
    await _saveSetting('notify_on_error', value.toString());
    state = AsyncData(state.value!.copyWith(notifyOnError: value));
  }

  Future<void> setNotifyOnMeridianFlip(bool value) async {
    await _saveSetting('notify_on_meridian_flip', value.toString());
    state = AsyncData(state.value!.copyWith(notifyOnMeridianFlip: value));
  }

  Future<void> setSoundEnabled(bool value) async {
    await _saveSetting('sound_enabled', value.toString());
    state = AsyncData(state.value!.copyWith(soundEnabled: value));
  }

  // ========== File Path Settings ==========

  Future<void> setImageOutputPath(String value) async {
    await _saveSetting('image_output_path', value);
    state = AsyncData(state.value!.copyWith(imageOutputPath: value));
  }

  Future<void> setSequencesPath(String value) async {
    await _saveSetting('sequences_path', value);
    state = AsyncData(state.value!.copyWith(sequencesPath: value));
  }

  Future<void> setDatabasePath(String value) async {
    await _saveSetting('database_path', value);
    state = AsyncData(state.value!.copyWith(databasePath: value));
  }

  Future<void> setLogsPath(String value) async {
    await _saveSetting('logs_path', value);
    state = AsyncData(state.value!.copyWith(logsPath: value));
  }

  // ========== Network/Protocol Settings ==========

  Future<void> setIndiServerHost(String value) async {
    await _saveSetting('indi_server_host', value);
    state = AsyncData(state.value!.copyWith(indiServerHost: value));
  }

  Future<void> setIndiServerPort(int value) async {
    await _saveSetting('indi_server_port', value.toString());
    state = AsyncData(state.value!.copyWith(indiServerPort: value));
  }

  Future<void> setIndiAutoConnect(bool value) async {
    await _saveSetting('indi_auto_connect', value.toString());
    state = AsyncData(state.value!.copyWith(indiAutoConnect: value));
  }

  Future<void> setAlpacaServerHost(String value) async {
    await _saveSetting('alpaca_server_host', value);
    state = AsyncData(state.value!.copyWith(alpacaServerHost: value));
  }

  Future<void> setAlpacaServerPort(int value) async {
    await _saveSetting('alpaca_server_port', value.toString());
    state = AsyncData(state.value!.copyWith(alpacaServerPort: value));
  }

  Future<void> setAlpacaAutoDiscover(bool value) async {
    await _saveSetting('alpaca_auto_discover', value.toString());
    state = AsyncData(state.value!.copyWith(alpacaAutoDiscover: value));
  }

  // Equipment Settings - Camera
  Future<void> setCoolingBehavior(String value) async {
    await _saveSetting('cooling_behavior', value);
    state = AsyncData(state.value!.copyWith(coolingBehavior: value));
  }

  Future<void> setDefaultGain(int value) async {
    await _saveSetting('default_gain', value.toString());
    state = AsyncData(state.value!.copyWith(defaultGain: value));
  }

  Future<void> setDefaultOffset(int value) async {
    await _saveSetting('default_offset', value.toString());
    state = AsyncData(state.value!.copyWith(defaultOffset: value));
  }

  // Equipment Settings - Mount
  Future<void> setEnableMeridianFlip(bool value) async {
    await _saveSetting('enable_meridian_flip', value.toString());
    state = AsyncData(state.value!.copyWith(enableMeridianFlip: value));
  }

  // Equipment Settings - Focuser
  Future<void> setTempCompensation(bool value) async {
    await _saveSetting('temp_compensation', value.toString());
    state = AsyncData(state.value!.copyWith(tempCompensation: value));
  }

  Future<void> setTempCoefficient(double value) async {
    await _saveSetting('temp_coefficient', value.toString());
    state = AsyncData(state.value!.copyWith(tempCoefficient: value));
  }

  Future<void> setBacklashCompensation(int value) async {
    await _saveSetting('backlash_compensation', value.toString());
    state = AsyncData(state.value!.copyWith(backlashCompensation: value));
  }

  // Equipment Settings - Guider
  Future<void> setDitherScale(String value) async {
    await _saveSetting('dither_scale', value);
    state = AsyncData(state.value!.copyWith(ditherScale: value));
  }

  Future<void> setSettleThreshold(double value) async {
    await _saveSetting('settle_threshold', value.toString());
    state = AsyncData(state.value!.copyWith(settleThreshold: value));
  }

  Future<void> setSettleTimeout(int value) async {
    await _saveSetting('settle_timeout', value.toString());
    state = AsyncData(state.value!.copyWith(settleTimeout: value));
  }
}

/// Main app settings provider
final appSettingsProvider = AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(() {
  return AppSettingsNotifier();
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

final locationSettingsProvider = AsyncNotifierProvider<LocationSettingsNotifier, LocationSettings>(() {
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
    final filePattern = await dao.getSetting('file_pattern') ?? r'$DATE_$TARGET_$FILTER_$EXPOSURE_###';
    final includeTimestamp = (await dao.getSetting('include_timestamp') ?? 'true') == 'true';
    final includeFilter = (await dao.getSetting('include_filter') ?? 'true') == 'true';
    
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
    if (includeTimestamp != null) settings['include_timestamp'] = includeTimestamp.toString();
    if (includeFilter != null) settings['include_filter'] = includeFilter.toString();
    
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

final outputSettingsProvider = AsyncNotifierProvider<OutputSettingsNotifier, OutputSettings>(() {
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
    final autoSolve = (await dao.getSetting('plate_solve_auto') ?? 'true') == 'true';
    final searchRadiusStr = await dao.getSetting('plate_solve_radius') ?? '30.0';
    
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
    if (timeoutSeconds != null) settings['plate_solve_timeout'] = timeoutSeconds.toString();
    if (autoSolve != null) settings['plate_solve_auto'] = autoSolve.toString();
    if (searchRadius != null) settings['plate_solve_radius'] = searchRadius.toString();
    
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

final plateSolveSettingsProvider = AsyncNotifierProvider<PlateSolveSettingsNotifier, PlateSolveSettings>(() {
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

final themeSettingsProvider = AsyncNotifierProvider<ThemeSettingsNotifier, String>(() {
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

final autoConnectSettingsProvider = AsyncNotifierProvider<AutoConnectSettingsNotifier, bool>(() {
  return AutoConnectSettingsNotifier();
});

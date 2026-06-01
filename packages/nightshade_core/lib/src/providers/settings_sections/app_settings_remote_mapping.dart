part of '../settings_provider.dart';

extension _AppSettingsRemoteMapping on AppSettingsNotifier {
  AppSettingsState _fromRemoteSettings(models.AppSettings remote) {
    final location = remote.location;
    return AppSettingsState(
      autoConnectEquipment: remote.autoConnect,
      autoDiscoverOnLaunch: remote.autoDiscoverOnLaunch,
      theme: remote.theme,
      language: remote.language,
      accentColor: remote.accentColor.isEmpty
          ? kDefaultAccentColorHex
          : remote.accentColor,
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

  /// Translate a single JSON-shaped `(key, value)` from the server into
  /// a copyWith on the in-memory [AppSettingsState]. Unknown keys are a
  /// no-op (a newer host may carry settings this build does not yet
  /// know about â€” silent skipping preserves forward-compatibility).
  ///
  /// Returns null when the value parses to something the current state
  /// already has â€” caller checks for that to avoid pointless rebuilds.
  AppSettingsState? _applyJsonSettingChange(
    AppSettingsState current,
    String key,
    dynamic value,
  ) {
    // The keys mirror `models.AppSettings.toJson()` â€” which is the freezed
    // JSON projection â€” NOT the database column names. The settings provider
    // already has `_applySettingsMap` for the db-column form; here we only
    // need to handle the remote-JSON form for the keys that round-trip.
    switch (key) {
      case 'theme':
        return value is String ? current.copyWith(theme: value) : null;
      case 'language':
        return value is String ? current.copyWith(language: value) : null;
      case 'autoConnect':
        return value is bool
            ? current.copyWith(autoConnectEquipment: value)
            : null;
      case 'autoDiscoverOnLaunch':
        return value is bool
            ? current.copyWith(autoDiscoverOnLaunch: value)
            : null;
      case 'latitude':
        return value is num
            ? current.copyWith(latitude: value.toDouble())
            : null;
      case 'longitude':
        return value is num
            ? current.copyWith(longitude: value.toDouble())
            : null;
      case 'elevation':
        return value is num
            ? current.copyWith(elevation: value.toDouble())
            : null;
      case 'fileNamingPattern':
        return value is String
            ? current.copyWith(fileNamingPattern: value)
            : null;
      case 'meridianFlipMinutes':
        return value is num
            ? current.copyWith(meridianFlipMinutes: value.toInt())
            : null;
      case 'autoFocusEveryMinutes':
        return value is num
            ? current.copyWith(autoFocusEveryMinutes: value.toInt())
            : null;
      case 'ditherEveryFrames':
        return value is num
            ? current.copyWith(ditherEveryFrames: value.toInt())
            : null;
      case 'plateSolveTimeout':
        return value is num
            ? current.copyWith(plateSolveTimeout: value.toInt())
            : null;
      case 'plateSolveSearchRadius':
        return value is num
            ? current.copyWith(plateSolveSearchRadius: value.toDouble())
            : null;
      case 'accentColor':
        return value is String ? current.copyWith(accentColor: value) : null;
      case 'fontSize':
        return value is String ? current.copyWith(fontSize: value) : null;
      case 'uiScale':
        return value is String ? current.copyWith(uiScale: value) : null;
      case 'discordWebhook':
        return value is String ? current.copyWith(discordWebhook: value) : null;
      case 'pushoverKey':
        return value is String ? current.copyWith(pushoverKey: value) : null;
      case 'pushoverUser':
        return value is String ? current.copyWith(pushoverUser: value) : null;
      case 'astapPath':
        return value is String ? current.copyWith(astapPath: value) : null;
      case 'indiServerHost':
        return value is String ? current.copyWith(indiServerHost: value) : null;
      case 'indiServerPort':
        return value is num
            ? current.copyWith(indiServerPort: value.toInt())
            : null;
      case 'indiAutoConnect':
        return value is bool ? current.copyWith(indiAutoConnect: value) : null;
      case 'alpacaServerHost':
        return value is String
            ? current.copyWith(alpacaServerHost: value)
            : null;
      case 'alpacaServerPort':
        return value is num
            ? current.copyWith(alpacaServerPort: value.toInt())
            : null;
      case 'alpacaAutoDiscover':
        return value is bool
            ? current.copyWith(alpacaAutoDiscover: value)
            : null;
      case 'useNativeExecution':
        return value is bool
            ? current.copyWith(useNativeExecution: value)
            : null;
      case 'useSimulationMode':
        return value is bool
            ? current.copyWith(useSimulationMode: value)
            : null;
      case 'imageOutputPath':
        return value is String
            ? current.copyWith(imageOutputPath: value)
            : null;
      case 'safetyFailMode':
        if (value is String) {
          return current.copyWith(
            safetyFailMode: _parseSafetyFailMode(value),
          );
        }
        return null;
      default:
        // Forward-compat: a newer host may emit settings this build
        // does not yet have a copyWith for. The persisted snapshot
        // captures the value (above) so a subsequent rebuild still
        // sees it via `_fromRemoteSettings`.
        return null;
    }
  }
}

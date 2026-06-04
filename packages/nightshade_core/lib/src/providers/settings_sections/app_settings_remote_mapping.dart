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
      // Wave 3 Image Grading — carried by the wire model so an unattended
      // night driven from a phone keeps its Pass/Reject thresholds.
      enableImageGrading: remote.enableImageGrading,
      imageGradingHfrThresholdPx: remote.imageGradingHfrThresholdPx,
      imageGradingHfrBaselinePercent: remote.imageGradingHfrBaselinePercent,
      imageGradingEccentricityThreshold:
          remote.imageGradingEccentricityThreshold,
      imageGradingStarCountMin: remote.imageGradingStarCountMin,
      imageGradingMaxConsecutiveRejects:
          remote.imageGradingMaxConsecutiveRejects,
      imageGradingRejectFolderPath: remote.imageGradingRejectFolderPath,
      // Wave 5 Sky-brightness adaptive exposure — global defaults + per-filter
      // overrides round-trip so adaptive subs work when planned remotely.
      adaptiveExposureEnabled: remote.adaptiveExposureEnabled,
      adaptiveExposureTargetSnr: remote.adaptiveExposureTargetSnr,
      adaptiveExposureReferenceMag: remote.adaptiveExposureReferenceMag,
      adaptiveExposureMinSecs: remote.adaptiveExposureMinSecs,
      adaptiveExposureMaxSecs: remote.adaptiveExposureMaxSecs,
      adaptiveExposurePerFilterEnabled:
          Map<String, bool>.from(remote.adaptiveExposurePerFilterEnabled),
      adaptiveExposurePerFilterMinSecs:
          Map<String, double>.from(remote.adaptiveExposurePerFilterMinSecs),
      adaptiveExposurePerFilterMaxSecs:
          Map<String, double>.from(remote.adaptiveExposurePerFilterMaxSecs),
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
      // Wave 3 Image Grading — push the live thresholds to the host so a
      // remote save doesn't silently revert them to model defaults.
      enableImageGrading: settings.enableImageGrading,
      imageGradingHfrThresholdPx: settings.imageGradingHfrThresholdPx,
      imageGradingHfrBaselinePercent: settings.imageGradingHfrBaselinePercent,
      imageGradingEccentricityThreshold:
          settings.imageGradingEccentricityThreshold,
      imageGradingStarCountMin: settings.imageGradingStarCountMin,
      imageGradingMaxConsecutiveRejects:
          settings.imageGradingMaxConsecutiveRejects,
      imageGradingRejectFolderPath: settings.imageGradingRejectFolderPath,
      // Wave 5 Sky-brightness adaptive exposure.
      adaptiveExposureEnabled: settings.adaptiveExposureEnabled,
      adaptiveExposureTargetSnr: settings.adaptiveExposureTargetSnr,
      adaptiveExposureReferenceMag: settings.adaptiveExposureReferenceMag,
      adaptiveExposureMinSecs: settings.adaptiveExposureMinSecs,
      adaptiveExposureMaxSecs: settings.adaptiveExposureMaxSecs,
      adaptiveExposurePerFilterEnabled:
          Map<String, bool>.from(settings.adaptiveExposurePerFilterEnabled),
      adaptiveExposurePerFilterMinSecs:
          Map<String, double>.from(settings.adaptiveExposurePerFilterMinSecs),
      adaptiveExposurePerFilterMaxSecs:
          Map<String, double>.from(settings.adaptiveExposurePerFilterMaxSecs),
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
      // Wave 3 Image Grading — keys mirror models.AppSettings.toJson().
      // The nullable threshold fields accept `null` explicitly (user cleared
      // the field) which copyWith honours via its `_unset` sentinel pattern.
      case 'enableImageGrading':
        return value is bool
            ? current.copyWith(enableImageGrading: value)
            : null;
      case 'imageGradingHfrThresholdPx':
        if (value == null) {
          return current.copyWith(imageGradingHfrThresholdPx: null);
        }
        return value is num
            ? current.copyWith(imageGradingHfrThresholdPx: value.toDouble())
            : null;
      case 'imageGradingHfrBaselinePercent':
        if (value == null) {
          return current.copyWith(imageGradingHfrBaselinePercent: null);
        }
        return value is num
            ? current.copyWith(
                imageGradingHfrBaselinePercent: value.toDouble())
            : null;
      case 'imageGradingEccentricityThreshold':
        if (value == null) {
          return current.copyWith(imageGradingEccentricityThreshold: null);
        }
        return value is num
            ? current.copyWith(
                imageGradingEccentricityThreshold: value.toDouble())
            : null;
      case 'imageGradingStarCountMin':
        if (value == null) {
          return current.copyWith(imageGradingStarCountMin: null);
        }
        return value is num
            ? current.copyWith(imageGradingStarCountMin: value.toInt())
            : null;
      case 'imageGradingMaxConsecutiveRejects':
        return value is num
            ? current.copyWith(
                imageGradingMaxConsecutiveRejects: value.toInt())
            : null;
      case 'imageGradingRejectFolderPath':
        if (value == null) {
          return current.copyWith(imageGradingRejectFolderPath: null);
        }
        return value is String
            ? current.copyWith(imageGradingRejectFolderPath: value)
            : null;
      // Wave 5 Sky-brightness adaptive exposure.
      case 'adaptiveExposureEnabled':
        return value is bool
            ? current.copyWith(adaptiveExposureEnabled: value)
            : null;
      case 'adaptiveExposureTargetSnr':
        return value is num
            ? current.copyWith(adaptiveExposureTargetSnr: value.toDouble())
            : null;
      case 'adaptiveExposureReferenceMag':
        return value is num
            ? current.copyWith(adaptiveExposureReferenceMag: value.toDouble())
            : null;
      case 'adaptiveExposureMinSecs':
        return value is num
            ? current.copyWith(adaptiveExposureMinSecs: value.toDouble())
            : null;
      case 'adaptiveExposureMaxSecs':
        return value is num
            ? current.copyWith(adaptiveExposureMaxSecs: value.toDouble())
            : null;
      case 'adaptiveExposurePerFilterEnabled':
        return value is Map
            ? current.copyWith(
                adaptiveExposurePerFilterEnabled: value.map(
                  (k, v) => MapEntry(k.toString(), v == true),
                ),
              )
            : null;
      case 'adaptiveExposurePerFilterMinSecs':
        return value is Map
            ? current.copyWith(
                adaptiveExposurePerFilterMinSecs: value.map(
                  (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
                ),
              )
            : null;
      case 'adaptiveExposurePerFilterMaxSecs':
        return value is Map
            ? current.copyWith(
                adaptiveExposurePerFilterMaxSecs: value.map(
                  (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
                ),
              )
            : null;
      default:
        // Forward-compat: a newer host may emit settings this build
        // does not yet have a copyWith for. The persisted snapshot
        // captures the value (above) so a subsequent rebuild still
        // sees it via `_fromRemoteSettings`.
        return null;
    }
  }
}

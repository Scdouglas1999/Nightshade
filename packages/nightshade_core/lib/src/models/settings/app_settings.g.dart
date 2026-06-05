// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ObserverLocationImpl _$$ObserverLocationImplFromJson(
        Map<String, dynamic> json) =>
    _$ObserverLocationImpl(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      elevation: (json['elevation'] as num).toDouble(),
    );

Map<String, dynamic> _$$ObserverLocationImplToJson(
        _$ObserverLocationImpl instance) =>
    <String, dynamic>{
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'elevation': instance.elevation,
    };

_$AppSettingsImpl _$$AppSettingsImplFromJson(Map<String, dynamic> json) =>
    _$AppSettingsImpl(
      location: json['location'] == null
          ? null
          : ObserverLocation.fromJson(json['location'] as Map<String, dynamic>),
      theme: json['theme'] as String? ?? 'dark',
      language: json['language'] as String? ?? 'en',
      autoConnect: json['autoConnect'] as bool? ?? true,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      elevation: (json['elevation'] as num?)?.toDouble() ?? 0.0,
      fileNamingPattern: json['fileNamingPattern'] as String? ?? '',
      meridianFlipMinutes: (json['meridianFlipMinutes'] as num?)?.toInt() ?? 5,
      autoFocusEveryMinutes:
          (json['autoFocusEveryMinutes'] as num?)?.toInt() ?? 60,
      ditherEveryFrames: (json['ditherEveryFrames'] as num?)?.toInt() ?? 3,
      plateSolveTimeout: (json['plateSolveTimeout'] as num?)?.toInt() ?? 60,
      plateSolveSearchRadius:
          (json['plateSolveSearchRadius'] as num?)?.toDouble() ?? 30.0,
      discordWebhook: json['discordWebhook'] as String? ?? '',
      pushoverKey: json['pushoverKey'] as String? ?? '',
      pushoverUser: json['pushoverUser'] as String? ?? '',
      astapPath: json['astapPath'] as String? ?? '',
      autoDiscoverOnLaunch: json['autoDiscoverOnLaunch'] as bool? ?? true,
      accentColor: json['accentColor'] as String? ?? '',
      fontSize: json['fontSize'] as String? ?? 'Medium',
      uiScale: json['uiScale'] as String? ?? 'Auto',
      indiServerHost: json['indiServerHost'] as String? ?? 'localhost',
      indiServerPort: (json['indiServerPort'] as num?)?.toInt() ?? 7624,
      indiAutoConnect: json['indiAutoConnect'] as bool? ?? false,
      alpacaServerHost: json['alpacaServerHost'] as String? ?? 'localhost',
      alpacaServerPort: (json['alpacaServerPort'] as num?)?.toInt() ?? 11111,
      alpacaAutoDiscover: json['alpacaAutoDiscover'] as bool? ?? false,
      useNativeExecution: json['useNativeExecution'] as bool? ?? true,
      useSimulationMode: json['useSimulationMode'] as bool? ?? false,
      imageOutputPath: json['imageOutputPath'] as String? ?? '',
      observer: json['observer'] as String? ?? '',
      telescope: json['telescope'] as String? ?? '',
      instrument: json['instrument'] as String? ?? '',
      updateCheckEnabled: json['updateCheckEnabled'] as bool? ?? true,
      updateServerUrl: json['updateServerUrl'] as String? ?? '',
      updateChannel: json['updateChannel'] as String? ?? 'stable',
      updateCheckIntervalHours:
          (json['updateCheckIntervalHours'] as num?)?.toInt() ?? 24,
      skippedUpdateVersion: json['skippedUpdateVersion'] as String? ?? '',
      safetyFailMode: $enumDecodeNullable(
              _$SafetyFailModeEnumMap, json['safetyFailMode']) ??
          SafetyFailMode.failClosed,
      enableImageGrading: json['enableImageGrading'] as bool? ?? false,
      imageGradingHfrThresholdPx:
          (json['imageGradingHfrThresholdPx'] as num?)?.toDouble(),
      imageGradingHfrBaselinePercent:
          (json['imageGradingHfrBaselinePercent'] as num?)?.toDouble(),
      imageGradingEccentricityThreshold:
          (json['imageGradingEccentricityThreshold'] as num?)?.toDouble(),
      imageGradingStarCountMin:
          (json['imageGradingStarCountMin'] as num?)?.toInt(),
      imageGradingMaxConsecutiveRejects:
          (json['imageGradingMaxConsecutiveRejects'] as num?)?.toInt() ?? 3,
      imageGradingRejectFolderPath:
          json['imageGradingRejectFolderPath'] as String?,
      adaptiveExposureEnabled:
          json['adaptiveExposureEnabled'] as bool? ?? false,
      adaptiveExposureTargetSnr:
          (json['adaptiveExposureTargetSnr'] as num?)?.toDouble() ?? 30.0,
      adaptiveExposureReferenceMag:
          (json['adaptiveExposureReferenceMag'] as num?)?.toDouble() ?? 21.5,
      adaptiveExposureMinSecs:
          (json['adaptiveExposureMinSecs'] as num?)?.toDouble() ?? 5.0,
      adaptiveExposureMaxSecs:
          (json['adaptiveExposureMaxSecs'] as num?)?.toDouble() ?? 600.0,
      adaptiveExposurePerFilterEnabled:
          (json['adaptiveExposurePerFilterEnabled'] as Map<String, dynamic>?)
                  ?.map(
                (k, e) => MapEntry(k, e as bool),
              ) ??
              const <String, bool>{},
      adaptiveExposurePerFilterMinSecs:
          (json['adaptiveExposurePerFilterMinSecs'] as Map<String, dynamic>?)
                  ?.map(
                (k, e) => MapEntry(k, (e as num).toDouble()),
              ) ??
              const <String, double>{},
      adaptiveExposurePerFilterMaxSecs:
          (json['adaptiveExposurePerFilterMaxSecs'] as Map<String, dynamic>?)
                  ?.map(
                (k, e) => MapEntry(k, (e as num).toDouble()),
              ) ??
              const <String, double>{},
      parkOnUnsafeWeather: json['parkOnUnsafeWeather'] as bool? ?? true,
      autoFocusOnFilterChange: json['autoFocusOnFilterChange'] as bool? ?? true,
      afDisableGuidingDuringAf:
          json['afDisableGuidingDuringAf'] as bool? ?? false,
      ditherEnabled: json['ditherEnabled'] as bool? ?? true,
      ditherScale: json['ditherScale'] as String? ?? 'Medium',
      recoveryDefaultRetryIntervalMins:
          (json['recoveryDefaultRetryIntervalMins'] as num?)?.toDouble() ??
              10.0,
      recoveryDefaultMaxDurationMins:
          (json['recoveryDefaultMaxDurationMins'] as num?)?.toDouble() ?? 90.0,
      recoveryStopTrackingDuringRecovery:
          json['recoveryStopTrackingDuringRecovery'] as bool? ?? true,
      recoveryAbortOnMeridian: json['recoveryAbortOnMeridian'] as bool? ?? true,
      recoveryAudibleAlertWhenEntered:
          json['recoveryAudibleAlertWhenEntered'] as bool? ?? true,
      parkBeforeDawn: json['parkBeforeDawn'] as bool? ?? true,
      enableMeridianFlip: json['enableMeridianFlip'] as bool? ?? true,
      tempCompensation: json['tempCompensation'] as bool? ?? true,
      tempCoefficient: (json['tempCoefficient'] as num?)?.toDouble() ?? -12.0,
      backlashCompensation:
          (json['backlashCompensation'] as num?)?.toInt() ?? 0,
      settleThreshold: (json['settleThreshold'] as num?)?.toDouble() ?? 0.5,
      settleTimeout: (json['settleTimeout'] as num?)?.toInt() ?? 30,
      plateSolver: json['plateSolver'] as String? ?? 'ASTAP',
      blindSolve: json['blindSolve'] as bool? ?? false,
      bortleClass: (json['bortleClass'] as num?)?.toInt() ?? 5,
      effectiveHorizonDeg:
          (json['effectiveHorizonDeg'] as num?)?.toDouble() ?? 0.0,
      preflightStrictness: json['preflightStrictness'] as String? ?? 'normal',
      polarAlignmentMaxAgeDays:
          (json['polarAlignmentMaxAgeDays'] as num?)?.toInt() ?? 7,
      opticalTrainDriftThreshold:
          (json['opticalTrainDriftThreshold'] as num?)?.toDouble() ?? 8.0,
      darkLibraryMinCoverage:
          (json['darkLibraryMinCoverage'] as num?)?.toInt() ?? 10,
      smartNightMaxSessionHours:
          (json['smartNightMaxSessionHours'] as num?)?.toDouble(),
      smartNightDefaultAfCadenceFrames:
          (json['smartNightDefaultAfCadenceFrames'] as num?)?.toInt() ?? 25,
      smartNightDefaultIntegrationBudgetMinsPerTarget:
          (json['smartNightDefaultIntegrationBudgetMinsPerTarget'] as num?)
                  ?.toInt() ??
              240,
      smartNightIncludeFlatsAtEnd:
          json['smartNightIncludeFlatsAtEnd'] as bool? ?? true,
      smartNightUseSchedulerForMultiTarget:
          json['smartNightUseSchedulerForMultiTarget'] as bool? ?? true,
      smartNightSchedulerTargetThreshold:
          (json['smartNightSchedulerTargetThreshold'] as num?)?.toInt() ?? 3,
      smartNightDefaultStrategy:
          json['smartNightDefaultStrategy'] as String? ?? 'auto_lrgb',
      smartNightPolarAlignmentStaleAfterDays:
          (json['smartNightPolarAlignmentStaleAfterDays'] as num?)?.toInt() ??
              7,
      smartNightSubExposureFloorSecs:
          (json['smartNightSubExposureFloorSecs'] as num?)?.toDouble() ?? 30.0,
      smartNightSubExposureCeilingSecs:
          (json['smartNightSubExposureCeilingSecs'] as num?)?.toDouble() ??
              300.0,
      smartNightTargetSnr:
          (json['smartNightTargetSnr'] as num?)?.toDouble() ?? 30.0,
    );

Map<String, dynamic> _$$AppSettingsImplToJson(_$AppSettingsImpl instance) =>
    <String, dynamic>{
      'location': instance.location,
      'theme': instance.theme,
      'language': instance.language,
      'autoConnect': instance.autoConnect,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'elevation': instance.elevation,
      'fileNamingPattern': instance.fileNamingPattern,
      'meridianFlipMinutes': instance.meridianFlipMinutes,
      'autoFocusEveryMinutes': instance.autoFocusEveryMinutes,
      'ditherEveryFrames': instance.ditherEveryFrames,
      'plateSolveTimeout': instance.plateSolveTimeout,
      'plateSolveSearchRadius': instance.plateSolveSearchRadius,
      'discordWebhook': instance.discordWebhook,
      'pushoverKey': instance.pushoverKey,
      'pushoverUser': instance.pushoverUser,
      'astapPath': instance.astapPath,
      'autoDiscoverOnLaunch': instance.autoDiscoverOnLaunch,
      'accentColor': instance.accentColor,
      'fontSize': instance.fontSize,
      'uiScale': instance.uiScale,
      'indiServerHost': instance.indiServerHost,
      'indiServerPort': instance.indiServerPort,
      'indiAutoConnect': instance.indiAutoConnect,
      'alpacaServerHost': instance.alpacaServerHost,
      'alpacaServerPort': instance.alpacaServerPort,
      'alpacaAutoDiscover': instance.alpacaAutoDiscover,
      'useNativeExecution': instance.useNativeExecution,
      'useSimulationMode': instance.useSimulationMode,
      'imageOutputPath': instance.imageOutputPath,
      'observer': instance.observer,
      'telescope': instance.telescope,
      'instrument': instance.instrument,
      'updateCheckEnabled': instance.updateCheckEnabled,
      'updateServerUrl': instance.updateServerUrl,
      'updateChannel': instance.updateChannel,
      'updateCheckIntervalHours': instance.updateCheckIntervalHours,
      'skippedUpdateVersion': instance.skippedUpdateVersion,
      'safetyFailMode': _$SafetyFailModeEnumMap[instance.safetyFailMode]!,
      'enableImageGrading': instance.enableImageGrading,
      'imageGradingHfrThresholdPx': instance.imageGradingHfrThresholdPx,
      'imageGradingHfrBaselinePercent': instance.imageGradingHfrBaselinePercent,
      'imageGradingEccentricityThreshold':
          instance.imageGradingEccentricityThreshold,
      'imageGradingStarCountMin': instance.imageGradingStarCountMin,
      'imageGradingMaxConsecutiveRejects':
          instance.imageGradingMaxConsecutiveRejects,
      'imageGradingRejectFolderPath': instance.imageGradingRejectFolderPath,
      'adaptiveExposureEnabled': instance.adaptiveExposureEnabled,
      'adaptiveExposureTargetSnr': instance.adaptiveExposureTargetSnr,
      'adaptiveExposureReferenceMag': instance.adaptiveExposureReferenceMag,
      'adaptiveExposureMinSecs': instance.adaptiveExposureMinSecs,
      'adaptiveExposureMaxSecs': instance.adaptiveExposureMaxSecs,
      'adaptiveExposurePerFilterEnabled':
          instance.adaptiveExposurePerFilterEnabled,
      'adaptiveExposurePerFilterMinSecs':
          instance.adaptiveExposurePerFilterMinSecs,
      'adaptiveExposurePerFilterMaxSecs':
          instance.adaptiveExposurePerFilterMaxSecs,
      'parkOnUnsafeWeather': instance.parkOnUnsafeWeather,
      'autoFocusOnFilterChange': instance.autoFocusOnFilterChange,
      'afDisableGuidingDuringAf': instance.afDisableGuidingDuringAf,
      'ditherEnabled': instance.ditherEnabled,
      'ditherScale': instance.ditherScale,
      'recoveryDefaultRetryIntervalMins':
          instance.recoveryDefaultRetryIntervalMins,
      'recoveryDefaultMaxDurationMins': instance.recoveryDefaultMaxDurationMins,
      'recoveryStopTrackingDuringRecovery':
          instance.recoveryStopTrackingDuringRecovery,
      'recoveryAbortOnMeridian': instance.recoveryAbortOnMeridian,
      'recoveryAudibleAlertWhenEntered':
          instance.recoveryAudibleAlertWhenEntered,
      'parkBeforeDawn': instance.parkBeforeDawn,
      'enableMeridianFlip': instance.enableMeridianFlip,
      'tempCompensation': instance.tempCompensation,
      'tempCoefficient': instance.tempCoefficient,
      'backlashCompensation': instance.backlashCompensation,
      'settleThreshold': instance.settleThreshold,
      'settleTimeout': instance.settleTimeout,
      'plateSolver': instance.plateSolver,
      'blindSolve': instance.blindSolve,
      'bortleClass': instance.bortleClass,
      'effectiveHorizonDeg': instance.effectiveHorizonDeg,
      'preflightStrictness': instance.preflightStrictness,
      'polarAlignmentMaxAgeDays': instance.polarAlignmentMaxAgeDays,
      'opticalTrainDriftThreshold': instance.opticalTrainDriftThreshold,
      'darkLibraryMinCoverage': instance.darkLibraryMinCoverage,
      'smartNightMaxSessionHours': instance.smartNightMaxSessionHours,
      'smartNightDefaultAfCadenceFrames':
          instance.smartNightDefaultAfCadenceFrames,
      'smartNightDefaultIntegrationBudgetMinsPerTarget':
          instance.smartNightDefaultIntegrationBudgetMinsPerTarget,
      'smartNightIncludeFlatsAtEnd': instance.smartNightIncludeFlatsAtEnd,
      'smartNightUseSchedulerForMultiTarget':
          instance.smartNightUseSchedulerForMultiTarget,
      'smartNightSchedulerTargetThreshold':
          instance.smartNightSchedulerTargetThreshold,
      'smartNightDefaultStrategy': instance.smartNightDefaultStrategy,
      'smartNightPolarAlignmentStaleAfterDays':
          instance.smartNightPolarAlignmentStaleAfterDays,
      'smartNightSubExposureFloorSecs': instance.smartNightSubExposureFloorSecs,
      'smartNightSubExposureCeilingSecs':
          instance.smartNightSubExposureCeilingSecs,
      'smartNightTargetSnr': instance.smartNightTargetSnr,
    };

const _$SafetyFailModeEnumMap = {
  SafetyFailMode.failOpen: 'failOpen',
  SafetyFailMode.failClosed: 'failClosed',
  SafetyFailMode.warnOnly: 'warnOnly',
};

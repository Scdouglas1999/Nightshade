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
    };

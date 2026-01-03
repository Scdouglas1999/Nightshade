// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WeatherStatusImpl _$$WeatherStatusImplFromJson(Map<String, dynamic> json) =>
    _$WeatherStatusImpl(
      currentLevel:
          $enumDecodeNullable(_$AlertLevelEnumMap, json['currentLevel']) ??
              AlertLevel.clear,
      activeAlert: json['activeAlert'] == null
          ? null
          : WeatherAlert.fromJson(json['activeAlert'] as Map<String, dynamic>),
      motion: json['motion'] == null
          ? null
          : CloudMotion.fromJson(json['motion'] as Map<String, dynamic>),
      radarFrames: (json['radarFrames'] as List<dynamic>?)
              ?.map((e) => RadarFrame.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      currentFrameIndex: (json['currentFrameIndex'] as num?)?.toInt() ?? 0,
      lastUpdate: DateTime.parse(json['lastUpdate'] as String),
      isLoading: json['isLoading'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
    );

Map<String, dynamic> _$$WeatherStatusImplToJson(_$WeatherStatusImpl instance) =>
    <String, dynamic>{
      'currentLevel': _$AlertLevelEnumMap[instance.currentLevel]!,
      'activeAlert': instance.activeAlert,
      'motion': instance.motion,
      'radarFrames': instance.radarFrames,
      'currentFrameIndex': instance.currentFrameIndex,
      'lastUpdate': instance.lastUpdate.toIso8601String(),
      'isLoading': instance.isLoading,
      'errorMessage': instance.errorMessage,
    };

const _$AlertLevelEnumMap = {
  AlertLevel.clear: 'clear',
  AlertLevel.watch: 'watch',
  AlertLevel.warning: 'warning',
  AlertLevel.critical: 'critical',
};
